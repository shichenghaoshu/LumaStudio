# 验收记录

## 当前 Mac 0.3.0 · 2026-11-12

- Release 编译成功，系统临时签名深度校验通过。当前可执行文件 SHA256：`783dcdc47ec83177b43c03e9eb65f05d91b9357e0c2138859a128f57ab15fff4`。
- 60 项 Swift 检查，0 失败，含真实 G9 RAW、人像、本机 Qwen；MCP stdio 转接器 3 项检查通过。日志为 `Artifacts/integrations-tests.log`、`integrations-stdio-tests.log`。
- MetalPetal 实际 GPU 执行：真实人像 29,648 个皮肤采样像素改变，蒙版外最大像素差为 0；曝光 +0.35／7200K／美颜叠加回归的新绿色皮肤像素为 0。这是执行与保护检查，不是普遍审美得分。
- 原生界面完成在线协议测试、WebSocket MCP 初始化／工具发现／状态／提交文字、语音待处理进入 Agent、真实 GPU 渲染、比较和导出。全尺寸 JPEG 为 2615×3269，两个原片 SHA256 不变。测试连接与密钥已移除，恢复本地模式和原有配方。
- 本机接口实测只监听 127.0.0.1，未带令牌返回 401；正向认证、连续请求、输入约束在真实 Network.framework loopback 测试中通过。
- 在线 API／小智使用明确标记的本机 HTTP／WebSocket 服务，不是付费模型或官方小智账号实连。真人语音、外部 ASR/TTS、小智设备、专业精修质量及训练仍未验收。

完整接法见 [INTEGRATIONS.md](INTEGRATIONS.md)，当前验收数据见本机 `Artifacts/integrations-acceptance.json`；GitHub CI 与本机结果单独记录，不互相替代。

以下保留原 0.1 基础能力历史记录。iPad 后续开发和验收暂缓。

日期：2026-11-10；地点：当前本机工作区。原始日志保存在 `Artifacts`，以下区分编译、模拟器、测试与硬件。

## 构建

- P0 Mac Debug：`Artifacts/P0-mac-build.log`，BUILD SUCCEEDED；进程已启动。
- P0 iPad Debug：`Artifacts/P0-pad-build.log`，BUILD SUCCEEDED；M4 iPad Pro 11-inch / iOS 18.6 模拟器已安装启动。
- 完整 Mac Release：`Artifacts/release-mac-build.log`。
- 完整 iPad Simulator Release：`Artifacts/release-pad-simulator-build.log`。
- 完整 iPad Device Release（无签名）：`Artifacts/release-pad-device-build.log`。

最终打包程序检查三个 Release 日志含 BUILD SUCCEEDED 后才复制应用，交付文件及 SHA256 列在 Deliverables/MANIFEST.txt。设备无签名产物不能直接安装到实体 iPad。

## 测试

设置两个真实 fixture 环境变量执行 `swift test`；`Artifacts/all-tests.log` 记录 **29 tests, 0 failures**，包含 RAW/人像样片测试，没有以跳过代替通过。

覆盖：第一代 G9 排除 G9 II、稳定等待、真实目录变更/恢复；guided filter 常量与边缘、无脸遮罩、模型失败回退、真实人像；Lab 往返、六个 LUT、非法 LUT、不同参考分布、肤色保护、最小 Recipe 默认值；库内容去重、同名不同内容、RAW/JPEG 配对、配方持久化；RAW 三层和全尺寸导出、方向与三种输出格式、原片/符号链接保护；队列失败重试、去重、暂停/恢复/取消；Bonjour、TLS 分块完整性、错误密钥、非法帧与路径。

恢复测试使用已写出的真实队列日志重新创建处理器，没有模拟出一个“恢复成功”按钮；强杀应用后的端到端恢复仍待独立测试。

## 第一代 G9 样片

来源：[raw.pixls.us](https://raw.pixls.us/)，repository ID **3219**，Panasonic / DC-G9 / 4:3，来源标记 CC0。下载地址在 `Scripts/fetch_fixtures.sh`。

- 输入：`work/fixtures/G9-3219.RW2`，约 23.15 MB。
- SHA256：`cfb015a89d7af92306328868e6d87ac7974c427612608016821dfb336e8e3faa`，与来源公布值一致。
- ImageIO TIFF 元数据：Make Panasonic、Model DC-G9。
- CIRAWFilter nativeSize：5184 × 3888。
- Thumbnail 最大边 360；Preview 1600 × 1200。
- Full-resolution JPEG：5184 × 3888，原片哈希未改变。
- 曝光、5200 K 色温、阴影分别真实渲染为 PNG；未假定所有 RAW 或所有 iPad 系统均支持。
- 完整结果：`Artifacts/RAW-Final/report.json` 和同目录图像。

## 人像

使用 [NASA S99-00858](https://www.nasa.gov/image-detail/amf-s99-00858/) 的 2615 × 3269 公共人像做开发 QA。Vision 检出 1 张人脸，传统遮罩不覆盖整张图片。已输出原图、美颜图、全尺寸图和参考 LUT，并在 Mac 工作台实际显示该人像、切换滤镜，确认按钮连接真实处理。

这不是多肤色验证集，也不能证明商业级人像精修质量。美颜算法对瑕疵的处理保守，默认未使用训练好的语义分割模型。

## 局域网

同一 Mac 上运行两个真实 LocalSyncService：Bonjour 发现 Host，随后在 loopback 上完成 TLS-PSK 和大于四块的数据传输，接收哈希相同。另测错误配对密钥不能进入 connected。测试没有使用互联网中转。

最初仅启用 TLS 1.3 的外部 PSK 配置在本机产生 NWError -9810。改为 Network.framework 当前 SDK 上实测可用的 TLS 1.2 + TLS_PSK_WITH_AES_128_GCM_SHA256，集成测试通过；没有关闭加密或跳过认证。两台物理设备间的权限、网络和连接仍未验收。

## 硬件与发布边界

USB inventory 没有 Panasonic / DC-G9，LUMIX Tether 未安装；官方安装流程要求相机序列号。没有 G9 原生快门、官方 Tether 拍摄或真实拔插成功记录。

M4 iPad 是模拟器配置，不是实体设备；没有 M1 或实体 M 系列 iPad 的性能数据。Mac 应用是本机 ad-hoc 签名，不是 Developer ID 公证版。没有发布外部服务或上传照片。

## Mac Edge AI 0.2 新增验收

最终共享检查：45 项，0 失败，日志 `Artifacts/edge-tests-acceptance.log`。训练检查：6 项通过；SFT 入口仅用微型随机模型完成 2 次 MPS 更新，正式 Student 权重数为 0。真实 CC0 RAW 的 3 组数据流程完成，但只有 1 张原始场景，不能作为高质量训练集。

原生 Qwen 1.5B + 约束检查的禁网进程测试成功，未使用规则降级。当前这次完整原生运行约 33.21 秒，参数生成约 30.09 秒；1 轮渲染，指标检查通过，原图哈希未变。采样 RSS 峰值约 1258.47 MiB。测试时同机曾有构建负载，应作为开发机观测，不是严格空闲基准。GPU 和 ANE 利用率均未测量。证据 `Artifacts/EdgeOfflineFinal/measurement.json`。

这一结果验证本机原生闭环与进程禁网运行；不构成 Jarvis 对比、专业审美评分、32GB Mac 或实体 iPad 验收。
<!-- Mac 0.2 final UI acceptance: 2026-11-10 -->

Mac 0.2 最终界面验收：基础中文指令生成实际预览（参数生成 8.461 秒），撤销／重做恢复参数，模型面板确认基础模型身份，确认导出真实 2615 × 3269 JPEG。截图见 `Artifacts/mac-edge-editor.png`、`mac-edge-models.png`、`mac-edge-export.png`。这不替代广泛人像质量盲评、正式 Student 训练或 Jarvis 对照。

