# 0.6.3 保存密钥与补充样图验收

密钥保存于系统钥匙串，应用会在内存中缓存已读取的密钥。显式“保存并记住”和“授权读取已存密钥”允许 macOS 发起系统授权，自动刷新与修图读取保持不弹窗。保存/读取操作在后台执行，避免阻塞编辑器。授权取消不会删除旧密钥，也不会自动反复弹窗。临时签名的开发版更新后仍可能需要重新授予系统访问权限，但无需重复填写 API 密钥；正式 Developer ID 签名尚未配置。

验证：独立测试账号完成保存/更新/读取，另用同一测试二进制的两个独立进程完成保存后退出、重新读取并清理，未读取或打印用户真实密钥。在线服务请求另行验收，本测试不代表真实服务连接通过。

新增 14 张品牌官网展示样图及 1 张用户雪山 PNG，本地规则生成方案并实际预览、按输入尺寸导出，全部15张原图哈希不变。2张检测到完整人脸，局部眼睛/剪影未计作完整人脸。阴影、高光、构图、锁定与禁止瘦脸/大眼受约束。官网 JPEG 为已处理图，部分为缩略图，不作为传感器 RAW 或品牌仿色精度测量。

| 样图 | 来源品牌 | 导出尺寸 | 完整人脸 | 导出/原图校验 |
|---|---|---|---|---|
| fujifilm-01.jpg | fujifilm | 768×512 | 0 | 通过 |
| fujifilm-02.jpg | fujifilm | 768×512 | 0 | 通过 |
| fujifilm-03.jpg | fujifilm | 512×768 | 0 | 通过 |
| nikon-01.jpg | nikon | 1280×852 | 0 | 通过 |
| nikon-02.jpg | nikon | 1280×852 | 0 | 通过 |
| nikon-03.jpg | nikon | 852×1280 | 1 | 通过 |
| nikon-04.jpg | nikon | 1280×852 | 0 | 通过 |
| panasonic-01.jpg | panasonic | 329×219 | 0 | 通过 |
| panasonic-02.jpg | panasonic | 329×219 | 0 | 通过 |
| panasonic-03.jpg | panasonic | 329×219 | 0 | 通过 |
| sony-01.jpg | sony | 2048×1365 | 0 | 通过 |
| sony-02.jpg | sony | 2048×1365 | 1 | 通过 |
| sony-03.jpg | sony | 2048×1365 | 0 | 通过 |
| sony-04.jpg | sony | 2048×1365 | 0 | 通过 |
| user-mountain.png | user-supplied | 6400×3600 | 0 | 通过 |

官方来源：

- [Sony α7 IV Gallery](https://www.sony.co.jp/en/Products/di_photo-gallery/camera/ILCE-7M4/)
- [Nikon Z8 Samples](https://nij.nikon.com/products/lineup/mirrorless/z8/sample.html)
- [Panasonic LUMIX S5 Gallery](https://panasonic.jp/dc/products/DC-S5/gallery/comuro-miho.html)
- [Fujifilm X-T5 Gallery](https://www.fujifilm-x.com/global/products/cameras/x-t5/gallery/)

Canon 官网当前对本机下载返回403，未绕过访问限制，未计入下载数量。官网照片与本次用户图片只用于本地验收，不随源码或安装包分发，不上传社区。逐图来源和SHA256记录在本地 Artifacts/Final063/sample-sources.json，原图与处理结果在 work/final063。
