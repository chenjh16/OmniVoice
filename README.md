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

把一个按键变成全局高质量输入：OmniVoice 在本地录音，可用多模态语音模型直接转写，也可先用 Apple Speech 得到草稿再交给文本模型修正，或仅使用系统 ASR 输出文字，最后安全插入任意可编辑输入框。

OmniVoice 是一个 macOS 14+ 菜单栏语音听写工具。它不是系统输入法，不注册 input source，也不接管当前键盘或输入源。按住已配置的触发键开始录音，松开后通过 MiMo、其他 OpenAI-compatible 模型管线或 macOS 系统 ASR 生成最终文本；如果无法安全插入，则显示置顶 ActionPanel，供你复制、切换风格、重试或取消。

### 演示

结果 ActionPanel 会从聆听/转写 HUD 位置展开，底部保留风格切换控件，并同时支持深色和浅色胶囊配色。当开启自动插入且当前输入框安全可写时，识别出的文本可以自动插入；当插入被关闭、目标不安全、不可用，或测试时强制进入面板时，才会显示 ActionPanel 供确认。中文演示使用中文 UI 和中文输入，转写阶段保留更长的流式预览时间。

| 深色胶囊 | 浅色胶囊 |
| --- | --- |
| <img src="assets/readme/action-panel-dark.gif" alt="OmniVoice 深色胶囊 ActionPanel 流程" width="420"> | <img src="assets/readme/action-panel-light.gif" alt="OmniVoice 浅色胶囊 ActionPanel 流程" width="420"> |

### 使用教程

1. 从 `/Applications/OmniVoice.app` 启动 OmniVoice。如果你从源码运行，请先按开发教程执行一次 `make run`。
2. 打开菜单栏图标，查看权限摘要。
3. 如果麦克风、辅助功能、输入监控或语音识别缺失，点击 `请求所有权限`。
4. 打开 `配置` -> `打开 config 文件`，填写 MiMo 或其他 OpenAI-compatible API 来源和 API Key。
5. 点击 `重新加载配置`，再点击 `检查连接与测速`。
6. 把光标放进任意可编辑输入框。
7. 按住触发键，说完后松开。

如果开启了自动插入，且目标输入框安全可写，OmniVoice 会直接插入最终文本。如果目标不安全或不可用，OmniVoice 会打开 ActionPanel，你可以复制文本、切换风格并基于缓存音频重新转写，或取消。

### 日常控制

- 默认触发键：Fn/Globe。
- 可选触发键：Fn/Globe、F1-F12、左右 Shift、Control、Option、Command，以及 Caps Lock。
- `触发键` 子菜单里的 `双击持续录音` 默认关闭；开启后，Fn/Globe、F1-F12 和左右修饰键可以双击进入持续录音，再单击停止。Caps Lock 由于系统事件稳定性暂不参与。
- Escape 会取消录音/转写，并关闭 ActionPanel。
- 如果系统输入在权限或重装异常后卡住，按 `Fn/Globe + Esc` 会停止监听、保存为停止状态并退出 OmniVoice。
- `自动插入` 控制是否把安全的最终文本自动写入当前输入框。
- `风格` 顺序为原文、精炼、技术、重写，然后显示来自 `config.jsonc` 的自定义风格；默认是重写。
- `关键词` 可以把已勾选的关键词组作为识别提示加入转写 prompt，适合专有名词、产品名、命令、路径和领域术语。
- `技术` 适合命令、路径、标识符、大小写、符号和中英混杂技术口述。
- `重写` 可以润色语气和结构，但不得新增事实、承诺、收件人、署名或用户没有表达的内容。
- 结果面板显示复制、主题化风格切换和取消。选择另一个风格只影响当前面板，不会修改全局默认风格。

### 配置

OmniVoice 内部带有一份完整默认配置，并只从 `~/.config/omnivoice/config.jsonc` 读取用户覆写项。运行时由 `AppConfigStore` 持有“默认配置 + 用户覆写”合并后的有效配置，菜单读取、菜单写入、热重载和 JSONC 序列化都走这一份对象。这个文件使用 JSONC，支持注释和尾随逗号；你可以只写 `sources`、`active_source` 或某个模型默认值，缺省字段会继续继承 App 默认配置。环境变量和 Keychain 都不是 App 配置来源。

请通过 `配置` 子菜单里的 `打开 config 文件` 编辑连接设置。如果文件不存在、格式错误或缺少必要字段，OmniVoice 会先把旧文件备份为 `config.jsonc.bak-YYYYMMDD-HHMMSS`，再创建当前界面语言的完整 JSONC 模板，然后优先用支持行号定位的 VS Code `code --goto`、Cursor `cursor --goto`、Zed `zed file:line:column` 或 Xcode `xed -l` 打开；找不到这些 CLI 时再回退到已安装编辑器 app bundle，最后回退到系统默认应用。API Key 只在 `config.jsonc` 中编辑，菜单中始终脱敏展示。

菜单里的转写模式与模型、语言、风格、关键词提示开关、关键词组多选、触发键、录音时长、自动插入、开机自启、HUD 样式、实时 ASR 预览、提示显示时长、HUD 弹出延迟、系统语音识别引擎、API 来源和测速频率都会写回 `config.jsonc`。切换界面语言时，OmniVoice 也会用对应语言重写配置注释。

示例配置：

```jsonc
{
  "active_source": "cn",
  "transcription_pipeline": { "mode": "input_audio" },
  "models": {
    "audio_llm": {
      "default_model": "mimo-v2.5",
      "extra_models": [
        "mimo-v2-omni",
        "gpt-audio-1.5",
        "gpt-audio",
        "gpt-audio-2025-08-28",
        "gemini-3.1-pro-preview",
        "gemini-3.1-flash-lite",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "qwen3.5-omni-plus",
        "qwen3.5-omni-flash",
        "qwen3-omni-flash"
      ]
    },
    "text_llm": {
      "default_model": "mimo-v2.5"
    }
  },
  "system_asr": {
    "engine": "speech_analyzer",
    "keyword_hints_enabled": true
  },
  "sources": {
    "cn": {
      "base_url": "https://token-plan-cn.xiaomimimo.com",
      "api_key": ""
    },
    "sgp": {
      "base_url": "https://token-plan-sgp.xiaomimimo.com",
      "api_key": ""
    }
  },
  "latency": {
    "enabled": true,
    "interval_seconds": 1800
  },
  "preferences": {
    "ui_language": "zh-Hans",
    "transcription_style": "rewrite",
    "keyword_hints_enabled": false,
    "enabled_keyword_groups": [],
    "trigger_key": "fn-globe",
    "trigger": {
      "continuous_recording_double_tap_enabled": false
    },
    "min_recording_duration_ms": 500,
    "max_recording_duration_seconds": 120,
    "auto_insert": true,
    "launch_at_login": true,
    "hud": {
      "visual_style": "automatic",
      "message_duration_seconds": 3,
      "reveal_delay_ms": 100,
      "live_asr_preview_enabled": false
    }
  },
  "custom_styles": {
    "meeting_notes": {
      "display_name": "Meeting Notes",
      "prompt_lines": [
        "请把这段音频整理成简洁会议纪要。",
        "保留明确说出的决定、待办、时间、人名、项目名和技术词。",
        "如果有多个要点，使用简短的换行列表。",
        "不要新增用户没有说出的事实、结论、负责人或截止日期。"
      ]
    }
  },
  "keyword_groups": {
    "mimo_e2e_terms": {
      "display_name": "MiMo E2E Terms",
      "keywords": [
        "OmniVoice",
        "MiMo",
        "mimo-v2.5",
        "mimo-v2-omni",
        "mimo-v2-pro",
        "mimo-v2.5-pro",
        "config.jsonc",
        "Swift",
        "API"
      ]
    },
    "omnivoice_terms": {
      "display_name": "OmniVoice 术语",
      "keywords": [
        "OmniVoice",
        "MiMo",
        "mimo-v2.5",
        "mimo-v2-omni",
        "mimo-v2-pro",
        "mimo-v2.5-pro",
        "config.jsonc",
        "ActionPanel",
        "HUD",
        "Panel"
      ]
    },
    "technical_terms": {
      "display_name": "技术术语",
      "keywords": [
        "Swift",
        "AppKit",
        "macOS",
        "JSONC",
        "API",
        "make run",
        "Cmd+V",
        "Fn"
      ]
    },
    "llm_model_terms": {
      "display_name": "大模型与模型公司",
      "keywords": [
        "OpenAI",
        "ChatGPT",
        "GPT",
        "Anthropic",
        "Claude",
        "Claude Code",
        "Opus",
        "Sonnet",
        "Haiku",
        "Google",
        "Gemini",
        "Gemma",
        "Llama",
        "Mistral",
        "xAI",
        "Grok",
        "Qwen",
        "Qwen3",
        "Qwen3.5",
        "Qwen3.6",
        "Qwen Omni",
        "DeepSeek",
        "Kimi",
        "MiniMax",
        "Zhipu AI",
        "智谱",
        "GLM",
        "Hunyuan",
        "StepFun",
        "阶跃星辰",
        "SenseNova",
        "Hermes",
        "OpenClaw",
        "Hugging Face"
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

`active_source: "auto"` 会在支持当前所选模型的 API 来源中选择 `/v1/models` 可访问且测速最快者。`auto` 是保留值，不能作为普通 source id。如果当前模型只存在于一个来源，OmniVoice 会把 API 来源固定到该来源，并在菜单中灰掉其他不支持该模型的来源。切换到 `仅系统 ASR` 后，API 来源菜单会显示为仅系统 ASR，来源项会置灰，因为该模式不会调用模型 API。

`transcription_pipeline.mode` 支持 `input_audio`、`system_asr_text_llm` 和 `system_asr_only`。菜单文案分别显示为 `音频直转`、`语音识别 + 文本转写` 和 `仅系统 ASR`。`input_audio` 管线使用 `models.audio_llm` 选择音频 LLM，默认是 `mimo-v2.5`，并允许加入 `mimo-v2-omni`、GPT Audio、Gemini、Qwen Omni 等额外候选；`system_asr_text_llm` 会把系统 ASR 草稿标记为不可靠输入，再交给 `models.text_llm.default_model` 指定的文本模型修正、重写和应用风格；`system_asr_only` 只使用当前 `system_asr.engine` 输出原始系统 ASR final，不使用模型、风格重写或 LLM prompt。Text LLM 菜单直接显示可达 API 来源 `/v1/models` 的观测并集，并默认隐藏名称明显包含 TTS、voiceclone 或 voicedesign 的模型；如果某个观测模型实际不支持文本补全，请求失败时 OmniVoice 会在 ActionPanel 中提示更换文本模型，而不会静默插入 ASR 草稿。

`system_asr.engine` 支持 `classic_speech`、`speech_analyzer` 和 `apple_online_speech`。默认 `speech_analyzer` 是 macOS 26+ 的端侧 SpeechAnalyzer 适配层；`classic_speech` 是端侧经典 Speech；`apple_online_speech` 是显式选择的 Apple 在线识别，macOS 可免费调用，但音频可能发送给 Apple，并受 Apple 服务可用性、每日限制和约一分钟任务限制影响。

可以用 `custom_styles` 添加自己的转写 prompt。每个风格需要一个安全 ID、显示名称，以及 `prompt` 或 `prompt_lines`。自定义风格会在风格菜单和结果面板风格切换中标记为 `自定义`。

可以用 `keyword_groups` 添加多组关键词，再通过菜单里的 `关键词` 分组勾选控制是否注入。关键词默认未启用且不预选任何分组；勾选任一分组会自动启用，取消最后一个分组会自动回到未启用。默认模板包含 `llm_model_terms` 分组，用于常见大模型公司、模型系列和模型名，例如 OpenAI/GPT、Anthropic/Claude/Claude Code、Google/Gemini、Qwen、DeepSeek、Kimi、Llama、Mistral、Grok、GLM、Hunyuan、SenseNova、Hermes、OpenClaw 和 Hugging Face 等。关键词只作为识别消歧提示使用：模型会在发音和上下文合理时优先参考它们，但不会因为列表里有某个词就强行输出。每组最多使用 200 个关键词，总计最多注入 500 个。`custom_styles` 和 `keyword_groups` 只需要可选的 `display_name`；没有 `display_name` 时菜单显示对应 ID，不再维护 `*_zh` 或 `description` 字段。

OmniVoice 会监听 `config.jsonc` 的保存和更新。有效配置会自动热更新，并显示一条短暂 HUD 提示；如果热更新时文件格式或必要字段有问题，OmniVoice 会继续使用上一份有效配置，把当前运行配置导出为 `config.current-YYYYMMDD-HHMMSS.jsonc`，并提示你检查原配置文件。

### 权限

OmniVoice 启动时和每次打开菜单时都会检查权限：

- 麦克风：使用 `AVAudioEngine` 录音。
- 辅助功能：检查当前输入框是否可以接收文本，并在安全时写入。
- 输入监控：感知触发键的按下和松开。
- 语音识别：调用 macOS Speech 生成 `语音识别 + 文本转写` / `仅系统 ASR` 的最终草稿，也用于音频直转在发起模型请求前做本地有效语音预判。

如果已经打开当前 App 的权限，但 OmniVoice 仍显示无法获得对应权限，请不要只反复开关权限；先在对应的隐私设置中移除 OmniVoice，再点击 `+` 重新添加 `/Applications/OmniVoice.app`，最后重新打开权限。macOS 隐私权限和 App 路径相关，因此使用已安装 App 路径很重要。

辅助功能和输入监控权限在新版 macOS 上不一定显示传统允许/拒绝弹窗；菜单里的 `请求辅助功能权限`、`请求输入监控权限` 和 `请求所有权限` 会先触发系统提示，让 macOS 尝试把 OmniVoice 登记到对应权限列表中。macOS 弹出的“去系统设置开启”权限引导小对话框可能出现在其他桌面/全屏 Space；如果当前桌面没看到，请检查 Mission Control、其他 Space 或 Cmd+Tab。OmniVoice 也会 best-effort 打开对应系统设置页，但不能强制这个系统小对话框出现在当前 Space。

开发期如果使用 ad-hoc 签名反复替换 `/Applications/OmniVoice.app`，macOS TCC 可能不会把当前 App 自动登记到辅助功能列表。建议使用稳定签名身份运行，例如本机自签名的 `OmniVoice Local Development`，并在重试前清理旧的辅助功能记录：

```sh
cd OmniVoice
tccutil reset Accessibility dev.local.omnivoice
make run SIGN_IDENTITY="OmniVoice Local Development"
```

如果 `security find-identity -p codesigning` 能看到该身份但 Gatekeeper 仍显示 `spctl ... rejected`，这是因为本机自签名证书还未在钥匙串中完全信任；本地开发可先验证 TCC 行为，必要时在“钥匙串访问”里把该证书设为始终信任。

如果你从源码反复运行 `make run`，安装流程会先退出旧的 `/Applications/OmniVoice.app` 实例，再替换并打开新 bundle，避免旧进程继续持有输入监听权限。

### 菜单布局

所有设置都在菜单栏内完成。没有 Dock 图标、Settings 窗口、popover、sheet，也不注册输入源。

菜单按控制、配置、转写、体验/系统和最后 App 操作分段组织，包含 `停止` 或 `重新启用`、状态、权限、脱敏 Base URL/API Key、`转写：音频直转 · <model>`、`转写：语音识别 + 文本转写 · <model>` 或 `转写：仅系统 ASR · <engine>`、`配置`、`语言`、`风格`、`关键词`、`触发键`、`录音时长`、`开机自启`、`自动插入`、`提示与显示`、`权限管理`、`重启` 和 `退出`。主菜单不再显示只读的 `来源：...` 行，API 来源只在配置子菜单中操作。

`提示与显示` 子菜单包含 `实时 ASR 预览`、`HUD 样式`、`提示显示时长` 和 `HUD 弹出延迟`。实时 ASR 预览默认关闭；开启后录音期间会用系统语音识别在 HUD 中显示实时文本。音频直转和语音识别 + 文本转写会显示自绘居中的 `草稿` 徽标和最近草稿尾部；仅系统 ASR 显示 `识别` 徽标，表示这是当前模式会直接使用的实时识别文本。即使关闭 HUD 预览，音频直转也会在录音期间同步收集系统 ASR 证据，用于松手后本地判断是否听到可靠语音；如果系统 ASR 正常运行但没有任何文字且 RMS 不强，OmniVoice 会直接提示重试，不调用大模型 API。HUD 展示层会折叠 ASR partial 中的换行和连续空白，避免单行预览出现大段空格；长文本不显示省略号，而是在左侧使用约 100px 渐隐来提示前文被裁掉；同一次录音里 HUD 只会随预览增长，不会因为系统 ASR 修订出更短 partial 而突然回缩。`语音识别 + 文本转写` 和 `仅系统 ASR` 都会保留最短录音时长检查，但不会因为本地 RMS 偏低而跳过已有 ASR final；仅系统 ASR 松手后只显示“正在完成识别”，不显示模型转写进度条。睡眠、唤醒、锁屏或解锁后，OmniVoice 会取消残留 live ASR 会话，短时间优先经典 Speech，并延迟探测 SpeechAnalyzer 是否恢复，避免必须重启 App 才能恢复实时预览。HUD 弹出延迟默认 100ms，可选 100ms、200ms、300ms、400ms、500ms；录音仍会在按下触发键时立即开始。

模型选择、转写模式、系统 ASR 设置、重新加载配置、刷新模型、API 来源、测速设置、打开配置文件，以及合并后的检查连接与测速都位于配置子菜单内。`模型` 子菜单先显示模式，再只显示当前模式对应的模型列表：音频直转时不显示文本模型设置，语音识别 + 文本转写时不显示音频模型设置，仅系统 ASR 时显示只读提示 `此模式不使用大模型`。`API 来源` 子菜单底部有 `仅使用系统 ASR 能力` 勾选项；开启后来源项不可选，再次点击会回到音频直转。模型子菜单底部提供 `编辑模型列表`，会复用打开 config 文件逻辑并尽量定位到 `models.audio_llm`，方便直接修改 Audio LLM 候选和 `models.text_llm.default_model`。`语言` 菜单控制 UI 语言；转写输出默认简体中文，如果音频主要是英文则输出英文。

音频直转模式默认使用 `mimo-v2.5`，并在 `models.audio_llm.extra_models` 中预置 `mimo-v2-omni` 和三方 Audio LLM 候选。Audio LLM 模型菜单只展示 `配置模型池 ∩ 所有 API 来源 /v1/models 观测结果`；Text LLM 模型菜单展示可达来源的观测模型并集，并默认排除明显的 TTS/voiceclone/voicedesign 模型。如果还没有任何观测模型，菜单显示刷新提示，不展开 seeded 长列表。`刷新模型` 会刷新所有已配置来源，API 来源菜单会把不支持当前模型的来源置灰。

### 运行说明

- `录音时长` 菜单会显示当前最短到最长区间，例如 `录音时长：500ms-60s`。最短可选 300ms、500ms、800ms、1s、2s、3s；最长可选 15s、30s、60s、120s、300s。
- `双击持续录音` 开启后，第一次短按会等待第二击；若没有第二击，则按普通短录音收尾。进入持续录音后，下一次单击触发键停止，实际停止处理会在该次单击抬起后开始，避免长录音导出阻塞触发键释放确认；最长录音时长仍会作为安全上限。
- 上传 WAV 格式为 16 kHz mono little-endian Int16 PCM WAV。
- 自动插入会对标准原生文本框优先使用保守辅助功能写入，再回退到保存剪贴板 + Cmd+V。
- Secure text field、密码、验证码、token/API-key-like 输入框、无焦点、缺权限、粘贴失败和关闭自动插入都会进入置顶 ActionPanel。
- 如果有效本地录音后的转写失败，OmniVoice 会把 WAV 保留在内存中，并提供重试/取消，不要求你重新说一遍。
- 模型转写阶段的细进度条会跟随 OpenAI-compatible streaming 请求阶段变化：准备和连接阶段先使用较短上限，收到 HTTP 响应和等待首个 delta 时继续推进，首个流式文本到达后切换到更稳定的流式状态颜色，并且只在完成事件后到 100%。
- `HUD 样式` 在 macOS 14/15 上支持 Automatic、Dark Capsule 和 Light Capsule。Automatic 会跟随系统亮暗外观：浅色系统使用浅色胶囊，深色系统使用深色胶囊。Liquid Glass 只会在 macOS 26+ 且系统原生 glass view 可用时显示；HUD 和 ActionPanel 会共用原生玻璃、圆角外部深度和外描边文字光晕，避免亮背景下文字被描边吃细。
- `提示显示时长` 控制短状态或 warning 提示显示多久。
- `HUD 弹出延迟` 只影响 HUD 何时出现，不影响录音开始时间；组合快捷键会在 HUD 出现前静默取消。
- 录音波形使用实时 RMS：安静环境下低幅慢速运动，说话 attack 和近期音节会更快影响速度和振幅。
- 脱敏运行诊断写入 `~/Library/Logs/OmniVoice/diagnostics.log`。菜单不暴露完整诊断。

### 开发教程

#### 项目结构

这里只列出 Git 追踪的项目表面。`.build/`、已安装的 app bundle、本地配置文件、诊断日志和 harness 测试产物等生成内容不会纳入这里。

| 路径 | 用途 |
| --- | --- |
| `Package.swift` | Swift Package Manager 清单，定义发布用 `OmniVoiceApp`、E2E 用 `OmniVoiceE2EApp`、`OmniVoiceCore`、`OmniVoiceE2ESupport` 和测试 target。 |
| `Makefile` | 构建、安装、运行、清理、生成配置模板、测试和 `check` 的命令入口。 |
| `Sources/OmniVoiceApp/` | 最小发布可执行入口，不链接 E2E 注入命令。 |
| `Sources/OmniVoiceE2EApp/` | 仅供 GUI/真实模型 E2E 验证使用的可执行入口，会链接隐藏 E2E 命令。 |
| `Sources/OmniVoiceCore/` | 生产 App 运行时，按领域目录组织：App、Configuration、Menu、Permissions、Trigger、Recording、ASR、API、Injection、UI、Models、Diagnostics 和 Shared。 |
| `Sources/OmniVoiceE2ESupport/` | 仅供开发使用的 E2E 辅助能力，例如 WAV replay、注入命令和 GUI artifact 渲染。 |
| `Tests/OmniVoiceCoreTests/` | 按领域目录镜像组织的核心单元测试，覆盖配置、权限、触发键、录音/WAV、系统 ASR、API client、文本注入、HUD/ActionPanel、诊断和资源。 |
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
make check
```

`make build` 默认会 ad-hoc 签名 `.build/OmniVoice.app`，并安装不带 E2E 注入入口的发布形态 binary。`make install` 会先退出正在运行的已安装 OmniVoice，再把签名后的 bundle 复制到 `/Applications/OmniVoice.app`；`make run` 会先安装再打开这个已安装的 bundle。只有在明确需要从构建目录启动时才使用 `make dev-run`。GUI E2E harness 需要安装带隐藏 E2E 命令的同名 bundle，请使用 `make run ENABLE_E2E=1`；因为音频直转也会启动 live ASR 证据收集，任何可能触发语音识别或其它隐私用途说明的 GUI E2E 都应使用 `--launch-services` 通过完整 `.app` bundle 启动。完成验证后再运行普通 `make run` 可恢复发布形态安装。`make check` 会执行 `git diff --check`、`swift test` 和 `make build`。

涉及辅助功能、输入监控或反复重装验证时，优先使用稳定签名身份，而不是默认 ad-hoc 签名。当前本机开发验证使用的身份名是 `OmniVoice Local Development`：

```sh
security find-identity -p codesigning
make run SIGN_IDENTITY="OmniVoice Local Development"
```

如果辅助功能列表中没有 OmniVoice，先重置当前 bundle id 的辅助功能记录，再用同一个签名身份重新安装启动：

```sh
tccutil reset Accessibility dev.local.omnivoice
make run SIGN_IDENTITY="OmniVoice Local Development"
```

如需指定签名证书：

```sh
make build SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

默认 `SIGN_IDENTITY=-` 是 ad-hoc 签名，只适合本机开发和快速 TCC 验证；`OmniVoice Local Development` 这类本机自签名身份也只适合本机稳定测试。公开 release 不应使用 `dev.local.omnivoice` + ad-hoc/self-signed 包。面向其他用户分发时，请使用稳定正式 bundle id、Apple 签发的 `Developer ID Application` 证书、hardened runtime、notarization 和 stapling，再生成 zip/dmg。

由于 App 需要麦克风、辅助功能、输入监控和语音识别权限，它按直接分发和 notarization 设计，不按 Mac App Store sandbox 分发设计。

## English

Turn one held key into high-quality text anywhere on macOS. OmniVoice records locally, transcribes with omnimodal speech models, Apple Speech plus a text LLM, or system ASR alone, then safely inserts the final result.

OmniVoice is a macOS 14+ menu-bar dictation utility. It is not a system input method, does not register an input source, and does not take over the active keyboard or input source. Hold the configured trigger key to record, release to process through MiMo, another OpenAI-compatible model pipeline, or macOS system ASR, then let OmniVoice insert the final text into the focused field or show a topmost ActionPanel for copy, style switching, retry, or cancel.

### Demo

The result ActionPanel expands from the listening/transcribing HUD, keeps the style switcher in the button row, and supports both dark and light capsule palettes. When Auto Insert is enabled and the focused field is safe, the recognized text can be inserted automatically; the ActionPanel appears when insertion is disabled, unsafe, unavailable, or explicitly forced for review. The English demos use English UI and English input, with a longer streaming transcription phase so the preview animation is visible.

| Dark Capsule | Light Capsule |
| --- | --- |
| <img src="assets/readme/action-panel-dark-en.gif" alt="OmniVoice dark capsule ActionPanel flow in English" width="420"> | <img src="assets/readme/action-panel-light-en.gif" alt="OmniVoice light capsule ActionPanel flow in English" width="420"> |

### Usage Tutorial

1. Start OmniVoice from `/Applications/OmniVoice.app`. If you are running from source, use `make run` in the Developer Guide once first.
2. Open the menu-bar icon and check the permission summary.
3. Use `Request All Permissions` if microphone, Accessibility, Input Monitoring, or Speech Recognition is missing.
4. Open `Configuration` -> `Open config file` and fill in your MiMo or other OpenAI-compatible API source and API key.
5. Click `Reload Config`, then `Check Connection & Latency`.
6. Put the cursor in any editable text field.
7. Hold the trigger key, speak, then release the key.

If Auto Insert is enabled and the target field is safe, OmniVoice inserts the final text directly. If the target is unsafe or unavailable, OmniVoice opens the ActionPanel instead, so you can copy the text, switch style and retranscribe from the cached audio, or cancel.

### Everyday Controls

- Default trigger key: Fn/Globe.
- Available trigger keys: Fn/Globe, F1-F12, left/right Shift, Control, Option, Command, and Caps Lock.
- `Double-tap Continuous Recording` in the Trigger menu defaults off. When enabled, Fn/Globe, F1-F12, and left/right modifiers can be double-tapped to keep recording and tapped once again to stop. Caps Lock is excluded until its event sequence is proven stable.
- Escape cancels recording/transcription and closes the ActionPanel.
- If system input gets stuck after a permission or reinstall problem, `Fn/Globe + Esc` stops listening, persists the stopped state, and quits OmniVoice.
- `Auto Insert` controls whether safe final text is inserted automatically.
- `Transcription Style` is ordered as Verbatim, Concise, Technical, Rewrite, then custom styles from `config.jsonc`; Rewrite is the default.
- `Keyword Hints` can inject selected keyword groups into the transcription prompt as recognition hints for proper nouns, product names, commands, paths, and domain terms.
- `Technical` preserves commands, paths, identifiers, casing, symbols, and mixed Chinese/English technical speech.
- `Rewrite` may polish tone and structure, but must not add facts, promises, recipients, signatures, or content the user did not express.
- Result panels show Copy, a themed style switcher, and Cancel. Choosing another style only affects that panel and does not change the global default.

### Configuration

OmniVoice carries a complete built-in default config and reads user overrides only from `~/.config/omnivoice/config.jsonc`. At runtime, `AppConfigStore` owns the effective merged object of built-in defaults plus user overrides; menu reads, menu writes, hot reloads, and JSONC serialization all go through that object. The file uses JSONC, so comments and trailing commas are allowed; you can write only `sources`, `active_source`, or a model default, and omitted fields keep the app defaults. Environment variables and Keychain are not app configuration sources.

Use `Open config file` from the `Configuration` submenu to edit connection settings. If the file is missing, invalid, or incomplete, OmniVoice first backs up the old file as `config.jsonc.bak-YYYYMMDD-HHMMSS`, then creates a complete localized JSONC template and first tries line-aware editor CLIs: VS Code `code --goto`, Cursor `cursor --goto`, Zed `zed file:line:column`, or Xcode `xed -l`. If those are unavailable, it falls back to installed editor app bundles and finally the system default app. API keys are edited only in `config.jsonc` and are always redacted in the menu.

Menu choices for transcription mode and model, language, style, keyword hint enablement, keyword group selection, trigger key, recording duration, Auto Insert, Launch at Login, HUD style, Live ASR Preview, message duration, HUD reveal delay, System ASR engine, API source, and latency interval are written back to `config.jsonc`. When you switch UI language, OmniVoice rewrites the config comments in the selected language.

Example config:

```jsonc
{
  "active_source": "cn",
  "transcription_pipeline": { "mode": "input_audio" },
  "models": {
    "audio_llm": {
      "default_model": "mimo-v2.5",
      "extra_models": [
        "mimo-v2-omni",
        "gpt-audio-1.5",
        "gpt-audio",
        "gpt-audio-2025-08-28",
        "gemini-3.1-pro-preview",
        "gemini-3.1-flash-lite",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "qwen3.5-omni-plus",
        "qwen3.5-omni-flash",
        "qwen3-omni-flash"
      ]
    },
    "text_llm": {
      "default_model": "mimo-v2.5"
    }
  },
  "system_asr": {
    "engine": "speech_analyzer",
    "keyword_hints_enabled": true
  },
  "sources": {
    "cn": {
      "base_url": "https://token-plan-cn.xiaomimimo.com",
      "api_key": ""
    },
    "sgp": {
      "base_url": "https://token-plan-sgp.xiaomimimo.com",
      "api_key": ""
    }
  },
  "latency": {
    "enabled": true,
    "interval_seconds": 1800
  },
  "preferences": {
    "ui_language": "zh-Hans",
    "transcription_style": "rewrite",
    "keyword_hints_enabled": false,
    "enabled_keyword_groups": [],
    "trigger_key": "fn-globe",
    "trigger": {
      "continuous_recording_double_tap_enabled": false
    },
    "min_recording_duration_ms": 500,
    "max_recording_duration_seconds": 120,
    "auto_insert": true,
    "launch_at_login": true,
    "hud": {
      "visual_style": "automatic",
      "message_duration_seconds": 3,
      "reveal_delay_ms": 100,
      "live_asr_preview_enabled": false
    }
  },
  "custom_styles": {
    "meeting_notes": {
      "display_name": "Meeting Notes",
      "prompt_lines": [
        "Turn this audio into concise meeting notes.",
        "Preserve explicitly spoken decisions, todos, times, names, project names, and technical terms.",
        "Use a short line-by-line list when there are multiple points.",
        "Do not add facts, conclusions, owners, or deadlines that the user did not say."
      ]
    }
  },
  "keyword_groups": {
    "mimo_e2e_terms": {
      "display_name": "MiMo E2E Terms",
      "keywords": [
        "OmniVoice",
        "MiMo",
        "mimo-v2.5",
        "mimo-v2-omni",
        "mimo-v2-pro",
        "mimo-v2.5-pro",
        "config.jsonc",
        "Swift",
        "API"
      ]
    },
    "omnivoice_terms": {
      "display_name": "OmniVoice Terms",
      "keywords": [
        "OmniVoice",
        "MiMo",
        "mimo-v2.5",
        "mimo-v2-omni",
        "mimo-v2-pro",
        "mimo-v2.5-pro",
        "config.jsonc",
        "ActionPanel",
        "HUD",
        "Panel"
      ]
    },
    "technical_terms": {
      "display_name": "Technical Terms",
      "keywords": [
        "Swift",
        "AppKit",
        "macOS",
        "JSONC",
        "API",
        "make run",
        "Cmd+V",
        "Fn"
      ]
    },
    "llm_model_terms": {
      "display_name": "LLM Models and Companies",
      "keywords": [
        "OpenAI",
        "ChatGPT",
        "GPT",
        "Anthropic",
        "Claude",
        "Claude Code",
        "Opus",
        "Sonnet",
        "Haiku",
        "Google",
        "Gemini",
        "Gemma",
        "Llama",
        "Mistral",
        "xAI",
        "Grok",
        "Qwen",
        "Qwen3",
        "Qwen3.5",
        "Qwen3.6",
        "Qwen Omni",
        "DeepSeek",
        "Kimi",
        "MiniMax",
        "Zhipu AI",
        "智谱",
        "GLM",
        "Hunyuan",
        "StepFun",
        "阶跃星辰",
        "SenseNova",
        "Hermes",
        "OpenClaw",
        "Hugging Face"
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

`active_source: "auto"` chooses the fastest reachable API source that exposes the currently selected model in `/v1/models`. `auto` is reserved and cannot be used as a normal source id. If the selected model exists in only one source, OmniVoice fixes the API source to that source and disables unsupported sources in the menu. In `System ASR Only`, the API Source menu switches to a system-ASR state and disables API sources because no model API is called.

`transcription_pipeline.mode` supports `input_audio`, `system_asr_text_llm`, and `system_asr_only`. Menu labels show these as `Direct Audio`, `Speech Recognition + Text Rewrite`, and `System ASR Only`. The `input_audio` pipeline selects its audio LLM through `models.audio_llm`, defaults to `mimo-v2.5`, and lets you add `mimo-v2-omni`, GPT Audio, Gemini, Qwen Omni, or other candidates. `system_asr_text_llm` marks the system ASR draft as unreliable, then asks the text model stored in `models.text_llm.default_model` to correct, rewrite, and apply style. `system_asr_only` uses only the current `system_asr.engine` final ASR text and does not use models, style rewriting, or LLM prompts. The Text LLM menu shows the union of models observed from reachable API sources via `/v1/models`, while hiding obvious TTS, voiceclone, and voicedesign models. If an observed model still does not support text completion, OmniVoice shows an ActionPanel hint to choose another text model instead of silently inserting the ASR draft.

`system_asr.engine` supports `classic_speech`, `speech_analyzer`, and `apple_online_speech`. The default `speech_analyzer` engine is the macOS 26+ on-device SpeechAnalyzer adapter; `classic_speech` is on-device classic Speech; `apple_online_speech` is an explicit Apple online recognition choice. After sleep, wake, lock, or unlock, OmniVoice cancels residual live ASR sessions, briefly prefers classic Speech, and probes SpeechAnalyzer again so live preview can recover without restarting the app. macOS can use Apple online recognition for free, but audio may be sent to Apple and usage can be limited by Apple service availability, daily limits, and roughly one-minute task limits.

Use `custom_styles` to add your own transcription prompts. Each style needs a safe ID, a display name, and either `prompt` or `prompt_lines`. Custom styles are marked as `Custom` in the Style menu and in the result panel style switcher.

Use `keyword_groups` to add multiple keyword groups, then select groups in the `Keyword Hints` menu to inject them. Keyword hints are off by default with no preselected groups; selecting any group turns hints on, and clearing the final group turns them off again. The default template includes `llm_model_terms` for common LLM companies, model families, and model names, such as OpenAI/GPT, Anthropic/Claude/Claude Code, Google/Gemini, Qwen, DeepSeek, Kimi, Llama, Mistral, Grok, GLM, Hunyuan, SenseNova, Hermes, OpenClaw, and Hugging Face. Keywords are recognition hints only: the model should prefer them when the audio and context fit, but should not force a listed word into the result. Each group uses at most 200 keywords, and at most 500 keywords are injected in total. `custom_styles` and `keyword_groups` only need an optional `display_name`; if it is missing, menus show the ID. `*_zh` and `description` fields are no longer written or parsed.

OmniVoice watches `config.jsonc` for saves and updates. Valid changes hot-reload automatically and show a brief HUD confirmation. If a hot reload finds invalid JSON or missing required fields, OmniVoice keeps using the last valid in-memory config, exports the current running config as `config.current-YYYYMMDD-HHMMSS.jsonc`, and asks you to check the original file.

### Permissions

OmniVoice checks permissions at launch and each time the menu opens:

- Microphone records speech with `AVAudioEngine`.
- Accessibility checks whether the current text field can receive text, then inserts when possible.
- Input Monitoring lets OmniVoice notice when you press and release the trigger key.
- Speech Recognition lets macOS Speech create the final draft used by `Speech Recognition + Text Rewrite` and `System ASR Only`, and it also supports Direct Audio's local reliable-speech check before a model request is sent.

If you already enabled the permission for the current app but OmniVoice still cannot obtain it, do not just toggle the permission repeatedly. Remove OmniVoice from the matching Privacy & Security permission page, click `+` to add `/Applications/OmniVoice.app` again, then enable the permission again. macOS privacy permissions are path-sensitive, so using the installed app path matters.

On newer macOS versions, Accessibility and Input Monitoring may not show a traditional Allow/Deny popup. `Request Accessibility Permission`, `Request Input Monitoring Permission`, and `Request All Permissions` first ask macOS to register OmniVoice in the matching permission list. The small "open System Settings" permission guidance dialog that macOS shows can appear in another desktop/full-screen Space; if it is not on the current desktop, check Mission Control, other Spaces, or Cmd+Tab. OmniVoice also best-effort opens the matching System Settings page, but it cannot force that system dialog into the current Space.

During development, repeatedly replacing `/Applications/OmniVoice.app` with an ad-hoc-signed build can prevent macOS TCC from auto-registering the current app in the Accessibility list. Prefer a stable signing identity, such as the local self-signed `OmniVoice Local Development`, and reset the old Accessibility record before retrying:

```sh
cd OmniVoice
tccutil reset Accessibility dev.local.omnivoice
make run SIGN_IDENTITY="OmniVoice Local Development"
```

If `security find-identity -p codesigning` shows the identity but Gatekeeper still reports `spctl ... rejected`, the local self-signed certificate has not been fully trusted in Keychain Access. That can still be useful for local TCC testing; trust the certificate in Keychain Access if a fully trusted local identity is needed.

When running from source repeatedly with `make run`, the install step first quits the old `/Applications/OmniVoice.app` instance before replacing and reopening the bundle, so an older process cannot keep holding input-monitoring permissions.

### Menu Layout

All settings live in the menu bar. There is no Dock icon, Settings window, popover, sheet, or input-source registration.

The menu is grouped as control, configuration, transcription, experience/system, and final app actions. It includes `Stop` or `Re-enable`, status, permissions, redacted Base URL/API Key, `Transcription: Direct Audio · <model>`, `Transcription: Speech Recognition + Text Rewrite · <model>`, or `Transcription: System ASR Only · <engine>`, `Configuration`, `Language`, `Transcription Style`, `Keyword Hints`, `Trigger Key`, `Recording Duration`, `Launch at Login`, `Auto Insert`, `Display & Hints`, `Permission Management`, `Restart`, and `Quit`. The top-level read-only `Source: ...` row is gone; API sources are changed only inside the Configuration submenu.

`Display & Hints` contains `Live ASR Preview`, `HUD Style`, `Message Duration`, and `HUD Reveal Delay`. Live ASR Preview defaults off; when enabled, OmniVoice shows live system-ASR text while recording. Direct Audio and Speech Recognition + Text Rewrite show a self-drawn vertically centered `Draft` badge plus the most recent preview tail; System ASR Only shows a `Live` badge because that text is the recognition stream the active mode will use directly. Even when HUD preview is off, Direct Audio records live system-ASR evidence in parallel so release can locally decide whether reliable speech was heard; if system ASR ran normally but produced no text and RMS is not strong, OmniVoice asks you to retry without calling the model API. The HUD display layer collapses line breaks and repeated whitespace from ASR partials so the single-line preview does not show large blank gaps. Long text does not use an ellipsis, and instead uses an approximately 100px left fade to show that earlier text has been clipped; within one recording, the HUD grows with the preview and does not suddenly shrink when system ASR revises a shorter partial. `Speech Recognition + Text Rewrite` and `System ASR Only` keep the minimum-duration check but do not skip an available ASR final just because local RMS is low; after release, System ASR Only shows `Finishing recognition` without the model transcription progress bar. After sleep, wake, lock, or unlock, OmniVoice cancels residual live ASR sessions, briefly prefers classic Speech, and probes SpeechAnalyzer again so live preview can recover without restarting the app. HUD Reveal Delay defaults to 100ms and offers 100ms, 200ms, 300ms, 400ms, and 500ms; recording still starts immediately when the trigger is pressed.

Model selection, transcription mode, System ASR settings, Reload Config, Refresh Models, API Source, latency settings, config opening, and the combined Check Connection & Latency action live inside the Configuration submenu. The `Model` submenu shows mode choices first, then only the model list for the active mode: text-model settings are hidden in Direct Audio mode, input-audio settings are hidden in Speech Recognition + Text Rewrite mode, and System ASR Only shows a read-only `This mode does not use an LLM` item. The `API Source` submenu has a separated bottom `Use System ASR Only` check item; enabling it disables API source choices, and clicking it again returns to Direct Audio. A separated bottom `Edit Model List` action reuses the config-file opener and tries to jump to `models.audio_llm`, so you can edit Audio LLM candidates and `models.text_llm.default_model` directly. The `Language` menu controls UI language; transcription output defaults to simplified Chinese and switches to English when the audio is mainly English.

Direct Audio mode defaults to `mimo-v2.5`, with `mimo-v2-omni` and third-party Audio LLM candidates seeded under `models.audio_llm.extra_models`. The Audio LLM menu shows only `configured model pool ∩ models observed from all API sources via /v1/models`; the Text LLM menu shows the observed model union from reachable sources and excludes obvious TTS/voiceclone/voicedesign models. When nothing has been observed, the menu shows a refresh prompt instead of the seeded long list. `Refresh Models` refreshes every configured source, and the API Source menu disables sources that do not expose the current model.

### Runtime Notes

- The `Recording Duration` menu shows the current min-max range, for example `Duration: 500ms-60s`. Minimum choices are 300ms, 500ms, 800ms, 1s, 2s, and 3s; maximum choices are 15s, 30s, 60s, 120s, and 300s.
- When `Double-tap Continuous Recording` is enabled, the first quick tap waits for a second tap; without one, OmniVoice finishes it as a normal short recording. After continuous recording starts, the next trigger tap stops it, and the actual stop work begins after that tap is released so long WAV export cannot block trigger-release acknowledgement. The maximum recording duration remains a safety limit.
- WAV upload format is 16 kHz mono little-endian Int16 PCM in a WAV container.
- Auto insertion uses conservative Accessibility insertion for standard native text fields, then falls back to clipboard preservation plus Cmd+V.
- Secure text fields, passwords, verification codes, token/API-key-like fields, missing focus, missing permissions, paste failures, and disabled Auto Insert all use the topmost ActionPanel.
- If transcription fails after a valid local recording, OmniVoice keeps the WAV in memory and offers Retry/Cancel without requiring you to speak again.
- During model-backed transcription, the thin progress bar follows the OpenAI-compatible streaming request phase: preparation and connection start with lower caps, HTTP response and first-delta waiting advance the bar, the first streamed text chunk switches to a steadier streaming color, and 100% appears only after completion.
- `HUD Style` supports Automatic, Dark Capsule, and Light Capsule on macOS 14/15. Automatic follows the system appearance: light mode uses the light capsule, and dark mode uses the dark capsule. Liquid Glass appears only on macOS 26+ when the native glass view is available; HUD and ActionPanel share native glass, rounded external depth, and an outer text halo so bright backgrounds do not thin the glyph body.
- `Message Duration` controls how long short status or warning messages remain visible.
- `HUD Reveal Delay` only controls when the HUD appears, not when recording starts; trigger-key combinations cancel silently before the HUD appears.
- Recording waveform uses live RMS: quiet rooms get slower low-amplitude motion, while speech attacks and recent syllables quickly affect speed and amplitude.
- Redacted runtime diagnostics are appended to `~/Library/Logs/OmniVoice/diagnostics.log`. The menu does not expose full diagnostics.

### Developer Guide

#### Project Structure

Only Git-tracked project surfaces are listed here. Generated paths such as `.build/`, installed app bundles, local config files, diagnostics logs, and harness test artifacts are intentionally excluded.

| Path | Purpose |
| --- | --- |
| `Package.swift` | Swift Package Manager manifest for release `OmniVoiceApp`, E2E `OmniVoiceE2EApp`, `OmniVoiceCore`, `OmniVoiceE2ESupport`, and test targets. |
| `Makefile` | Build, install, run, cleanup, config-template, test, and `check` command surface. |
| `Sources/OmniVoiceApp/` | Minimal release executable entrypoint without the E2E injection command. |
| `Sources/OmniVoiceE2EApp/` | E2E-only executable entrypoint for GUI and real-model validation; it links the hidden E2E command. |
| `Sources/OmniVoiceCore/` | Production app runtime organized by domain directories: App, Configuration, Menu, Permissions, Trigger, Recording, ASR, API, Injection, UI, Models, Diagnostics, and Shared. |
| `Sources/OmniVoiceE2ESupport/` | Developer-only E2E helpers such as WAV replay, injection commands, and GUI artifact rendering. |
| `Tests/OmniVoiceCoreTests/` | Core unit tests mirrored by domain directories, covering configuration, permissions, trigger keys, recording/WAV, System ASR, API client behavior, injection, HUD/ActionPanel, diagnostics, and resources. |
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
make check
```

`make build` ad-hoc signs `.build/OmniVoice.app` by default and installs the release-shaped binary without the E2E injection entrypoint. `make install` first quits the running installed OmniVoice, then copies the signed bundle to `/Applications/OmniVoice.app`; `make run` installs first and opens that installed bundle. Use `make dev-run` only when you deliberately want to launch from the build directory. The GUI E2E harness needs the same bundle with the hidden E2E command, so install it with `make run ENABLE_E2E=1`; because Direct Audio can start live ASR evidence collection, any GUI E2E that may touch Speech Recognition or another privacy usage description should use `--launch-services` to run through the full `.app` bundle. Run normal `make run` again after validation to restore the release-shaped install. `make check` runs `git diff --check`, `swift test`, and `make build`.

For Accessibility, Input Monitoring, or repeated reinstall validation, prefer a stable signing identity instead of default ad-hoc signing. The current local validation identity is `OmniVoice Local Development`:

```sh
security find-identity -p codesigning
make run SIGN_IDENTITY="OmniVoice Local Development"
```

If OmniVoice does not appear in the Accessibility list, reset the current bundle id's Accessibility record before installing again with the same signing identity:

```sh
tccutil reset Accessibility dev.local.omnivoice
make run SIGN_IDENTITY="OmniVoice Local Development"
```

Override signing with:

```sh
make build SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

The default `SIGN_IDENTITY=-` is ad-hoc signing, suitable only for local development and quick TCC validation. A local self-signed identity such as `OmniVoice Local Development` is also only for stable local testing. Do not ship the `dev.local.omnivoice` ad-hoc/self-signed build as a public release. For distribution to other users, use a stable production bundle id, an Apple-issued `Developer ID Application` certificate, hardened runtime, notarization, stapling, and then package the zip/dmg.

The app is designed for direct distribution and notarization, not Mac App Store sandboxing, because it needs microphone, Accessibility, Input Monitoring, and Speech Recognition permissions.
