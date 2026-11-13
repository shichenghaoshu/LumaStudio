# 在线模型、美颜与语音接入 · Mac 0.4.2

2026-11-12。入口：左侧「接入」，或助手中的「模型与语音接入」。设置集中在原生页面，编辑、对照与确认导出继续使用原工作台。默认方案来源是本地模型／规则；在线服务和语音连接需要使用者自己的账号与凭据。

## 在线模型 API

1. 打开「接入 → 在线模型」，选择服务商。
2. 确认 **API Base URL**、**模型 ID** 与 **API 格式**，填写自己的密钥并点「保存密钥」。密钥存入此 Mac 的系统钥匙串，输入框随即清空；没有写入工程、配方或 GitHub。
3. 点「测试在线连接」。测试只发送简短文字，验证认证与 JSON 响应，不上传照片。
4. 将方案来源切换为「在线模型 API」，回到助手或处理过程页输入要求，点击开始处理。返回方案经过 EditRecipe、参数范围、工具和指令约束检查后才会渲染。

| 服务 | 预设 Base URL | API 格式 | 模型选择 |
|---|---|---|---|
| 阿里云百炼／通义 | `https://dashscope.aliyuncs.com/compatible-mode/v1` | Chat Completions | 默认 `qwen-plus`，按开通区域与控制台调整 |
| DeepSeek | `https://api.deepseek.com` | Chat Completions | 默认 `deepseek-flash`，以账号支持的模型为准 |
| OpenAI | `https://api.openai.com/v1` | Responses | 手动填写账号可用且支持 JSON 输出的模型 ID |
| 自定义兼容服务 | 自行填写 | 可选以上两种 | 需要支持 JSON object 格式的模型 |

地址填写到版本前缀，代码会追加 `/chat/completions` 或 `/responses`。不要填写完整请求路径。远程只接受 HTTPS；本机开发服务可使用 `http://127.0.0.1:端口/v1`。不接受 URL 内嵌账号密码或 HTTP 查询参数，重定向不会转发密钥。

默认仅发送修图文字、图像分析指标和当前配方。若主动开启「附带不超过 512 像素的照片预览」，会额外上传移除原片 EXIF/GPS 的小 JPEG（上限 512 KiB），需选择支持图片输入的模型。云服务可能计费，其隐私与数据规则由所选服务商决定。原片、实际 GPU 渲染和导出在 Mac 本地完成。

「在线请求失败时，使用本地模型继续」默认开启，处理记录会显示降级原因；取消操作不会被转换为本地继续。关闭后，网络／模型错误直接报告失败。连接成功只证明端点响应，不保证该模型能稳定生成合适的修图方案。

扩展位置：`Packages/CloudModel`。`ModelHTTPTransport` 可替换传输；`OnlineAgentPlanner` 实现与本地规划器相同的协议，Responses 请求设置 `store: false`。当前没有流式文字展示、代理服务器或云端图像生成。

官方接入参考：[百炼兼容接口](https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope)、[DeepSeek API](https://api-docs.deepseek.com/)、[OpenAI JSON 输出](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=chat)。模型 ID 与价格会变化，请以自己的服务控制台为准。

## 真实美颜

已将 [MetalPetal 1.25.2](https://github.com/MetalPetal/MetalPetal) 的 `MTIHighPassSkinSmoothingFilter` 接入实际 GPU 管线，结合本平台的人脸／皮肤蒙版、纹理恢复、温和肤色处理与细小红／暗瑕疵弱化。人像面板可开启并调整强度、肤色、瑕疵与纹理保留；处理过程显示实际后端。

这是实际改变照片像素的算法。皮肤蒙版默认由 Apple Vision、人脸关键点与传统色彩判断生成；未捆绑训练好的专业分割／商业精修网络。没有液化、五官重塑、痘痘与痣的语义区分或生成式消除。MetalPetal 不可用或运行失败时明确显示传统频率分离回退。

高亮输入先限制到上游 SDR LUT 可处理的范围，再恢复超出 SDR 的能量，避免曝光／暖调叠加导致的绿色斑点。Core Image 与 MetalPetal 的半浮点色彩交接保留 sRGB 标记，跨 GPU 队列等待写入完成。原片不被覆盖，效果仍需要看图确认。

## Mac 麦克风输入

助手和处理过程页提供麦克风按钮。首次点击时请求麦克风及 Speech 权限，中文识别文本实时填入要求；点击停止后可以修改文字，再开始修图。单次输入最长 45 秒。默认要求设备端识别，不支持时会说明；在「语音与小智」可自行允许 Apple 在线听写。实际离线语言支持由系统决定。

实现使用 `Speech` 与 `AVAudioEngine`，不依赖外部 Python。当前交付已编译并检查入口，但没有取得真人朗读、不同麦克风或在线听写的识别质量验收。

## 小智 MCP 接入

1. 在你自己的小智控制台取得 **MCP 接入点**（通常为包含令牌的 `wss://…` 地址）。
2. 打开「接入 → 语音与小智」，粘贴并「保存接入点」，再点「连接小智」。完整地址只保存于系统钥匙串。
3. 连接后暴露两个工具：`lumastudio.get_status` 查询照片名称、任务和待处理数量；`lumastudio.set_instruction` 提交最终修图文字。
4. 默认进入「语音待处理」，可「填入要求」或「开始处理」。只有主动开启「收到最终语音要求后，自动处理当前照片」，空闲且已选照片时才直接运行 Agent；忙碌时继续排队。

队列最多 8 条待处理，UUID 最近记录最多 128 条用于重试去重。接口只接受受限文字；不暴露任意脚本、文件路径或自动导出工具。状态可含照片文件名；照片内容不会经语音接口发送。

此连接是小智的 **MCP 工具接入**。语音识别、对话、麦克风音频、Opus 与播报由小智设备／服务负责，本应用不模拟 ESP32 的音频上行服务。未复制小智固件、模型或不明许可代码。参考其[公开设备协议](https://github.com/78/xiaozhi-esp32/blob/main/docs/websocket.md)及 [MCP 接入示例](https://github.com/78/mcp-calculator/blob/main/mcp_pipe.py)。

## 其他语音 AI：本机 HTTP

在同一设置页点「启动本机接口」，系统选择空闲端口并生成本次会话令牌。「复制接入配置」会把端口与令牌写入剪贴板，供同一台 Mac 的语音程序使用。停止后旧配置失效，重启时重新复制。

仅监听 `127.0.0.1`，每个请求必须有 `Authorization: Bearer …`。不支持浏览器跨域调用，不向局域网公开端口；小智远端使用前述 WSS MCP 通道。

```sh
# 从应用复制的配置中取得这两个值；不要把真实令牌提交到仓库。
export LUMA_VOICE_BASE_URL='http://127.0.0.1:应用显示的端口'
export LUMA_VOICE_TOKEN='应用复制的本次会话令牌'

curl --fail-with-body "$LUMA_VOICE_BASE_URL/v1/status" \
  -H "Authorization: Bearer $LUMA_VOICE_TOKEN"

curl --fail-with-body "$LUMA_VOICE_BASE_URL/v1/voice/commands" \
  -H "Authorization: Bearer $LUMA_VOICE_TOKEN" \
  -H 'Content-Type: application/json' \
  --data '{"text":"自然提亮，保留皮肤纹理","source":"my-voice-ai","final":true,"id":"9e17ea27-4792-408c-9c84-33cced907b39"}'
```

`text` 为 1–1000 字；`source` 最多 80 字；`final: false` 不进入处理队列。`id` 为可选 UUID，相同 ID 不重复执行。每条新要求请生成新 UUID。HTTP body 上限 8 KiB。无效或缺少令牌返回 401；重复／非最终文本不会被当作新任务；队列满时调用方需稍后重试。

`Tools/VoiceMCP/luma_voice_mcp.py` 提供标准 MCP stdio 转接器，只用 Python 标准库。在支持 MCP 的本机客户端中配置 `command: python3`、`args: [仓库绝对路径/Tools/VoiceMCP/luma_voice_mcp.py]`，并在该进程环境中设置上述两个变量。该脚本不是 Mac App 的启动依赖。不要把当前令牌写入共享配置。

## 开源组件与源码发布

- MetalPetal **1.25.2**，MIT：实际高通皮肤平滑。
- apple/swift-collections **1.1.4**，Apache-2.0 + Runtime Library Exception：`Deque` 用于语音有界去重记录。
- llama.cpp **b12110**，MIT：现有进程内本地 Qwen 推理。GitHub 只打包本次 Mac 使用的未修改 macOS 通用框架；原包与 SHA 记录见 `Vendor/runtime-provenance.json`。

依赖版本在 `Package.resolved` 固定，许可保留于 `Vendor/Notices`、`Vendor/llama-LICENSE.txt` 和 App 的 `ThirdPartyNotices.txt`。没有导入 Jarvis 限制商用的权重／代码，也没有上传用户的像素蛋糕逆向目录、商业计划书、照片、密钥或 GGUF。

GitHub 源码仓库为 `shichenghaoshu/LumaStudio`（本轮核对为公开仓库）；实际上传与提交号见本机交付的验收记录。只上传白名单源码、许可、运行框架和 CI。仓库不含已安装的 Qwen 权重，克隆后无模型时仍可使用规则规划，或配置自己的在线模型。

## 验证边界

当前共享测试包含两种在线 API 请求格式、认证失败/取消、严格配方、预览隐私、语音 MCP 发现/工具调用、去重与真实 loopback HTTP；stdio 适配器另有 3 项协议检查。真实 DeepSeek 验证见下方。小智官方平台、真人语音硬件与听写主观质量未验收，不能以本机协议测试替代。美颜的真实 GPU 算子和蒙版已验证，尚未完成广泛人像的主观质量评审。

## 0.4 真实服务与批量更新

2026-11-12：用户授权的 DeepSeek 真实密钥已通过本机 SecureField 保存到系统钥匙串。真实连接、JSON 返回、单张人像调整、8 张独立 RAW 逐张分析／规划／渲染／检查／导出均通过；8 张全部来自 `DeepSeek / deepseek-flash`，无本地回退。报告明确记录原片哈希、各张配方、逐轮指标和实际来源，不能用指标代替审美验收。API 账单不在应用内读取，因此不声明具体消费金额。

新版系统钥匙串读取不会等待授权对话框而卡住主界面。临时签名版本更新可能失去已有条目的系统访问授权；“本次会话使用”允许将主动填写的密钥仅保留在内存，退出后清除。保存到钥匙串失败时会显示具体状态，并保留本次会话的可用密钥。没有复制到配置文件或将其写入日志。系统授权仍由用户在 macOS 中管理。

批量页增加“逐张 AI 调整”：共用当前模板与参考档案，逐张分析，并保留每张原有锁定值及模板锁；每项的最终 Recipe、来源、回退原因与处理记录目录在导出前持久化。失败重试或恢复会复用已有方案，避免重复请求模型。可载入本张方案进入编辑器，正常撤销，原件保持不变。重启后恢复未完成 AI 队列时，新的待规划项使用当前接入设置，已经生成的方案保持不变。

本次在线规划只发送图像分析指标和指令；512px 预览上传保持关闭。小智官方平台、真实语音硬件、广泛人像审美质量尚未验收。

0.4.2 使用 DeepSeek 官方非思考模式生成有界 JSON 参数补丁，避免默认思考过程耗尽输出预算。其他供应商请求不增加 DeepSeek 专属字段。一次早期四图 UI 批次中有一张因在线 JSON 未完整返回而明确回退本地，该历史失败不计作全在线成功。具体来源始终显示在每项任务中。官方接口参数见 [DeepSeek 文档](https://api-docs.deepseek.com/api/create-chat-completion/)。
