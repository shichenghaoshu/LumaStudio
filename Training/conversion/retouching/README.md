# 本地 AI 精修模型转换

原模型为 Alibaba / ModelScope `iic/cv_unet_skin-retouching`，官方模型页标注 Apache License 2.0。仓库保留完整许可、源代码出处、上游权重和转换后文件的校验值。LumaStudio 没有训练这些模型。

三个 Core ML 模块随 Mac 完整包离线提供：

- `LumaBlemishDetect`：768 × 768 的局部瑕疵概率。
- `LumaBlemishHeal`：576 × 576 的局部 RGB 修复差值。
- `LumaRetouchBlend`：512 × 512 的自适应混合层，用于改善肤色和皮肤明暗。

运行时使用原生 Core ML、Vision 和 Core Image，不需要 Python、TensorFlow、Photoshop 或网络。模型输入为按人脸较大边 1.5 倍扩展的裁片；预测差值与混合层放回原尺寸像素，并受皮肤及五官保护蒙版约束。与上游的原尺寸分块修复不同，本适配采用固定尺寸修复，细小瑕疵可能遗漏。

开发转换环境：Python 3.11、PyTorch 2.8.0、coremltools 8.3.0、NumPy 1.26.4、Pillow 11.3.0。coremltools 对 PyTorch 2.8 提示未经其官方测试；本项目另以实际数值对照核验转换结果，见验证脚本。此环境仅供开发，不进入应用。

```sh
python Training/conversion/retouching/convert.py \
  --weights-dir work/retouch-weights --download \
  --output work/retouch-coreml

python Training/conversion/retouching/verify_conversion.py \
  --weights-dir work/retouch-weights \
  --models-dir Packages/BeautyEngine/Resources/RetouchModels \
  --image /absolute/path/to/approved-portrait.jpg \
  --output work/retouch-parity.json
```

转换脚本只下载两份固定版本的公开权重，先核 SHA-256，再以 `weights_only=True` 读取。不会上传照片。转换记录不要求不同工具版本产出完全相同的二进制；提交资源的精确哈希见 `Models/manifests/retouch-coreml-v1.json`。校验脚本衡量转换数值误差，不能代替实际修图的质量评审。

来源：

- https://www.modelscope.cn/models/iic/cv_unet_skin-retouching/summary
- https://github.com/modelscope/modelscope/tree/master/modelscope/models/cv/skin_retouching
- https://openaccess.thecvf.com/content/CVPR2022/html/Lei_ABPN_Adaptive_Blend_Pyramid_Network_for_Real-Time_Local_Retouching_of_CVPR_2022_paper.html

`upstream` 文件保留 Alibaba 版权行。适配将 inpainting 网络的导入改为相对路径，并补回 `train()` 的 `return self`；网络权重未修改。完整 Apache 许可见同目录 `LICENSE.txt`。
