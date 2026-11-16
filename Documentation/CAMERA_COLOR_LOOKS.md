# Mac 0.5.5：相机风格仿色

新增 11 个独立仿色，内置滤镜由 30 增至 41。进入精修工作区 → 滤镜面板，默认展示“相机仿色”，可按徕卡灵感、哈苏灵感、富士灵感筛选。力度沿用现有 0–100% 控件，保存到每张照片的 v2 配方，可撤销、同步与批量导出。

这些是色彩风格近似，未用真实相机配对样本校准，不代表小米、徕卡、OPPO、哈苏或富士的专有算法，也没有厂商授权或背书。不同照片原有白平衡、曝光、相机处理会影响结果。只改色彩，不自动添加颗粒、暗角、锐化或 XPan 宽幅裁剪；这些效果可通过已有独立参数控制。

## 风格与实现

- **小米徕卡经典方向**（xiaomiLeicaClassic）：LumaStudio 原创；克制饱和、较深中暗调、微暖肤色，采用亮度曲线、按色相加权的饱和度和向色域边缘渐退的色度。
- **小米徕卡生动方向**（xiaomiLeicaVivid）：LumaStudio 原创；明快反差与较鲜明的红绿，对近肤色色相减弱额外饱和度。这里的肤色色相权重不是人脸分割，不保证只保护真正的皮肤。
- **OPPO 哈苏自然方向**（hasselbladNatural）：移植 Filmic 的 Natural Colour 通道矩阵、饱和度、反差和高光曲线。
- **哈苏 XPan 色彩**（hasselbladXPan）：Filmic 原始 17³ CUBE，冷影暖高光、褪色效果；保持当前照片比例。
- **徕卡微暖／Chrome／黑白**（leicaStandard / leicaChrome / leicaMonochrom）：分别移植 Filmic 矩阵、原始 CUBE、单色矩阵与影调曲线。
- **富士经典灰调／鲜艳／柔和／黑白**（fujiClassicChrome / fujiVelvia / fujiAstia / fujiAcros）：Filmic 的 Classic Chrome、Velvia、Astia、Acros 色彩近似；Astia 保留上游原始 CUBE。

新增 ID 不改变原 30 个 ID 或其 LUT 字节。6 个矩阵/曲线与 2 个原创风格离线烘焙为 33³ sRGB LUT；3 个上游 LUT 保持 17³ 原始字节。运行时仍由 Core Image 处理，不执行 Android CPU 逐像素代码。查找表按需加载并复用，避免每个处理器重复解析全部滤镜。sRGB 表应用于已经显影、白平衡与基础调整后的画面，不作为传感器 RGB、Log 或专用相机色彩配置。

文字输入支持例如“小米徕卡经典”“小米徕卡生动”“OPPO 哈苏自然色”“哈苏 XPan”“富士 Classic Chrome”“富士鲜艳”“徕卡黑白”。明确命名的相机风格按窄范围色彩请求处理，保留未提及的美颜、构图、局部蒙版与强度；AI 和同步仍遵守参数锁。与其他参数组合的指令继续按已支持的规则执行。手动点击维持原有规则，锁只限制 AI／同步。

## 开源来源与取舍

**实际接入：[yingwang/filmic](https://github.com/yingwang/filmic/tree/219e30356cc80ae90e98d78be2af5da149d49116)**，固定提交 219e30356cc80ae90e98d78be2af5da149d49116，MIT，Copyright (c) 2026 Ying Wang。上游明确说明其风格为手工调校近似，尚未经过相机配对校准。LumaStudio 使用浮点矩阵/曲线，省略上游 8 位中间量化、随机颗粒和裁剪，因此不宣称与 Android App 每个像素完全相同。完整许可已纳入应用 ThirdPartyNotices。原始源码、3 个 CUBE、原始 Git blob 与 SHA256 记录位于 Resources/ColorLooks/Filmic。

**研究候选：[JanLohse/spectral_film_lut](https://github.com/JanLohse/spectral_film_lut)**，MIT 的光谱胶片 LUT 生成工具，可研究更多胶片负片／正片／印相组合。其 README 也列明公开数据精度和简化模型的限制。本版本未安装运行该工具或纳入其 LUT，不将“找到”写成“已接入”。

**未随应用分发：[tqmane/film_sims](https://github.com/tqmane/film_sims)**。项目代码标 GPLv3，但 README 列出的滤镜来自小米、OnePlus、Leica 等固件或闭源应用的提取。项目代码许可不能证明它有权重新授权全部厂商调色资源，因此没有拷入这些 LUT。

**未随应用分发：[LaowuENT/leica-m9-style-lut](https://github.com/LaowuENT/leica-m9-style-lut)**。README 标注固件提取，本轮检查仓库没有明确许可证。未纳入资源或推导为可商用开源授权。

原创小米方向只参考公开的风格定位：[小米对经典／生动的官方说明](https://www.mi.com/global/support/faq/details/KA-513262/)。OPPO 哈苏方向参考其[自然色与影像技术说明](https://www.oppo.com/en/discover/technology/imaging/)，实际颜色数学来自上述 Filmic 开源近似，未提取 OPPO 的 HNCS 配置。

## 可复现与验证

运行 `python3 Scripts/generate_camera_looks.py --check` 可核验固定源文件、11 个新 LUT、清单和 30 个旧 LUT 的字节完整性。无网络、GPU 训练或第三方 Python 依赖。去掉 --check 会重建新 LUT，不写入旧 LUT。

本轮已完成 152 项本地 Release 测试，0 失败、0 跳过；另语音 stdio 3 项通过。包含实际 GPU sRGB 数值探针、灰阶单调性、黑白去色、全部 41 滤镜力度、JSON Schema 保存恢复、命名文字路由、锁和照片局部状态保护。sRGB 数值差是工程精度，不是厂商风格相似度。

6 张独立 Pexels 样图覆盖户外／低照／影棚人像、山林湖水、城市落日与霓虹夜景；66 组新风格处理加 6 张原图，已逐张目视检查。100% 风格力度用于效果对照，日常使用可降低力度。样图为已经处理的公开 JPEG，非同场景相机配对数据，也没有主观盲评。6/6 逐张配方批量输出原始尺寸 JPEG，最大 6000×4000，原文件 SHA256 保持；其中影棚人像同时启用中式标准美颜。

实际界面验收、构建来源与交付状态以本轮 Artifacts/ColorEmulation 和发布包 MANIFEST 为准，不套用 0.5.4 的界面验收。Windows／Android 仍为 0.5.0，本次没有多平台同等效果验收。Mac 为 Apple Silicon、macOS 14+，本地 ad-hoc 签名，未 Developer ID 公证。
