# Offhand

[中文](README.zh-CN.md) | [English](README.md)

Speak freely, write unbound.

Offhand is a privacy-first voice-to-text input app, with support for high-performance local models so sensitive audio can stay on your device.

Offhand is a voice-to-text input application. After you configure a speech recognition model, it can convert your voice into text and automatically insert the result at the current cursor position of the active application.

## Run in debug mode

### macOS
```
flutter run -d macos
```

### Windows
```
flutter run -d windows
```

## Build installers

If you want to build on your own machine, use the commands below. If you just want to download and use it directly, check [Releases](https://github.com/tyro668/voicetype/releases).

**Note:** On macOS, you need to allow this app in Privacy & Security before launching it. Example:
![mac](screenshots/mac_start.png)

### macOS build
```
flutter build macos --release
```

### Windows build
```
flutter build windows --release
```

## One-click build scripts

macOS (DMG):

```
./scripts/build-macos.sh
```

Windows (EXE):

```
powershell -ExecutionPolicy Bypass -File scripts/build-windows.ps1
```

## Configure speech model

Using GLM speech model is recommended. Visit [Zhipu](https://bigmodel.cn/usercenter), top up your account, create an API key, and configure it in the app.

| Property | Value |
|-----|-----|
| Endpoint URL | https://open.bigmodel.cn/api/paas/v4 |
| Model Name | GLM-ASR-2512 |

You can also use Alibaba Cloud DashScope speech model (OpenAI-compatible API mode).

| Property | Value |
|-----|-----|
| Endpoint URL | https://dashscope.aliyuncs.com/compatible-mode/v1 |
| Model Name | qwen3-asr-flash |

OpenAI official speech transcription is also supported.

| Property | Value |
|-----|-----|
| Endpoint URL | https://api.openai.com/v1 |
| Model Name | gpt-4o-transcribe / gpt-4o-mini-transcribe / whisper-1 |

Google Gemini OpenAI-compatible endpoint is also supported (with built-in audio fallback).

| Property | Value |
|-----|-----|
| Endpoint URL | https://generativelanguage.googleapis.com/v1beta/openai |
| Model Name | gemini-3-pro / gemini-3-flash / gemini-3-flash-lite |

## Configure text model (optional)

Any OpenAI-compatible service can be used.

| Property | Value |
|-----|-----|
| Endpoint URL | https://open.bigmodel.cn/api/paas/v4 |
| Model Name | GLM-4.7 |

OpenAI common setup for text enhancement.

| Property | Value |
|-----|-----|
| Endpoint URL | https://api.openai.com/v1 |
| Model Name | gpt-5 / gpt-5-mini / gpt-5-nano / gpt-4.1 |

Google Gemini common setup for text enhancement.

| Property | Value |
|-----|-----|
| Endpoint URL | https://generativelanguage.googleapis.com/v1beta/openai |
| Model Name | gemini-3-pro / gemini-3-flash / gemini-3-flash-lite |

## UI

### General settings
![General settings](screenshots/main.png)

### Speech model settings

Used to configure speech-to-text models. There are online models (better recognition quality, supports dialects) and local models (for testing only).

#### Online speech recognition model (recommended)
![Speech model settings](screenshots/voice_setting.png)

#### Local speech recognition model (testing)
![Local speech model settings](screenshots/local_voice_model.png)

### Text model settings

Used to refine colloquial sentences into smoother text. There are online models (better text optimization) and local models (for testing only, lower quality).

#### Online text enhancement model (recommended)
![Text model settings](screenshots/text_setting.png)

#### Local text enhancement model (testing)
![Local text model settings](screenshots/local_text_model.png)

Recording effect
![Recording effect](screenshots/record.png)

## License

This project is licensed under the Apache License 2.0. See [LICENSE](LICENSE).
