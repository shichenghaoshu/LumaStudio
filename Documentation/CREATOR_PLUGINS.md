# LumaStudio 创作者插件首版（0.6.0 Preview）

这是可运行的 **Mac 本地创作中心 + 社区服务**。摄影师可以贡献 LUT、调色师可以发布配方、开发者可以组合局部算法和 AI 修图方法。所有插件使用同一份 `.lumaplugin` 协议，在单张编辑、逐张批量处理和 Agent 工具调用中执行。

架构参考 [DeepSeek 官方 Harness](https://github.com/deepseek-ai/DeepSeek-Harness) 的插件思路；没有引入或复制 Harness 运行时。v1 插件是经过校验的声明式工具，复用 LumaStudio 已有的算法和宿主模型。

## 使用安装包

打开随此版交付的 Mac App，点击编辑器顶栏的“创作中心”（叠层图标）。安装包附带独立本机社区服务，不需要用户安装 Python。服务仅监听 `127.0.0.1:8791`。如果是从源码直接编译，先按下文启动服务。

1. **发现与搜索**：按名称、说明、作者和标签搜索，筛选 LUT / 调色配方 / 局部工具 / AI 工具；支持最近更新、评分和下载排序。首屏的四个内置作品明确标为原创示例，没有虚构评分。
2. **试用**：先在编辑器选择照片，在创作中心点击“在当前照片试用”。这是实际本地渲染；按住对比按钮查看原图。试用不会修改当前配方，也不会把试用 LUT 写进用户滤镜库。
3. **安装与使用**：免费作品可以安装，商业作品当前仅作者可安装，其他用户可预览。安装后可应用到当前照片、导出已选照片，或让 Agent 调用。单张应用可以用编辑器“撤销”恢复。
4. **收藏与评分**：创建本机账号后收藏作品、写 1–5 分反馈。同一账号的评分会更新，作者不能给自己的作品评分。记录保存在 SQLite 中，刷新和重启后仍存在。
5. **成为作者**：注册时选择摄影师、调色师、开发者等身份。点“发布作品”，上传 `.lumaplugin`，或把 CUBE、v2 配方、LocalMask JSON、AI 指令转换成插件。Mac 可直接读取当前编辑参数生成共享配方；会去除裁剪、RAW、输出、蒙版、锁和本机参考档案，不带 API 密钥。
6. **更新与回退**：相同作者可以发布更高的 `major.minor.patch` 版本。已经发布的版本不能覆盖。详情里的版本选择可以安装旧版本；安装记录保存版本和 SHA-256，执行前再次校验。

Mac 导出的插件包保存在“下载 / LumaStudioPlugins”。批量照片结果保存在当前图库的 `Exports`，保留每张照片原有的构图、RAW、输出设置、局部蒙版和参数锁。局部插件只增改自己对应的蒙版，不替换其他局部编辑。AI 指令插件可使用“接入设置”中的本地或在线规划器，也可在本次操作中明确选择“本地规则（无需密钥）”，遵守当前照片的约束。不会静默替换用户选定的在线配置。

## 四类插件协议

- **LUT**：一个 2–65 维、0–1 定义域的 CUBE；包内嵌 Base64 资源和 SHA-256，声明 `asset.lut` + `edit.recipe`。
- **调色配方**：v2 编辑参数和允许同步的分组；声明 `edit.recipe`。v1 支持影调、白平衡、颜色、曲线、分级、滤镜、美颜、细节、效果。插件不能把作者的本地 LUT / 参考档案路径带到其他机器。
- **局部工具**：一个 LocalMask 声明；声明 `edit.localMask`，使用已支持的人脸、皮肤、人物、背景或画笔区域。区域检测失败由现有图像引擎报错，不伪造分割结果。
- **AI 工具**：最多 2000 字的指令模板，`${request}` 插入用户补充；声明 `agent.plan` + `edit.recipe`。宿主提供分析和规划器，返回值重新验证、限制到允许的编辑分组。

[JSON Schema](../Resources/Plugins/plugin.schema.json) / [四类完整示例](../Resources/Plugins/Examples) / [示例完整 MIT 许可](../Resources/Plugins/LICENSE.txt)。包总大小上限 12 MB，单个 CUBE 上限 8 MB。未知执行字段、任意脚本、动态库、网络端点、路径穿越资源会被拒绝。v1 的局部处理与 AI 工具是对宿主能力的组合，尚不能加载第三方任意新算法代码；这需要后续独立沙箱与版本化二进制接口。

统一宿主 API 为 `PluginRuntime.execute(package, on:current, context:.editor/.batch/.agent, request:, planner:)`。插件返回普通的 v2 `EditRecipe`，随后交给现有的 `PhotoProcessor` / `BatchProcessor` 渲染。版本、场景和参数变更写入执行记录。

### Agent 调用

Mac AI 助手可以输入：

```text
/plugin studio.luma.warm-light
/plugin studio.luma.portrait-assistant 不要美白
```

只会调用已经安装的明确 ID。创作中心的“Agent 调用”按钮使用同一个接口。开发者或外部 Agent 也可以通过 CLI 验证、生成实际照片结果：

```bash
swift run -c release LumaAgentCLI plugin validate Resources/Plugins/Examples/studio.luma.warm-light.lumaplugin
swift run -c release LumaAgentCLI plugin run PACKAGE IMAGE CURRENT_RECIPE OUTPUT_JPG RECEIPTS_DIR agent '不要美白'
```

`CURRENT_RECIPE` 是现有 v2 JSON。`OUTPUT_JPG` 必须是新的安全路径。CLI 的 AI 工具使用本地规则规划器，不会自行读取在线 API 凭据；Mac 宿主使用用户在接入设置中选择的规划器。

## 本地社区服务与开发

运行时只需 Python 标准库（3.12+），无需安装 Web 框架。SQLite 的数据、账号摘要和登录会话都在用户目录，不能提交到源码仓库。

```bash
cd /Users/admin/Desktop/lumastudio
python3 Tools/PluginCommunity/server.py --seed-examples
```

访问 [本机创作中心](http://127.0.0.1:8791)。默认数据库：`~/Library/Application Support/LumaStudio/Community/community.sqlite3`。可使用 `--port` / `--data` 或 `LUMA_COMMUNITY_PORT` / `LUMA_COMMUNITY_DATA` 指定隔离测试实例。Mac 首版宿主固定连接 8791 的回环地址。

服务按账号、目录、协议和 HTTP 边界分层。密码使用独立盐和 PBKDF2-SHA256 600000 次迭代；会话使用随机 token，仅保留 token 摘要，通过 HttpOnly / SameSite=Strict cookie 传递。退出会撤销当前会话，30 天后需重新登录。默认不接受外部 Host / Origin，不返回宽泛 CORS 许可；对发布、认证和下载限制请求频率。请求日志只记录请求 ID、路由、状态和耗时。

| 操作 | 接口 |
| --- | --- |
| 存活 / 数据库状态 | `GET /health` / `GET /ready` |
| 本地能力与支付状态 | `GET /api/config` |
| 注册 / 登录 / 退出 / 当前账号 | `POST /api/register`、`/api/login`、`/api/logout`，`GET /api/me` |
| 搜索 / 作者作品 / 收藏 | `GET /api/plugins?q=&kind=&sort=&mine=1&favorites=1` |
| 发布不可覆盖的新版本 | `POST /api/plugins`（原始插件 JSON） |
| 详情 / 历史版本 / 反馈 | `GET /api/plugins/{id}` |
| 预览包 / 安装包 | `GET /api/plugins/{id}/package?mode=trial|install|download&version=` |
| 收藏 / 评分 / 问题反馈 | `PUT .../favorite`、`PUT .../rating`、`POST .../report` |
| 创作者资料与作品 | `GET /api/authors/{id}` |

搜索最多返回 100 个结果；返回真实总数。下载计数是请求次数，包括版本重取，**不是安装人数**。问题反馈只写进本地待审核队列，不会发送给外部人员。单个账号发布包的总容量暂为 200 MB。

### 构建与验证

```bash
python3 -m unittest discover -s Tests/PluginCommunityTests -v
swift test -c release --filter PluginTests
```

`PluginPhotoTests` 通过 `LUMA_COLOR_LOOK_FIXTURES` 和 `LUMA_PLUGIN_OUTPUT` 接收现有有来源记录的公开人像和证据目录；未配置真实照片时明确跳过。包含四类插件的实际 GPU 预览、逐张批量导出以及源文件摘要保护。

随 App 分发的本机服务使用独立打包环境构建，依赖锁在 `Tools/PluginCommunity/packaging-requirements.txt`。构建脚本不会读取用户照片、账号数据库或凭据：

```bash
uv venv work/plugin-ecosystem/packaging-venv
uv pip install --python work/plugin-ecosystem/packaging-venv/bin/python -r Tools/PluginCommunity/packaging-requirements.txt
work/plugin-ecosystem/packaging-venv/bin/python Scripts/build_plugin_service.py
```

将生成的 `service-dist/LumaCommunity` 整个目录放到候选 App 的 `Contents/Resources/PluginCommunity`，然后重新签名。目录带有运行时许可证与构建摘要；不能只复制可执行文件。独立服务在通过 Mac App 启动时跟随启动它的 App 退出，手动启动的开发服务按终端进程生命周期运行。

## 商业授权与收益的实际边界

已经实现：作者选择开源 / 免费 / 商业许可、登记条款、价格与币种，作品展示来源与作者主页；真实搜索、评分与收藏有助于作品被发现；安装端区分免费、作者和未授权商业作品。授权按请求的具体版本检查，不会被后续改价绕过。

**尚未接通：公网社区部署、支付下单、支付回调、付费权益签发、退款、作者分账与提现。当前没有真实交易、收益或平台抽成记录。** UI 返回 `not_connected` 和未知收益，不展示虚构余额。商业试用是产品预览约定，不是 DRM；声明式配方与 LUT 不能防止复制。

付费生态下一步应在可部署的 HTTPS 服务上加入订单、支付适配器、验签回调、权益和分账账本。接入真实平台账号、支付商户与结算主体后，才能验证收款与作者收益。当前服务绑定回环地址，交付范围为本地可运行验证版。

## 本轮已验证范围

本地完整 Release 回归 **161 项通过，0 失败、0 跳过**，包含原有相机、RAW、美颜、色彩、批量、模型和语音模块；新增插件测试覆盖四类包、字段/资源校验、场景限制、锁和照片状态、安装版本冲突/回退/篡改、商业授权以及实际照片执行。独立社区接口 **7 项通过**，语音 MCP **3 项通过**。真实人像完成 **8 张 GPU 插件预览与 2 张批量导出**；这些数据证明执行与状态保护，不代表审美得分或厂商匹配率。

Mac Release 构建通过；独立打包服务已实际验证健康接口、四类目录和静态页面。对应日志保存在本地 `Artifacts/PluginEcosystem` 与 `work/plugin-ecosystem`，实际界面验收与最终包摘要单独记录。源码 CI 在 GitHub 上执行，外部素材/大模型不随仓库提供，CI 的跳过范围与本地完整素材回归不同。

## 0.6.1 社区补齐

- 点击左下角账号，在创作者主页编辑昵称、介绍和身份。历史插件包保持不可变，作者资料更新不会重写已发布的包。
- 在作品详情点击作者，可关注或取消关注；“关注动态”按所选排序显示关注作者的作品，支持类型筛选、搜索和翻页。
- 创作者主页可查看全部作品，作品列表每页 24 个，不再截断在前 100 个。
- 窄屏也保留登录与投稿入口。
- `PUT /api/me` 修改当前用户资料（name/roles/bio）；`PUT /api/authors/{id}/follow` 接收 `{ "value": true }`；作品列表新增 `following=1`、`author`、`offset`、`limit`，返回 total/offset/limit/hasMore。所有账号操作仍要求同源会话，关注幂等、不可关注自己。
- 本版本仍为本机社区。公网托管、支付与结算未配置。
