#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
    static constexpr UINT kOverlayWidth = 360;
    static constexpr UINT kOverlayHeight = 56;
     static constexpr UINT kTrayCallbackMessage = WM_APP + 101;
     static constexpr UINT kTrayIconId = 1;
     static constexpr UINT kTrayMenuOpenId = 40001;
     static constexpr UINT kTrayMenuExitId = 40002;

    static FlutterWindow* instance_;

    bool SetupMethodChannel();
    void HandleMethodCall(
        const flutter::MethodCall<flutter::EncodableValue>& call,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    bool RegisterGlobalHotkey(int key_code);
    void UnregisterGlobalHotkey();
    bool RegisterMeetingHotkey(int key_code, int modifiers);
    void UnregisterMeetingHotkey();
    void EnsureKeyboardHook();
    void RemoveKeyboardHookIfUnused();
    static LRESULT CALLBACK LowLevelKeyboardProc(int n_code, WPARAM wparam,
                                                 LPARAM lparam);
    void EmitGlobalKeyEvent(int key_code, const std::string& type,
                            bool is_repeat);

    void EnsureOverlayWindow();
    void ShowOverlay(const std::string& state, const std::string& duration,
                                         double level, const std::string& state_label);
    void UpdateOverlay(const std::string& state, const std::string& duration,
                                             double level, const std::string& state_label);
    void HideOverlay();
    void PositionOverlayWindow();
    void PaintOverlay(HDC hdc);
    static LRESULT CALLBACK OverlayWndProc(HWND hwnd, UINT message,
                                           WPARAM wparam,
                                           LPARAM lparam) noexcept;

    void ShowMainWindowNative();
    void InsertTextAtCursor(const std::wstring& text);
    void InitializeTrayIcon();
    void RemoveTrayIcon();
    void ShowTrayMenu();
    void ExitFromTray();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
        method_channel_;

    HHOOK keyboard_hook_ = nullptr;
    int hotkey_key_code_ = VK_F2;
    bool hotkey_enabled_ = false;
    bool hotkey_is_down_ = false;

    int meeting_hotkey_key_code_ = VK_F3;
    int meeting_hotkey_modifiers_ = 0;
    bool meeting_hotkey_enabled_ = false;
    bool meeting_hotkey_is_down_ = false;

    bool tray_icon_initialized_ = false;
    bool exiting_from_tray_ = false;
    std::wstring tray_label_open_ = L"\x6253\x5F00";   // 打开
    std::wstring tray_label_quit_ = L"\x9000\x51FA";   // 退出

    HWND overlay_window_ = nullptr;
    std::string overlay_state_ = "idle";
    std::string overlay_state_label_;
    std::string overlay_duration_ = "00:00";
    double overlay_level_ = 0.0;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
