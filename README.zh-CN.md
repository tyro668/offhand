# 释手

[中文](README.zh-CN.md) | [English](README.md)

言之所至，释手而书。

释手是一款注重隐私保护的语音转文字输入应用，支持基于 sherpa-onnx 的高性能本地 ASR 模型，让敏感语音数据尽可能留在本机处理。

释手是一款语音转文字输入应用，配置语音模型后可将语音快速转化为文字，并在转换完成后自动插入当前应用的光标位置，实现自然流畅的输入体验。

## 启动调试

### mac电脑
```
flutter run  -d macos
```

### windows电脑
```
flutter run  -d windows
```

说明：开发环境默认使用精简模式（不启用本地文本模型，不依赖 llamadart），避免首次调试时下载本地原生库失败。GitHub Actions 打包发布版本会自动启用完整本地模型支持。

## 构建安装文件

如果要在自己电脑上构建，使用以下的方式，如果要直接下载使用，在这里[下载安装文件](https://github.com/tyro668/voicetype/releases)。

**注意：** mac上使用该应用需要自己去隐私与安全性中允许该应用，如图所示：![mac](screenshots/mac_start.png)

### mac版本
```
flutter build macos --release
```

### windows版本
```
flutter build windows --release
```

## 一键构建脚本

macOS (DMG):

```
./scripts/build-macos.sh
```

Windows (EXE):

```
powershell -ExecutionPolicy Bypass -File scripts/build-windows.ps1
```
## 配置语音模型

推荐使用GLM的语音模型，直接访问[智普的官网](https://bigmodel.cn/usercenter)充值10块钱，然后新建好API Key后，在应用中进行配置即可。

|属性名|属性值|
|-----|-----|
|端点URL|https://open.bigmodel.cn/api/paas/v4|
|模型名称|GLM-ASR-2512|

也可以使用 Aliyun DashScope 的语音模型 (兼容 OpenAI 接口模式)

|属性名|属性值|
|-----|-----|
|端点URL|https://dashscope.aliyuncs.com/compatible-mode/v1|
|模型名称|qwen3-asr-flash|

也支持 OpenAI 官方语音转写模型

|属性名|属性值|
|-----|-----|
|端点URL|https://api.openai.com/v1|
|模型名称|gpt-4o-transcribe / gpt-4o-mini-transcribe / whisper-1|

也支持 Google Gemini 的 OpenAI 兼容接口（内置了音频回退调用）

|属性名|属性值|
|-----|-----|
|端点URL|https://generativelanguage.googleapis.com/v1beta/openai|
|模型名称|gemini-3-pro / gemini-3-flash / gemini-3-flash-lite|

## 配置文本模型（可选）

可以使用任意兼容OpenAI接口的服务

|属性名|属性值|
|-----|-----|
|端点URL|https://open.bigmodel.cn/api/paas/v4|
|模型名称|GLM-4.7|

OpenAI（文本增强）常用配置

|属性名|属性值|
|-----|-----|
|端点URL|https://api.openai.com/v1|
|模型名称|gpt-5 / gpt-5-mini / gpt-5-nano / gpt-4.1|

Google Gemini（文本增强）常用配置

|属性名|属性值|
|-----|-----|
|端点URL|https://generativelanguage.googleapis.com/v1beta/openai|
|模型名称|gemini-3-pro / gemini-3-flash / gemini-3-flash-lite|

## 用户界面

### 通用设置
![通用设置](screenshots/main.png)

### 语音模型设置

用于设置将语音转为为文本的模型，分为在线模型（优秀的语音识别效果，可以支持各种方言）和本地模型（仅供测试使用）

#### 在线语音识别模型（效果好）
![语音模型设置](screenshots/voice_setting.png)

#### 本地语音识别模型（测试用）
![本地语音模型设置](screenshots/local_voice_model.png)

### 文本模型设置

用于设置将口语化的句子修改为通顺的语句，分为在线模型（优秀的文本优化效果）和本地模型（仅供测试使用，效果较差）

#### 在线文本增强模型（效果好）
![文本模型设置](screenshots/text_setting.png)

#### 本地文本增强模型（测试用）
![本地文本模型设置](screenshots/local_text_model.png)


录音效果
![录音效果](screenshots/record.png)

## 许可证

本项目采用 Apache License 2.0 协议发布，详见 [LICENSE](LICENSE)。
