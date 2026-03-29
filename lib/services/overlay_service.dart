import 'dart:io';

import 'package:flutter/services.dart';
import 'log_service.dart';

/// 与原生 overlay 窗口通信的服务（支持 macOS 和 Windows）
class OverlayService {
  static const _channel = MethodChannel('com.voicetype/overlay');
  static bool get _isMacOS => Platform.isMacOS;
  static bool get _isWindows => Platform.isWindows;
  static bool get _supportsNativeOverlay => _isMacOS || _isWindows;
  static String? _activeOwner;

  /// 全局快捷键回调
  static Function(
    int keyCode,
    String type,
    bool isRepeat,
    bool hasModifiers,
    int modifiers,
  )?
  onGlobalKeyEvent;

  static void init() {
    LogService.info('OVERLAY', 'init: setting method call handler');
    _channel.setMethodCallHandler((call) async {
      LogService.info('OVERLAY', 'received native call: ${call.method}');
      if (call.method == 'onGlobalKeyEvent') {
        final args = call.arguments as Map;
        final keyCode = args['keyCode'] as int;
        final type = args['type'] as String;
        final isRepeat = args['isRepeat'] as bool;
        final hasModifiers = args['hasModifiers'] as bool? ?? false;
        final modifiers = args['modifiers'] as int? ?? 0;
        final hasCallback = onGlobalKeyEvent != null;
        LogService.info(
          'OVERLAY',
          'onGlobalKeyEvent keyCode=$keyCode type=$type hasModifiers=$hasModifiers modifiers=$modifiers hasCallback=$hasCallback',
        );
        try {
          onGlobalKeyEvent?.call(
            keyCode,
            type,
            isRepeat,
            hasModifiers,
            modifiers,
          );
        } catch (e) {
          LogService.error('OVERLAY', 'onGlobalKeyEvent callback error: $e');
        }
      }
    });
  }

  static Future<void> showOverlay({
    required String state,
    String duration = '00:00',
    double? level,
    String? stateLabel,
    String? owner,
  }) async {
    if (!_supportsNativeOverlay) return;
    if (owner != null) {
      if (_activeOwner != owner) {
        LogService.info(
          'OVERLAY',
          'owner switched: ${_activeOwner ?? 'none'} -> $owner',
        );
      }
      _activeOwner = owner;
    }
    final args = <String, Object>{'state': state, 'duration': duration};
    if (level != null) {
      args['level'] = level;
    }
    if (stateLabel != null) {
      args['stateLabel'] = stateLabel;
    }
    await _channel.invokeMethod('showOverlay', args);
  }

  static Future<void> hideOverlay({String? owner}) async {
    if (!_supportsNativeOverlay) return;
    if (owner != null && _activeOwner != owner) {
      return;
    }
    _activeOwner = null;
    await _channel.invokeMethod('hideOverlay');
  }

  static Future<void> updateOverlay({
    required String state,
    String duration = '00:00',
    double? level,
    String? stateLabel,
    String? owner,
  }) async {
    if (!_supportsNativeOverlay) return;
    if (owner != null && _activeOwner != owner) {
      return;
    }
    final args = <String, Object>{'state': state, 'duration': duration};
    if (level != null) {
      args['level'] = level;
    }
    if (stateLabel != null) {
      args['stateLabel'] = stateLabel;
    }
    await _channel.invokeMethod('updateOverlay', args);
  }

  static Future<void> showMainWindow() async {
    if (!_supportsNativeOverlay) return;
    await _channel.invokeMethod('showMainWindow');
  }

  static Future<void> insertText(String text) async {
    if (!_supportsNativeOverlay) return;
    await _channel.invokeMethod('insertText', {'text': text});
  }

  /// Update the overlay with real-time streaming text.
  static Future<void> updateOverlayText(String text, {String? owner}) async {
    if (!_supportsNativeOverlay) return;
    if (owner != null && _activeOwner != owner) {
      return;
    }
    try {
      await _channel.invokeMethod('updateOverlayText', {'text': text});
    } catch (_) {
      // Fallback: native side may not support this yet
    }
  }

  /// 检查辅助功能权限
  static Future<bool> checkAccessibility() async {
    if (_isWindows) return true;
    if (!_isMacOS) return false;
    final result = await _channel.invokeMethod<bool>('checkAccessibility');
    return result ?? false;
  }

  /// 请求辅助功能权限（弹出系统提示）
  static Future<bool> requestAccessibility() async {
    if (_isWindows) return true;
    if (!_isMacOS) return false;
    final result = await _channel.invokeMethod<bool>('requestAccessibility');
    return result ?? false;
  }

  /// 打开系统声音输入设置
  static Future<void> openSoundInput() async {
    if (!_supportsNativeOverlay) return;
    await _channel.invokeMethod('openSoundInput');
  }

  /// 打开麦克风隐私设置
  static Future<void> openMicrophonePrivacy() async {
    if (!_supportsNativeOverlay) return;
    await _channel.invokeMethod('openMicrophonePrivacy');
  }

  /// 打开辅助功能隐私设置
  static Future<void> openAccessibilityPrivacy() async {
    if (!_supportsNativeOverlay) return;
    await _channel.invokeMethod('openAccessibilityPrivacy');
  }

  /// 打开输入监控隐私设置
  static Future<void> openInputMonitoringPrivacy() async {
    if (!_supportsNativeOverlay) return;
    await _channel.invokeMethod('openInputMonitoringPrivacy');
  }

  /// 检查输入监控权限（macOS 10.15+）
  static Future<bool> checkInputMonitoring() async {
    if (_isWindows) return true;
    if (!_isMacOS) return false;
    final result = await _channel.invokeMethod<bool>('checkInputMonitoring');
    return result ?? false;
  }

  /// 请求输入监控权限（弹出系统提示）
  static Future<bool> requestInputMonitoring() async {
    if (_isWindows) return true;
    if (!_isMacOS) return false;
    final result = await _channel.invokeMethod<bool>('requestInputMonitoring');
    return result ?? false;
  }

  static Future<bool> registerHotkey({
    required int keyCode,
    int modifiers = 0,
  }) async {
    if (!_supportsNativeOverlay) return false;
    try {
      final result = await _channel.invokeMethod<bool>('registerHotkey', {
        'keyCode': keyCode,
        'modifiers': modifiers,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> registerMeetingHotkey({
    required int keyCode,
    int modifiers = 0,
  }) async {
    if (!_supportsNativeOverlay) return false;
    try {
      final result = await _channel.invokeMethod<bool>(
        'registerMeetingHotkey',
        {'keyCode': keyCode, 'modifiers': modifiers},
      );
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 取消会议快捷键注册
  static Future<void> unregisterMeetingHotkey() async {
    if (!_supportsNativeOverlay) return;
    await _channel.invokeMethod('unregisterMeetingHotkey');
  }

  /// 获取开机启动状态
  static Future<bool> getLaunchAtLogin() async {
    if (!_supportsNativeOverlay) return false;
    try {
      final result = await _channel.invokeMethod<bool>('getLaunchAtLogin');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 设置开机启动
  static Future<bool> setLaunchAtLogin(bool enabled) async {
    if (!_supportsNativeOverlay) return false;
    try {
      final result = await _channel.invokeMethod<bool>('setLaunchAtLogin', {
        'enabled': enabled,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 取消全局快捷键注册
  static Future<void> unregisterHotkey() async {
    if (!_supportsNativeOverlay) return;
    await _channel.invokeMethod('unregisterHotkey');
  }

  /// 获取是否在 Dock 上显示图标（仅 macOS）
  static Future<bool> getShowInDock() async {
    if (!_isMacOS) return true;
    try {
      final result = await _channel.invokeMethod<bool>('getShowInDock');
      return result ?? true;
    } catch (e) {
      return true;
    }
  }

  /// 设置是否在 Dock 上显示图标（仅 macOS）
  static Future<bool> setShowInDock(bool show) async {
    if (!_isMacOS) return false;
    try {
      final result = await _channel.invokeMethod<bool>('setShowInDock', {
        'show': show,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 设置系统托盘菜单的本地化文本
  static Future<void> setTrayLabels({
    required String open,
    required String quit,
  }) async {
    if (!_supportsNativeOverlay) return;
    try {
      await _channel.invokeMethod('setTrayLabels', {
        'open': open,
        'quit': quit,
      });
    } catch (e) {
      // ignore — older native code may not support this method yet
    }
  }
}
