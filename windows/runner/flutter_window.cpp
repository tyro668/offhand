#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <optional>
#include <shellapi.h>
#include <string>
#include <windowsx.h>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr wchar_t kOverlayWindowClassName[] = L"VOICE_TYPE_OVERLAY_WINDOW";

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return L"";
  }
  int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  if (size <= 0) {
    return L"";
  }
  std::wstring result(size - 1, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, result.data(), size);
  return result;
}

std::string OverlayStatusText(const std::string& state) {
  if (state == "starting") {
    return "Mic starting";
  }
  if (state == "recording") {
    return "Recording";
  }
  if (state == "transcribing") {
    return "Transcribing";
  }
  if (state == "enhancing") {
    return "Enhancing";
  }
  if (state == "transcribe_failed") {
    return "Transcribe failed";
  }
  return "";
}

bool IsVirtualKeyPressed(int vk) {
  return (GetAsyncKeyState(vk) & 0x8000) != 0;
}

bool MatchHotkeyModifiers(int required_modifiers) {
  int active_modifiers = 0;
  if (IsVirtualKeyPressed(VK_CONTROL)) {
    active_modifiers |= MOD_CONTROL;
  }
  if (IsVirtualKeyPressed(VK_MENU)) {
    active_modifiers |= MOD_ALT;
  }
  if (IsVirtualKeyPressed(VK_SHIFT)) {
    active_modifiers |= MOD_SHIFT;
  }
  if (IsVirtualKeyPressed(VK_LWIN) || IsVirtualKeyPressed(VK_RWIN)) {
    active_modifiers |= MOD_WIN;
  }
  return active_modifiers == required_modifiers;
}

int CurrentHotkeyModifiers() {
  int modifiers = 0;
  if (IsVirtualKeyPressed(VK_CONTROL)) {
    modifiers |= MOD_CONTROL;
  }
  if (IsVirtualKeyPressed(VK_MENU)) {
    modifiers |= MOD_ALT;
  }
  if (IsVirtualKeyPressed(VK_SHIFT)) {
    modifiers |= MOD_SHIFT;
  }
  if (IsVirtualKeyPressed(VK_LWIN) || IsVirtualKeyPressed(VK_RWIN)) {
    modifiers |= MOD_WIN;
  }
  return modifiers;
}

template <typename T>
std::optional<T> GetMapValue(const flutter::EncodableMap& map,
                             const std::string& key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) {
    return std::nullopt;
  }
  if (const auto* value = std::get_if<T>(&it->second)) {
    return *value;
  }
  return std::nullopt;
}

double GetDoubleValue(const flutter::EncodableMap& map, const std::string& key,
                      double fallback) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) {
    return fallback;
  }
  if (const auto* value = std::get_if<double>(&it->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int32_t>(&it->second)) {
    return static_cast<double>(*value);
  }
  if (const auto* value = std::get_if<int64_t>(&it->second)) {
    return static_cast<double>(*value);
  }
  return fallback;
}

}  // namespace

FlutterWindow* FlutterWindow::instance_ = nullptr;

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetupMethodChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  instance_ = this;
  InitializeTrayIcon();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  HideOverlay();
  if (overlay_window_) {
    DestroyWindow(overlay_window_);
    overlay_window_ = nullptr;
  }
  UnregisterGlobalHotkey();
  instance_ = nullptr;

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

bool FlutterWindow::SetupMethodChannel() {
  auto* messenger = flutter_controller_->engine()->messenger();
  if (messenger == nullptr) {
    return false;
  }

  method_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "com.voicetype/overlay",
      &flutter::StandardMethodCodec::GetInstance());

  method_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleMethodCall(call, std::move(result)); });
  return true;
}

void FlutterWindow::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();

  const flutter::EncodableMap* args = nullptr;
  if (call.arguments() != nullptr) {
    args = std::get_if<flutter::EncodableMap>(call.arguments());
  }

  if (method == "showOverlay") {
    std::string state = "recording";
    std::string duration = "00:00";
    std::string state_label;
    double level = 0.0;
    if (args != nullptr) {
      state = GetMapValue<std::string>(*args, "state").value_or(state);
      duration =
          GetMapValue<std::string>(*args, "duration").value_or(duration);
      state_label =
          GetMapValue<std::string>(*args, "stateLabel").value_or("");
      level = GetDoubleValue(*args, "level", 0.0);
    }
    ShowOverlay(state, duration, level, state_label);
    result->Success();
    return;
  }

  if (method == "hideOverlay") {
    HideOverlay();
    result->Success();
    return;
  }

  if (method == "updateOverlay") {
    std::string state = "recording";
    std::string duration = "00:00";
    std::string state_label;
    double level = 0.0;
    if (args != nullptr) {
      state = GetMapValue<std::string>(*args, "state").value_or(state);
      duration =
          GetMapValue<std::string>(*args, "duration").value_or(duration);
      state_label =
          GetMapValue<std::string>(*args, "stateLabel").value_or("");
      level = GetDoubleValue(*args, "level", 0.0);
    }
    UpdateOverlay(state, duration, level, state_label);
    result->Success();
    return;
  }

  if (method == "showMainWindow") {
    ShowMainWindowNative();
    result->Success();
    return;
  }

  if (method == "insertText") {
    if (args != nullptr) {
      const auto text = GetMapValue<std::string>(*args, "text").value_or("");
      InsertTextAtCursor(Utf8ToWide(text));
    }
    result->Success();
    return;
  }

  if (method == "checkAccessibility" || method == "requestAccessibility" ||
      method == "checkInputMonitoring" ||
      method == "requestInputMonitoring") {
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "openSoundInput") {
    ShellExecuteW(nullptr, L"open", L"ms-settings:sound", nullptr, nullptr,
                  SW_SHOWNORMAL);
    result->Success();
    return;
  }

  if (method == "openMicrophonePrivacy") {
    ShellExecuteW(nullptr, L"open", L"ms-settings:privacy-microphone", nullptr,
                  nullptr, SW_SHOWNORMAL);
    result->Success();
    return;
  }

  if (method == "openAccessibilityPrivacy" ||
      method == "openInputMonitoringPrivacy") {
    ShellExecuteW(nullptr, L"open", L"ms-settings:privacy", nullptr, nullptr,
                  SW_SHOWNORMAL);
    result->Success();
    return;
  }

  if (method == "registerHotkey") {
    int key_code = VK_F2;
    if (args != nullptr) {
      if (const auto key32 = GetMapValue<int32_t>(*args, "keyCode");
          key32.has_value()) {
        key_code = *key32;
      } else if (const auto key64 = GetMapValue<int64_t>(*args, "keyCode");
                 key64.has_value()) {
        key_code = static_cast<int>(*key64);
      }
    }
    const bool ok = RegisterGlobalHotkey(key_code);
    result->Success(flutter::EncodableValue(ok));
    return;
  }

  if (method == "unregisterHotkey") {
    UnregisterGlobalHotkey();
    result->Success();
    return;
  }

  if (method == "registerMeetingHotkey") {
    int key_code = VK_F3;
    int modifiers = 0;
    if (args != nullptr) {
      if (const auto key32 = GetMapValue<int32_t>(*args, "keyCode");
          key32.has_value()) {
        key_code = *key32;
      } else if (const auto key64 = GetMapValue<int64_t>(*args, "keyCode");
                 key64.has_value()) {
        key_code = static_cast<int>(*key64);
      }

      if (const auto modifiers32 = GetMapValue<int32_t>(*args, "modifiers");
          modifiers32.has_value()) {
        modifiers = *modifiers32;
      } else if (const auto modifiers64 =
                     GetMapValue<int64_t>(*args, "modifiers");
                 modifiers64.has_value()) {
        modifiers = static_cast<int>(*modifiers64);
      }
    }
    const bool ok = RegisterMeetingHotkey(key_code, modifiers);
    result->Success(flutter::EncodableValue(ok));
    return;
  }

  if (method == "unregisterMeetingHotkey") {
    UnregisterMeetingHotkey();
    result->Success();
    return;
  }

  if (method == "getLaunchAtLogin") {
    HKEY hKey;
    bool enabled = false;
    if (RegOpenKeyExW(HKEY_CURRENT_USER,
                      L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
                      0, KEY_READ, &hKey) == ERROR_SUCCESS) {
      enabled = RegQueryValueExW(hKey, L"Offhand", nullptr, nullptr,
                                 nullptr, nullptr) == ERROR_SUCCESS;
      RegCloseKey(hKey);
    }
    result->Success(flutter::EncodableValue(enabled));
    return;
  }

  if (method == "setLaunchAtLogin") {
    bool enabled = false;
    if (args != nullptr) {
      auto it = args->find(flutter::EncodableValue("enabled"));
      if (it != args->end()) {
        const auto* val = std::get_if<bool>(&it->second);
        if (val) enabled = *val;
      }
    }
    HKEY hKey;
    bool ok = false;
    if (RegOpenKeyExW(HKEY_CURRENT_USER,
                      L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
                      0, KEY_SET_VALUE, &hKey) == ERROR_SUCCESS) {
      if (enabled) {
        wchar_t exe_path[MAX_PATH];
        GetModuleFileNameW(nullptr, exe_path, MAX_PATH);
        std::wstring value = std::wstring(L"\"") + exe_path + L"\"";
        ok = RegSetValueExW(hKey, L"Offhand", 0, REG_SZ,
                            reinterpret_cast<const BYTE*>(value.c_str()),
                            static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t))) == ERROR_SUCCESS;
      } else {
        auto ret = RegDeleteValueW(hKey, L"Offhand");
        ok = (ret == ERROR_SUCCESS || ret == ERROR_FILE_NOT_FOUND);
      }
      RegCloseKey(hKey);
    }
    result->Success(flutter::EncodableValue(ok));
    return;
  }

  if (method == "setTrayLabels") {
    if (args != nullptr) {
      auto it_open = args->find(flutter::EncodableValue("open"));
      if (it_open != args->end()) {
        const auto* val = std::get_if<std::string>(&it_open->second);
        if (val) {
          int len = MultiByteToWideChar(CP_UTF8, 0, val->c_str(), -1, nullptr, 0);
          if (len > 0) {
            tray_label_open_.resize(len - 1);
            MultiByteToWideChar(CP_UTF8, 0, val->c_str(), -1, &tray_label_open_[0], len);
          }
        }
      }
      auto it_quit = args->find(flutter::EncodableValue("quit"));
      if (it_quit != args->end()) {
        const auto* val = std::get_if<std::string>(&it_quit->second);
        if (val) {
          int len = MultiByteToWideChar(CP_UTF8, 0, val->c_str(), -1, nullptr, 0);
          if (len > 0) {
            tray_label_quit_.resize(len - 1);
            MultiByteToWideChar(CP_UTF8, 0, val->c_str(), -1, &tray_label_quit_[0], len);
          }
        }
      }
    }
    result->Success();
    return;
  }

  result->NotImplemented();
}

bool FlutterWindow::RegisterGlobalHotkey(int key_code) {
  hotkey_key_code_ = key_code;
  hotkey_is_down_ = false;
  hotkey_enabled_ = true;
  EnsureKeyboardHook();
  return keyboard_hook_ != nullptr;
}

void FlutterWindow::UnregisterGlobalHotkey() {
  hotkey_enabled_ = false;
  hotkey_is_down_ = false;
  RemoveKeyboardHookIfUnused();
}

bool FlutterWindow::RegisterMeetingHotkey(int key_code, int modifiers) {
  meeting_hotkey_key_code_ = key_code;
  meeting_hotkey_modifiers_ = modifiers;
  meeting_hotkey_is_down_ = false;
  meeting_hotkey_enabled_ = true;
  EnsureKeyboardHook();
  return keyboard_hook_ != nullptr;
}

void FlutterWindow::UnregisterMeetingHotkey() {
  meeting_hotkey_enabled_ = false;
  meeting_hotkey_is_down_ = false;
  RemoveKeyboardHookIfUnused();
}

void FlutterWindow::EnsureKeyboardHook() {
  if (keyboard_hook_ != nullptr) return;
  keyboard_hook_ = SetWindowsHookExW(WH_KEYBOARD_LL, LowLevelKeyboardProc,
                                     GetModuleHandle(nullptr), 0);
}

void FlutterWindow::RemoveKeyboardHookIfUnused() {
  if (!hotkey_enabled_ && !meeting_hotkey_enabled_) {
    if (keyboard_hook_ != nullptr) {
      UnhookWindowsHookEx(keyboard_hook_);
      keyboard_hook_ = nullptr;
    }
  }
}

LRESULT CALLBACK FlutterWindow::LowLevelKeyboardProc(int n_code, WPARAM wparam,
                                                      LPARAM lparam) {
  if (n_code == HC_ACTION && instance_ != nullptr && lparam != 0) {
    const auto* keyboard = reinterpret_cast<KBDLLHOOKSTRUCT*>(lparam);
    const DWORD vk = keyboard->vkCode;
    const bool is_key_down = (wparam == WM_KEYDOWN || wparam == WM_SYSKEYDOWN);
    const bool is_key_up = (wparam == WM_KEYUP || wparam == WM_SYSKEYUP);

    if (is_key_down || is_key_up) {
      // Check voice input hotkey
      if (instance_->hotkey_enabled_ &&
          vk == static_cast<DWORD>(instance_->hotkey_key_code_)) {
        const bool is_repeat = is_key_down && instance_->hotkey_is_down_;
        instance_->hotkey_is_down_ = is_key_down;
        instance_->EmitGlobalKeyEvent(
            instance_->hotkey_key_code_, is_key_down ? "down" : "up",
            is_repeat, CurrentHotkeyModifiers());
      }

      // Check meeting hotkey
      if (instance_->meeting_hotkey_enabled_ &&
          vk == static_cast<DWORD>(instance_->meeting_hotkey_key_code_) &&
          MatchHotkeyModifiers(instance_->meeting_hotkey_modifiers_)) {
        const bool is_repeat = is_key_down && instance_->meeting_hotkey_is_down_;
        instance_->meeting_hotkey_is_down_ = is_key_down;
        instance_->EmitGlobalKeyEvent(
            instance_->meeting_hotkey_key_code_, is_key_down ? "down" : "up",
            is_repeat, CurrentHotkeyModifiers());
      }
    }
  }
  return CallNextHookEx(nullptr, n_code, wparam, lparam);
}

void FlutterWindow::EmitGlobalKeyEvent(int key_code, const std::string& type,
                                       bool is_repeat, int modifiers) {
  if (!method_channel_) {
    return;
  }

  const bool has_modifiers = modifiers != 0;

  flutter::EncodableMap payload;
  payload[flutter::EncodableValue("keyCode")] =
      flutter::EncodableValue(static_cast<int32_t>(key_code));
  payload[flutter::EncodableValue("type")] = flutter::EncodableValue(type);
  payload[flutter::EncodableValue("isRepeat")] =
      flutter::EncodableValue(is_repeat);
  payload[flutter::EncodableValue("hasModifiers")] =
      flutter::EncodableValue(has_modifiers);
  payload[flutter::EncodableValue("modifiers")] =
      flutter::EncodableValue(static_cast<int32_t>(modifiers));
  method_channel_->InvokeMethod("onGlobalKeyEvent",
                                std::make_unique<flutter::EncodableValue>(
                                    std::move(payload)));
}

void FlutterWindow::EnsureOverlayWindow() {
  if (overlay_window_ != nullptr) {
    return;
  }

  static bool class_registered = false;
  if (!class_registered) {
    WNDCLASSW wc{};
    wc.lpfnWndProc = FlutterWindow::OverlayWndProc;
    wc.hInstance = GetModuleHandle(nullptr);
    wc.lpszClassName = kOverlayWindowClassName;
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.hbrBackground = CreateSolidBrush(RGB(0, 0, 0));
    RegisterClassW(&wc);
    class_registered = true;
  }

  overlay_window_ = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
      kOverlayWindowClassName, L"OffhandOverlay", WS_POPUP, CW_USEDEFAULT,
      CW_USEDEFAULT, static_cast<int>(kOverlayWidth),
      static_cast<int>(kOverlayHeight), nullptr, nullptr, GetModuleHandle(nullptr),
      this);

  if (overlay_window_ == nullptr) {
    return;
  }

  const auto region =
      CreateRoundRectRgn(0, 0, kOverlayWidth, kOverlayHeight, kOverlayHeight,
                         kOverlayHeight);
  SetWindowRgn(overlay_window_, region, TRUE);
}

void FlutterWindow::ShowOverlay(const std::string& state,
                                const std::string& duration, double level,
                                const std::string& state_label) {
  EnsureOverlayWindow();
  if (overlay_window_ == nullptr) {
    return;
  }

  overlay_state_ = state;
  overlay_state_label_ = state_label;
  overlay_duration_ = duration;
  overlay_level_ = level;
  PositionOverlayWindow();
  ShowWindow(overlay_window_, SW_SHOWNOACTIVATE);
  InvalidateRect(overlay_window_, nullptr, TRUE);
}

void FlutterWindow::UpdateOverlay(const std::string& state,
                                  const std::string& duration, double level,
                                  const std::string& state_label) {
  if (overlay_window_ == nullptr) {
    return;
  }
  overlay_state_ = state;
  overlay_state_label_ = state_label;
  overlay_duration_ = duration;
  overlay_level_ = level;
  InvalidateRect(overlay_window_, nullptr, TRUE);
}

void FlutterWindow::HideOverlay() {
  if (overlay_window_ == nullptr) {
    return;
  }
  ShowWindow(overlay_window_, SW_HIDE);
}

void FlutterWindow::PositionOverlayWindow() {
  if (overlay_window_ == nullptr) {
    return;
  }

  const HMONITOR monitor = MonitorFromWindow(GetDesktopWindow(),
                                              MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  GetMonitorInfoW(monitor, &info);

  const int width = static_cast<int>(kOverlayWidth);
  const int height = static_cast<int>(kOverlayHeight);
  const int x = (info.rcWork.left + info.rcWork.right - width) / 2;
  const int y = info.rcWork.bottom - height - 24;

  SetWindowPos(overlay_window_, HWND_TOPMOST, x, y, width, height,
               SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

void FlutterWindow::PaintOverlay(HDC hdc) {
  RECT rect{};
  GetClientRect(overlay_window_, &rect);

  const auto background = CreateSolidBrush(RGB(24, 24, 30));
  const auto border = CreatePen(PS_SOLID, 1, RGB(50, 50, 58));
  const auto old_pen = SelectObject(hdc, border);
  const auto old_brush = SelectObject(hdc, background);
  RoundRect(hdc, rect.left, rect.top, rect.right, rect.bottom,
            static_cast<int>(kOverlayHeight), static_cast<int>(kOverlayHeight));
  SelectObject(hdc, old_pen);
  SelectObject(hdc, old_brush);
  DeleteObject(border);
  DeleteObject(background);

  COLORREF dot_color = RGB(231, 76, 60);
  if (overlay_state_ == "starting") {
    dot_color = RGB(241, 196, 15);
  } else if (overlay_state_ == "transcribing") {
    dot_color = RGB(107, 99, 255);
  } else if (overlay_state_ == "enhancing") {
    dot_color = RGB(79, 199, 158);
  }

  const auto dot_brush = CreateSolidBrush(dot_color);
  const auto old_dot_brush = SelectObject(hdc, dot_brush);
  const auto dot_pen = CreatePen(PS_SOLID, 1, dot_color);
  const auto old_dot_pen = SelectObject(hdc, dot_pen);
  Ellipse(hdc, 20, 22, 30, 32);
  SelectObject(hdc, old_dot_brush);
  SelectObject(hdc, old_dot_pen);
  DeleteObject(dot_pen);
  DeleteObject(dot_brush);

  SetBkMode(hdc, TRANSPARENT);
  SetTextColor(hdc, RGB(235, 235, 235));
  HFONT font = CreateFontW(18, 0, 0, 0, FW_MEDIUM, FALSE, FALSE, FALSE,
                           DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                           CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                           DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
  const auto old_font = SelectObject(hdc, font);

  std::string state_text = overlay_state_label_.empty()
                               ? OverlayStatusText(overlay_state_)
                               : overlay_state_label_;
  std::wstring status = Utf8ToWide(state_text);
  if (overlay_state_ == "recording") {
    status += L"  ";
    status += Utf8ToWide(overlay_duration_);
  }

  RECT text_rect{40, 0, rect.right - 12, rect.bottom};
  DrawTextW(hdc, status.c_str(), -1, &text_rect,
            DT_SINGLELINE | DT_VCENTER | DT_LEFT | DT_END_ELLIPSIS);

  if (overlay_state_ == "recording") {
    const int base_x = 156;
    const int base_y = 28;
    const int bar_width = 4;
    const int gap = 3;
    const int bar_count = 6;
    const double clamped = std::max(0.0, std::min(1.0, overlay_level_));
    const auto bar_brush = CreateSolidBrush(RGB(220, 220, 220));
    const auto old_bar_brush = SelectObject(hdc, bar_brush);
    for (int i = 0; i < bar_count; ++i) {
      const double phase = static_cast<double>(i) /
                           static_cast<double>(std::max(1, bar_count - 1));
      const double shaped = clamped * (0.6 + 0.4 * (1.0 - std::abs(phase - 0.5) * 2.0));
      const int h = static_cast<int>(4 + shaped * 14);
      RECT bar{base_x + i * (bar_width + gap), base_y - h,
               base_x + i * (bar_width + gap) + bar_width, base_y};
      FillRect(hdc, &bar, bar_brush);
    }
    SelectObject(hdc, old_bar_brush);
    DeleteObject(bar_brush);
  }

  SelectObject(hdc, old_font);
  DeleteObject(font);
}

LRESULT CALLBACK FlutterWindow::OverlayWndProc(HWND hwnd, UINT message,
                                                WPARAM wparam,
                                                LPARAM lparam) noexcept {
  FlutterWindow* owner = reinterpret_cast<FlutterWindow*>(
      GetWindowLongPtr(hwnd, GWLP_USERDATA));

  if (message == WM_NCCREATE) {
    const auto* cs = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(hwnd, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(cs->lpCreateParams));
    return DefWindowProc(hwnd, message, wparam, lparam);
  }

  if (owner == nullptr) {
    return DefWindowProc(hwnd, message, wparam, lparam);
  }

  switch (message) {
    case WM_PAINT: {
      PAINTSTRUCT ps{};
      HDC hdc = BeginPaint(hwnd, &ps);
      owner->PaintOverlay(hdc);
      EndPaint(hwnd, &ps);
      return 0;
    }
    case WM_ERASEBKGND:
      return 1;
    default:
      break;
  }

  return DefWindowProc(hwnd, message, wparam, lparam);
}

void FlutterWindow::ShowMainWindowNative() {
  const HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  ShowWindow(hwnd, SW_RESTORE);
  SetForegroundWindow(hwnd);
  SetFocus(hwnd);
}

void FlutterWindow::InsertTextAtCursor(const std::wstring& text) {
  if (text.empty()) {
    return;
  }

  if (OpenClipboard(nullptr)) {
    EmptyClipboard();
    const size_t bytes = (text.size() + 1) * sizeof(wchar_t);
    HGLOBAL handle = GlobalAlloc(GMEM_MOVEABLE, bytes);
    if (handle != nullptr) {
      void* ptr = GlobalLock(handle);
      if (ptr != nullptr) {
        memcpy(ptr, text.c_str(), bytes);
        GlobalUnlock(handle);
        SetClipboardData(CF_UNICODETEXT, handle);
      } else {
        GlobalFree(handle);
      }
    }
    CloseClipboard();
  }

  INPUT inputs[4] = {};
  inputs[0].type = INPUT_KEYBOARD;
  inputs[0].ki.wVk = VK_CONTROL;

  inputs[1].type = INPUT_KEYBOARD;
  inputs[1].ki.wVk = 'V';

  inputs[2].type = INPUT_KEYBOARD;
  inputs[2].ki.wVk = 'V';
  inputs[2].ki.dwFlags = KEYEVENTF_KEYUP;

  inputs[3].type = INPUT_KEYBOARD;
  inputs[3].ki.wVk = VK_CONTROL;
  inputs[3].ki.dwFlags = KEYEVENTF_KEYUP;

  SendInput(4, inputs, sizeof(INPUT));
}

void FlutterWindow::InitializeTrayIcon() {
  if (tray_icon_initialized_) {
    return;
  }

  const HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }

  NOTIFYICONDATAW nid{};
  nid.cbSize = sizeof(nid);
  nid.hWnd = hwnd;
  nid.uID = kTrayIconId;
  nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  nid.uCallbackMessage = kTrayCallbackMessage;
  nid.hIcon = static_cast<HICON>(LoadImageW(
      GetModuleHandle(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
      16, 16, LR_DEFAULTCOLOR));
  wcscpy_s(nid.szTip, L"Offhand");

  tray_icon_initialized_ = Shell_NotifyIconW(NIM_ADD, &nid) == TRUE;
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_icon_initialized_) {
    return;
  }

  const HWND hwnd = GetHandle();
  if (hwnd != nullptr) {
    NOTIFYICONDATAW nid{};
    nid.cbSize = sizeof(nid);
    nid.hWnd = hwnd;
    nid.uID = kTrayIconId;
    Shell_NotifyIconW(NIM_DELETE, &nid);
  }

  tray_icon_initialized_ = false;
}

void FlutterWindow::ShowTrayMenu() {
  const HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }

  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }

  AppendMenuW(menu, MF_STRING, kTrayMenuOpenId, tray_label_open_.c_str());
  AppendMenuW(menu, MF_STRING, kTrayMenuExitId, tray_label_quit_.c_str());

  POINT cursor{};
  GetCursorPos(&cursor);
  SetForegroundWindow(hwnd);
  TrackPopupMenu(menu, TPM_BOTTOMALIGN | TPM_LEFTALIGN, cursor.x, cursor.y, 0,
                 hwnd, nullptr);
  DestroyMenu(menu);
}

void FlutterWindow::ExitFromTray() {
  exiting_from_tray_ = true;
  RemoveTrayIcon();
  Destroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_CLOSE:
      if (!exiting_from_tray_) {
        ShowWindow(hwnd, SW_HIDE);
        return 0;
      }
      break;
    case WM_COMMAND: {
      const UINT command = LOWORD(wparam);
      if (command == kTrayMenuOpenId) {
        ShowMainWindowNative();
        return 0;
      }
      if (command == kTrayMenuExitId) {
        ExitFromTray();
        return 0;
      }
      break;
    }
    case kTrayCallbackMessage:
      if (LOWORD(lparam) == WM_LBUTTONDBLCLK) {
        ShowMainWindowNative();
        return 0;
      }
      if (LOWORD(lparam) == WM_RBUTTONUP || LOWORD(lparam) == WM_CONTEXTMENU) {
        ShowTrayMenu();
        return 0;
      }
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_DISPLAYCHANGE:
    case WM_SETTINGCHANGE:
      if (overlay_window_ != nullptr && IsWindowVisible(overlay_window_)) {
        PositionOverlayWindow();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
