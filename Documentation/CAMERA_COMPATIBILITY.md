# Panasonic DC-G9 第一代兼容性

核查日期：2026-11-10。本文件只讨论第一代 DC-G9，`G9M2`、`G9 II` 被设备身份测试明确排除。

## 官方资料与平台事实

[Panasonic LUMIX Tether 下载与环境要求](https://av.jpn.support.panasonic.com/support/global/cs/soft/download/d_lumixtether.html)列出 DC-G9、Apple Silicon 和 macOS 15 系列；当前页面版本为 2.12，2025-11-26 更新。此 Mac 为 macOS 15.6.1，属于相同系统系列，但仍需实机验证。

[机型支持表](https://av.jpn.support.panasonic.com/support/software/lumixtether/download/d_lumixtether2.html)为第一代 G9 标注 USB 接口。[第一代 G9 官方完整手册](https://eww.pavc.panasonic.co.jp/dscoi/DC-G9/JP/DC-G9_DVQP1401ZE_full_jpn.pdf)说明 PC(Tether) 连接时 Wi-Fi/Bluetooth 不可用。Mac ↔ iPad 的普通局域网连接不受相机 USB 模式限制。

[Panasonic 公开 LUMIX SDK](https://av.jpn.support.panasonic.com/support/software/tool/sdk.html)仍列 Windows 10 64-bit / Visual Studio 的运行环境。本工程不加载其 DLL，不声称该 SDK 在 macOS 可用。未发现可据以交付并验证第一代 G9 直接 Wi-Fi 控制的官方 macOS/iPadOS 接口，因此该功能不开放。没有扫描相机私有端点，也没有逆向或自动点击 Tether。

## 两条真实接入路径

可靠路径是官方 Tether 负责实时取景和快门，LumaStudio 负责其保存目录的稳定导入。系统事件与定时扫描在相机断开时继续运行，目录重建也会重新建立监听。文件到达可生成缩略图、进入自动美颜及可选 iPad 传输流程。

原生实验使用 ImageCaptureCore 枚举、过滤第一代 G9、打开会话、读取 mediaFiles 和设备 capability、下载新文件。只有相机报告标准拍照能力且 tetheredCaptureEnabled 为真才开放“验证原生快门”。成功收到新照片并下载以后，当前连接才开放正式原生快门；断开即失效。ISO、快门速度、光圈、实时取景均未开放。

本机 macOS 15.5 SDK 的 ICCameraDevice.h 明确将 requestEnableTethering 标为 macOS 14 起弃用、调用无效；支持标准命令的设备默认具备该能力。实现据实际设备状态判断，没有用一个无效调用冒充启用。参见 [Apple ImageCaptureCore](https://developer.apple.com/documentation/imagecapturecore) 和 [requestTakePicture](https://developer.apple.com/documentation/imagecapturecore/iccameradevice/requesttakepicture())。

## 实际结果

- USB 系统清单：未检测到 Panasonic / DC-G9。
- 官方 LUMIX Tether：当前未安装。官方下载安装流程要求合法相机序列号，当前没有该信息，未绕过。
- 稳定目录监听：延迟写入、重复事件、目录删除/重建自动恢复的本地集成测试通过。
- RAW：raw.pixls.us #3219 第一代 G9 RW2 样片成功解码、调整和 5184 × 3888 导出。详情见 VALIDATION.md。
- G9 USB 识别、实际外部拍摄、真实拔插恢复：没有硬件，尚未执行。
- 原生快门、相机文件下载：实现已编译，但没有实机成功证据。

## 实机验收步骤

1. 依照官方页面，使用相机序列号安装 Tether；关闭其它占用 USB 的摄影应用。
2. 数据 USB 线直连 Mac，G9 选择 PC(Tether)。在 Tether 中确认第一代 DC-G9 身份和实时取景。
3. 保存目录设 `~/Pictures/LumaStudio/Inbox`；先拍 JPEG，再 RAW+JPEG，检查图库、配对与缩略图、非覆盖导出。
4. 拍摄中断开/重新插入 USB；确认 Tether 恢复，监听不丢失，并拍第二张。
5. 关闭 Tether，单独启用 LumaStudio 原生发现实验，记录 capability 与 tetheredCaptureEnabled；仅在“验证原生快门”可用时测试。
6. 真实拍摄照片的生成、下载和导入全部完成，才能在验收记录中将原生快门标记已验证。
