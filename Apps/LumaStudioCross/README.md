# LumaStudio 0.5.0 · Android / Windows

这是可离线使用的照片编辑器。Windows 10/11 x64 解压完整文件夹后运行 `lumastudio.exe`；Android 7.0+ 安装 Release APK。Mac 专业版位于仓库的原生 Swift 工程，仍使用自己的完整图像管线。

## 使用

1. 点“导入照片”选择一张或多张照片，也可以先用内置的 CC0 山水示例体验。原件复制到应用本地图库，重复内容不会再次导入。
2. 影调、色彩、HSL、滤镜、细节、肤色、裁切都对真实像素生效。支持 18 个基础数值、8 色 HSL 的 24 个数值、30 款原创 CUBE 滤镜、90° 旋转、水平翻转与中心裁切。滑块拖动合为一次撤销，照片各自保存配方。
3. 勾选缩略图，进入批量处理。可用当前配方、每张已存配方或基于本地亮度统计的逐张自动影调校正。任务逐张执行，输出失败清单，停止在当前照片处理完后生效。Android 可把结果打成 ZIP，交给系统分享或保存。
4. 导出设置支持 JPEG 质量、PNG、原始尺寸/指定长边。始终从原始像素重新处理；输出为 **8 位 sRGB**，移除 EXIF/GPS。Windows 拒绝覆盖已有文件；Android 使用系统文件提供程序创建输出。
5. AI 助手在接入设置中填写 DeepSeek 或其他 Chat Completions 兼容 HTTPS 地址、模型和密钥。仅发送文字与参数，不上传照片。密钥只在本次会话内存中。在线建议先检查范围并完成本地渲染，再写入历史；失败保留当前编辑。

## 能力边界

- 支持 JPEG、PNG、TIFF、WebP、BMP、GIF 首帧、PSD 合成图及 LibRaw 0.22.3 支持的相机 RAW。不同机型/压缩方式须逐文件验证；不承诺所有历史与未来文件。HEIC 暂请使用 Mac。
- RAW 使用相机白平衡、sRGB 8 位输出。此最小 LibRaw 配置不含 JPEG-lossy DNG 扩展。可在影调与色彩面板继续调整；未暴露 Mac 专用 RAW 解码控制。
- 肤色柔化是颜色范围算法，可能影响相近颜色；没有人脸专用分割、瘦脸、语义祛痘或训练好的商业美颜网络。
- 不包含 Mac 的 179 项完整专业控制、局部蒙版、四通道曲线、16 位/ICC 专业输出、相机联机、本地 Qwen 和语音接口。
- Portable v1 配方与 Mac EditRecipe v2 **尚不互通**；未知配方会明确拒绝。图库保存在当前平台的应用支持目录。卸载 Android 应用会移除其私有图库，请先导出所需结果；设备上的导入源文件不被修改。
- 单文件最大 512 MB、像素最大 80 MP，实际可处理大小受可用内存影响。移动设备建议分批处理大 RAW。
- Windows 当前包未做商业代码签名；Mac 为本机临时签名，未公证。Android 使用独立私有发布密钥签名，不含密钥文件。

## 构建与验证

固定工具：Flutter 3.50.0 / Dart 3.14.0，Flutter Git 提交 `ab2912035e160d9cad6306df307576da6128ebdb`。Android 使用 JDK 21；Windows 在 Windows 主机上使用 Visual Studio 2022 C++ 桌面工具。依赖由 `pubspec.lock` 固定。

```sh
flutter pub get --enforce-lockfile
flutter analyze
# Windows 主机
flutter build windows --release
# Android；发布前另外使用私有发布密钥签名
flutter build apk --release --target-platform android-arm64,android-x64
```

图像处理在常驻隔离进程中执行，最多一项预览在运行，下一项由最新状态替换。完整尺寸导出使用独立工作进程、队列串行执行。C++ 把影调/HSL/滤镜编译成单个 33³ 变换并缓存；降噪/柔化使用有界局部平均缓冲。

编译后的 Windows 程序可运行独立图库自检（不要把测试目录指向个人照片库）：

```powershell
.\lumastudio.exe --self-test C:\LumaStudio-Test C:\LumaStudio-Test\report.json
```

自检覆盖实际像素变化、原始尺寸导出、不覆盖已有输出、旋转裁切、JPEG/PNG/TIFF、重复导入、撤销、保存/自动两种批量和重启恢复。不把这些自动检查当作实体 Android 手机或用户 Windows 电脑的人工视觉验收。

## 第三方材料

LibRaw 0.22.3 采用 CDDL-1.0 许可，未修改其源文件；源码在 `packages/luma_native/src/libraw`，许可在 `assets/licenses`。原创图像核心与这些源文件分开编译。Flutter、Dart Image、file_picker、file_selector、path_provider、archive、share_plus、http、ffi、crypto 的许可可从应用“开源许可”页查看。

内置示例来自 raw.pixls.us 的 CC0 Olympus E-M1 样片，来源和原始 SHA256 记录于 `assets/demo-source.json`。界面字体是 Noto Sans SC 的 GB2312 与界面字符子集，改名 Luma UI，采用 SIL OFL-1.1；保留原许可。以上素材不是用户个人照片。公开源码不含个人图库、API 密钥、商业计划书、逆向私有资料或模型权重。
