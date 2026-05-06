<div align="center">

# OmniVoice

<p>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white">
  <img alt="Swift 5.9" src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white">
  <img alt="Swift Package Manager" src="https://img.shields.io/badge/SwiftPM-package-F05138?logo=swift&logoColor=white">
  <img alt="AppKit" src="https://img.shields.io/badge/UI-AppKit-147EFB?logo=apple&logoColor=white">
  <img alt="MiMo speech models" src="https://img.shields.io/badge/STT-mimo--v2--omni%20%7C%20mimo--v2.5-7C3AED">
  <img alt="OpenAI-compatible API" src="https://img.shields.io/badge/API-OpenAI--compatible-10A37F?logo=openai&logoColor=white">
</p>

中文 | [English](#english)

</div>

## 中文

OmniVoice 是一个 macOS 14+ 菜单栏语音听写工具。它不是系统输入法，不注册 input source，也不接管当前键盘或输入源。按住已配置的触发键开始录音，松开后通过 MiMo OpenAI-compatible API 转写，然后让 OmniVoice 把最终文本插入当前输入框；如果无法安全插入，则显示置顶 ActionPanel，供你复制、切换风格、重试或取消。

### 演示

结果 ActionPanel 会从聆听/转写 HUD 位置展开，底部保留风格切换控件，并同时支持深色和浅色胶囊配色。当开启自动插入且当前输入框安全可写时，识别出的文本可以自动插入；当插入被关闭、目标不安全、不可用，或测试时强制进入面板时，才会显示 ActionPanel 供确认。中文演示使用中文 UI 和中文输入，转写阶段保留更长的流式预览时间。

| 深色胶囊 | 浅色胶囊 |
| --- | --- |
| <img src="assets/readme/action-panel-dark.gif" alt="OmniVoice 深色胶囊 ActionPanel 流程" width="420"> | <img src="assets/readme/action-panel-light.gif" alt="OmniVoice 浅色胶囊 ActionPanel 流程" width="420"> |

### 使用教程

1. 从 `/Applications/OmniVoice.app` 启动 OmniVoice。如果你从源码运行，请先按开发教程执行一次 `make run`。
2. 打开菜单栏图标，查看权限摘要。
3. 如果麦克风、辅助功能或输入监控缺失，点击 `请求所有权限`。
4. 打开 `配置` -> `打开 config 文件`，填写 MiMo API 来源和 API Key。
5. 点击 `重新加载配置`，再点击 `检查连接与测速`。
6. 把光标放进任意可编辑输入框。
7. 按住触发键，说完后松开。

如果开启了自动插入，且目标输入框安全可写，OmniVoice 会直接插入最终文本。如果目标不安全或不可用，OmniVoice 会打开 ActionPanel，你可以复制文本、切换风格并基于缓存音频重新转写，或取消。

### 日常控制

- 默认触发键：Fn/Globe。
- 可选触发键：Fn/Globe、F1-F12、左右 Shift、Control、Option、Command，以及 Caps Lock。
- Escape 会取消录音/转写，并关闭 ActionPanel。
- 如果系统输入在权限或重装异常后卡住，按 `Fn/Globe + Esc` 会停止监听、保存为停止状态并退出 OmniVoice。
- `自动插入` 控制是否把安全的最终文本自动写入当前输入框。
- `风格` 顺序为原文、精炼、技术、重写，然后显示来自 `config.jsonc` 的自定义风格；默认是精炼。
- `技术` 适合命令、路径、标识符、大小写、符号和中英混杂技术口述。
- `重写` 可以润色语气和结构，但不得新增事实、承诺、收件人、署名或用户没有表达的内容。
- 结果面板显示复制、主题化风格切换和取消。选择另一个风格只影响当前面板，不会修改全局默认风格。

### 配置

OmniVoice 只从 `~/.config/omnivoice/config.jsonc` 读取连接配置。这个文件使用 JSONC，支持注释和尾随逗号。环境变量和 Keychain 都不是 App 配置来源。

请通过 `配置` 子菜单里的 `打开 config 文件` 编辑连接设置。如果文件不存在，OmniVoice 会先创建当前界面语言的 JSONC 模板，然后优先用 VS Code、Cursor、Windsurf、Zed、Sublime Text、BBEdit、TextMate 或 Xcode 等代码编辑器打开；如果都找不到，则回退到系统默认应用。API Key 只在 `config.jsonc` 中编辑，菜单中始终脱敏展示。

示例配置：

```jsonc
{
  "active_source": "auto",
  "default_model": "mimo-v2-omni",
  "sources": {
    "sgp": {
      "base_url": "https://token-plan-sgp.xiaomimimo.com",
      "api_key": ""
    },
    "cn": {
      "base_url": "https://token-plan-cn.xiaomimimo.com",
      "api_key": ""
    }
  },
  "latency": {
    "enabled": true,
    "interval_seconds": 1800
  },
  "custom_styles": {
    "meeting_notes": {
      "display_name": "Meeting Notes",
      "display_name_zh": "会议纪要",
      "description": "Turn speech into concise meeting notes.",
      "description_zh": "把口述整理成简洁会议纪要。",
      "prompt_lines": [
        "请把这段音频整理成简洁会议纪要。",
        "保留明确说出的决定、待办、时间、人名、项目名和技术词。",
        "如果有多个要点，使用简短的换行列表。",
        "不要新增用户没有说出的事实、结论、负责人或截止日期。"
      ]
    }
  }
}
```

如果从源码 checkout 创建本地模板，可以运行：

```sh
make config-template
```

如果 `config.jsonc` 包含 API Key，请自行保护权限：

```sh
chmod 600 ~/.config/omnivoice/config.jsonc
```

`active_source: "auto"` 会选择 `/v1/models` 可访问、包含受支持语音模型且测速最快的来源。`auto` 是保留值，不能作为普通 source id。

可以用 `custom_styles` 添加自己的转写 prompt。每个风格需要一个安全 ID、显示名称，以及 `prompt` 或 `prompt_lines`。自定义风格会在风格菜单和结果面板风格切换中标记为 `自定义`。

### 权限

OmniVoice 启动时和每次打开菜单时都会检查权限：

- 麦克风：使用 `AVAudioEngine` 录音。
- 辅助功能：检查当前输入框是否可以接收文本，并在安全时写入。
- 输入监控：感知触发键的按下和松开。

如果 OmniVoice 已在辅助功能或输入监控列表中，但 App 仍显示缺权限，请移除残留项，点击 `+`，重新选择 `/Applications/OmniVoice.app`。macOS 隐私权限和 App 路径相关，因此使用已安装 App 路径很重要。

如果你从源码反复运行 `make run`，安装流程会先退出旧的 `/Applications/OmniVoice.app` 实例，再替换并打开新 bundle，避免旧进程继续持有输入监听权限。

### 菜单布局

所有设置都在菜单栏内完成。没有 Dock 图标、Settings 窗口、popover、sheet，也不注册输入源。

菜单按控制、配置、转写、体验/系统和最后 App 操作分段组织，包含 `停止` 或 `重新启用`、状态、权限、脱敏 Base URL/API Key/当前模型/来源、`配置`、`语言`、`风格`、`触发键`、`录音时长`、`开机自启`、`自动插入`、`HUD 样式`、`提示显示时长`、`权限管理`、`重启 OmniVoice` 和 `退出 OmniVoice`。

模型选择、重新加载配置、刷新模型、API 来源、测速设置、打开配置文件，以及合并后的检查连接与测速都位于配置子菜单内。`语言` 菜单控制 UI 语言；转写输出默认简体中文，如果音频主要是英文则输出英文。

语音模型候选仅限 `mimo-v2-omni` 和 `mimo-v2.5`；TTS 和 Pro 模型会被过滤。

### 运行说明

- `录音时长` 菜单会显示当前最短到最长区间，例如 `录音时长：500ms-60s`。最短可选 300ms、500ms、800ms、1s、2s、3s；最长可选 15s、30s、60s、120s、300s。
- 上传 WAV 格式为 16 kHz mono little-endian Int16 PCM WAV。
- 自动插入会对标准原生文本框优先使用保守辅助功能写入，再回退到保存剪贴板 + Cmd+V。
- Secure text field、密码、验证码、token/API-key-like 输入框、无焦点、缺权限、粘贴失败和关闭自动插入都会进入置顶 ActionPanel。
- 如果有效本地录音后的转写失败，OmniVoice 会把 WAV 保留在内存中，并提供重试/取消，不要求你重新说一遍。
- `HUD 样式` 在 macOS 14/15 上支持 Automatic、Dark Capsule 和 Light Capsule。Liquid Glass 只会在 macOS 26+ 且系统原生 glass view 可用时显示。
- `提示显示时长` 控制短状态或 warning 提示显示多久。
- 录音波形使用实时 RMS：安静环境下低幅慢速运动，说话 attack 和近期音节会更快影响速度和振幅。
- 脱敏运行诊断写入 `~/Library/Logs/OmniVoice/diagnostics.log`。菜单不暴露完整诊断。

### 开发教程

#### 项目结构

这里只列出 Git 追踪的项目表面。`.build/`、已安装的 app bundle、本地配置文件、诊断日志和 harness 测试产物等生成内容不会纳入这里。

| 路径 | 用途 |
| --- | --- |
| `Package.swift` | Swift Package Manager 清单，定义 `OmniVoiceApp`、`OmniVoiceCore`、`OmniVoiceE2ESupport` 和测试 target。 |
| `Makefile` | 构建、安装、运行、清理、生成配置模板和测试的命令入口。 |
| `Sources/OmniVoiceApp/` | 最小可执行入口。 |
| `Sources/OmniVoiceCore/` | 生产 App 运行时：菜单、设置、权限、event tap、录音、MiMo client、HUD、ActionPanel、文本注入、配置、诊断和开机自启支持。 |
| `Sources/OmniVoiceE2ESupport/` | 仅供开发使用的 E2E 辅助能力，例如 WAV replay、注入命令和 GUI artifact 渲染。 |
| `Tests/OmniVoiceCoreTests/` | 覆盖配置、权限、触发键、录音/WAV、SSE 解析、API client、文本注入、HUD/ActionPanel、诊断和资源的单元测试。 |
| `Resources/` | App bundle 元数据和图标资源。 |
| `config/` | 面向用户和开发的 `config.jsonc` 示例模板。 |
| `assets/readme/` | README 演示 GIF 资源。 |
| `tools/` | 小型 App 本地开发工具，目前包含 App 图标生成器。 |
| `README.md` | 独立 OmniVoice 项目的 GitHub 首页文档，中文在前，英文在后。 |
| `.gitignore` | 生成构建、本地配置、日志和机器相关产物的忽略规则。 |

从项目根目录运行开发命令：

```sh
make build
make run
make dev-run
make install
make cleanup-legacy
make config-template
make test
```

`make build` 会创建并 ad-hoc 签名 `.build/OmniVoice.app`。`make install` 会先退出正在运行的已安装 OmniVoice，再把签名后的 bundle 复制到 `/Applications/OmniVoice.app`；`make run` 会先安装再打开这个已安装的 bundle。只有在明确需要从构建目录启动时才使用 `make dev-run`。

如需指定签名证书：

```sh
make build SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

由于 App 需要麦克风、辅助功能和输入监控权限，它按直接分发和 notarization 设计，不按 Mac App Store sandbox 分发设计。

## English

OmniVoice is a macOS 14+ menu-bar dictation utility. It is not a system input method, does not register an input source, and does not take over the active keyboard or input source. Hold the configured trigger key to record, release to transcribe with the MiMo OpenAI-compatible API, then let OmniVoice insert the final text into the focused field or show a topmost ActionPanel for copy, style switching, retry, or cancel.

### Demo

The result ActionPanel expands from the listening/transcribing HUD, keeps the style switcher in the button row, and supports both dark and light capsule palettes. When Auto Insert is enabled and the focused field is safe, the recognized text can be inserted automatically; the ActionPanel appears when insertion is disabled, unsafe, unavailable, or explicitly forced for review. The English demos use English UI and English input, with a longer streaming transcription phase so the preview animation is visible.

| Dark Capsule | Light Capsule |
| --- | --- |
| <img src="assets/readme/action-panel-dark-en.gif" alt="OmniVoice dark capsule ActionPanel flow in English" width="420"> | <img src="assets/readme/action-panel-light-en.gif" alt="OmniVoice light capsule ActionPanel flow in English" width="420"> |

### Usage Tutorial

1. Start OmniVoice from `/Applications/OmniVoice.app`. If you are running from source, use `make run` in the Developer Guide once first.
2. Open the menu-bar icon and check the permission summary.
3. Use `Request All Permissions` if microphone, Accessibility, or Input Monitoring is missing.
4. Open `Configuration` -> `Open config file` and fill in your MiMo API source and API key.
5. Click `Reload Config`, then `Check Connection & Latency`.
6. Put the cursor in any editable text field.
7. Hold the trigger key, speak, then release the key.

If Auto Insert is enabled and the target field is safe, OmniVoice inserts the final text directly. If the target is unsafe or unavailable, OmniVoice opens the ActionPanel instead, so you can copy the text, switch style and retranscribe from the cached audio, or cancel.

### Everyday Controls

- Default trigger key: Fn/Globe.
- Available trigger keys: Fn/Globe, F1-F12, left/right Shift, Control, Option, Command, and Caps Lock.
- Escape cancels recording/transcription and closes the ActionPanel.
- If system input gets stuck after a permission or reinstall problem, `Fn/Globe + Esc` stops listening, persists the stopped state, and quits OmniVoice.
- `Auto Insert` controls whether safe final text is inserted automatically.
- `Transcription Style` is ordered as Verbatim, Concise, Technical, Rewrite, then custom styles from `config.jsonc`; Concise is the default.
- `Technical` preserves commands, paths, identifiers, casing, symbols, and mixed Chinese/English technical speech.
- `Rewrite` may polish tone and structure, but must not add facts, promises, recipients, signatures, or content the user did not express.
- Result panels show Copy, a themed style switcher, and Cancel. Choosing another style only affects that panel and does not change the global default.

### Configuration

OmniVoice stores connection settings only in `~/.config/omnivoice/config.jsonc`. The file uses JSONC, so comments and trailing commas are allowed. Environment variables and Keychain are not app configuration sources.

Use `Open config file` from the `Configuration` submenu to edit connection settings. OmniVoice creates a localized JSONC template when the file does not exist, then tries to open it in an installed code editor such as VS Code, Cursor, Windsurf, Zed, Sublime Text, BBEdit, TextMate, or Xcode. If none is available, it falls back to the system default app. API keys are edited only in `config.jsonc` and are always redacted in the menu.

Example config:

```jsonc
{
  "active_source": "auto",
  "default_model": "mimo-v2-omni",
  "sources": {
    "sgp": {
      "base_url": "https://token-plan-sgp.xiaomimimo.com",
      "api_key": ""
    },
    "cn": {
      "base_url": "https://token-plan-cn.xiaomimimo.com",
      "api_key": ""
    }
  },
  "latency": {
    "enabled": true,
    "interval_seconds": 1800
  },
  "custom_styles": {
    "meeting_notes": {
      "display_name": "Meeting Notes",
      "display_name_zh": "会议纪要",
      "description": "Turn speech into concise meeting notes.",
      "description_zh": "把口述整理成简洁会议纪要。",
      "prompt_lines": [
        "Turn this audio into concise meeting notes.",
        "Preserve explicitly spoken decisions, todos, times, names, project names, and technical terms.",
        "Use a short line-by-line list when there are multiple points.",
        "Do not add facts, conclusions, owners, or deadlines that the user did not say."
      ]
    }
  }
}
```

Create a local template from the source checkout with:

```sh
make config-template
```

If `config.jsonc` contains an API key, protect it yourself:

```sh
chmod 600 ~/.config/omnivoice/config.jsonc
```

`active_source: "auto"` chooses the fastest reachable source whose `/v1/models` response includes a supported speech model. `auto` is reserved and cannot be used as a normal source id.

Use `custom_styles` to add your own transcription prompts. Each style needs a safe ID, a display name, and either `prompt` or `prompt_lines`. Custom styles are marked as `Custom` in the Style menu and in the result panel style switcher.

### Permissions

OmniVoice checks permissions at launch and each time the menu opens:

- Microphone records speech with `AVAudioEngine`.
- Accessibility checks whether the current text field can receive text, then inserts when possible.
- Input Monitoring lets OmniVoice notice when you press and release the trigger key.

If OmniVoice is already listed under Accessibility or Input Monitoring but the app still reports missing permission, remove the stale row, click `+`, and choose `/Applications/OmniVoice.app` again. macOS privacy permissions are path-sensitive, so using the installed app path matters.

When running from source repeatedly with `make run`, the install step first quits the old `/Applications/OmniVoice.app` instance before replacing and reopening the bundle, so an older process cannot keep holding input-monitoring permissions.

### Menu Layout

All settings live in the menu bar. There is no Dock icon, Settings window, popover, sheet, or input-source registration.

The menu is grouped as control, configuration, transcription, experience/system, and final app actions. It includes `Stop` or `Re-enable`, status, permissions, redacted Base URL/API Key/current model/source, `Configuration`, `Language`, `Transcription Style`, `Trigger Key`, `Recording Duration`, `Launch at Login`, `Auto Insert`, `HUD Style`, `Message Duration`, `Permission Management`, `Restart OmniVoice`, and `Quit OmniVoice`.

Model selection, Reload Config, Refresh Models, API Source, latency settings, config opening, and the combined Check Connection & Latency action live inside the Configuration submenu. The `Language` menu controls UI language; transcription output defaults to simplified Chinese and switches to English when the audio is mainly English.

Speech model choices are limited to `mimo-v2-omni` and `mimo-v2.5`; TTS and Pro models are filtered out.

### Runtime Notes

- The `Recording Duration` menu shows the current min-max range, for example `Duration: 500ms-60s`. Minimum choices are 300ms, 500ms, 800ms, 1s, 2s, and 3s; maximum choices are 15s, 30s, 60s, 120s, and 300s.
- WAV upload format is 16 kHz mono little-endian Int16 PCM in a WAV container.
- Auto insertion uses conservative Accessibility insertion for standard native text fields, then falls back to clipboard preservation plus Cmd+V.
- Secure text fields, passwords, verification codes, token/API-key-like fields, missing focus, missing permissions, paste failures, and disabled Auto Insert all use the topmost ActionPanel.
- If transcription fails after a valid local recording, OmniVoice keeps the WAV in memory and offers Retry/Cancel without requiring you to speak again.
- `HUD Style` supports Automatic, Dark Capsule, and Light Capsule on macOS 14/15. Liquid Glass appears only on macOS 26+ when the native glass view is available.
- `Message Duration` controls how long short status or warning messages remain visible.
- Recording waveform uses live RMS: quiet rooms get slower low-amplitude motion, while speech attacks and recent syllables quickly affect speed and amplitude.
- Redacted runtime diagnostics are appended to `~/Library/Logs/OmniVoice/diagnostics.log`. The menu does not expose full diagnostics.

### Developer Guide

#### Project Structure

Only Git-tracked project surfaces are listed here. Generated paths such as `.build/`, installed app bundles, local config files, diagnostics logs, and harness test artifacts are intentionally excluded.

| Path | Purpose |
| --- | --- |
| `Package.swift` | Swift Package Manager manifest for the `OmniVoiceApp`, `OmniVoiceCore`, `OmniVoiceE2ESupport`, and test targets. |
| `Makefile` | Build, install, run, cleanup, config-template, and test command surface. |
| `Sources/OmniVoiceApp/` | Minimal executable entrypoint. |
| `Sources/OmniVoiceCore/` | Production app runtime: menu, settings, permissions, event tap, recording, MiMo client, HUD, ActionPanel, injection, configuration, diagnostics, and launch-at-login support. |
| `Sources/OmniVoiceE2ESupport/` | Developer-only E2E helpers such as WAV replay, injection commands, and GUI artifact rendering. |
| `Tests/OmniVoiceCoreTests/` | Unit coverage for configuration, permissions, trigger keys, recording/WAV, SSE parsing, API client behavior, injection, HUD/ActionPanel, diagnostics, and resources. |
| `Resources/` | App bundle metadata and icon resources. |
| `config/` | Example `config.jsonc` template shipped for users and development. |
| `assets/readme/` | README demo GIF assets. |
| `tools/` | Small app-local development utilities, currently the app icon generator. |
| `README.md` | GitHub-facing README for the standalone OmniVoice project, with Chinese first and English second. |
| `.gitignore` | Ignore rules for generated builds, local config, logs, and machine-specific artifacts. |

Run development commands from the repository root:

```sh
make build
make run
make dev-run
make install
make cleanup-legacy
make config-template
make test
```

`make build` creates and ad-hoc signs `.build/OmniVoice.app`. `make install` first quits the running installed OmniVoice, then copies the signed bundle to `/Applications/OmniVoice.app`; `make run` installs first and opens that installed bundle. Use `make dev-run` only when you deliberately want to launch from the build directory.

Override signing with:

```sh
make build SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

The app is designed for direct distribution and notarization, not Mac App Store sandboxing, because it needs microphone, Accessibility, and Input Monitoring permissions.
