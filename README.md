# SitRight 坐正

SitRight 坐正是一个轻量的 macOS 菜单栏活动提醒应用，借鉴定时活动提醒体验，按照实际可提醒的工作时间累计提醒节奏。

SitRight 不检测坐姿、真实运动或键鼠活动。活动记录来自你主动完成的 60 秒引导；可以走动、站立、坐姿活动或选择适合身体状况的方式。

## 第一版功能

- 菜单栏实时倒计时
- 到点提醒：开始 1 分钟活动、延后 5 分钟或暂停今天
- 完成完整 60 秒引导后才记一次活动，提醒后和主动活动都计入每日目标
- 两只独立时钟：可提醒活动累计时间与提醒机会响应窗口
- 每日活动目标、提醒后活动、主动活动和旧版未分类记录分开展示
- 30 / 45 / 50 / 60 分钟快捷间隔
- 自定义提醒间隔
- 延后 5 分钟
- 暂停、恢复、暂停今天
- 工作时间、午休、工作日提醒设置
- 系统通知和轻量完成奖励
- macOS WidgetKit 桌面小组件
- 开机启动开关
- 每天后台检查 GitHub 社区预览版更新，并在菜单中轻提示
- 「关于」页可查看版本、更新、开源协议、隐私/安全说明和社区入口
- 可在「设置 → 通用 → 应用 → 语言」中选择自动跟随系统、简体中文或 English；菜单栏面板、设置、提醒引导、系统通知和桌面小组件会同步更新
- 聚焦今日状态与快捷操作的菜单栏面板，低频选项集中在标准 macOS 设置窗口

## 提醒节奏与主动活动

SitRight 把提醒节奏和活动记录分开处理，避免主动增加的一次活动被简单当作下一次提醒的替代：

- 收到提醒后完成 60 秒活动，会完成本轮提醒，并从完成时开始下一完整提醒间隔。
- 提前完成「主动活动 1 分钟」，会计入主动活动和每日目标；通常保留原定提醒时间，在可提醒且会话活跃的时段内，60 秒引导期间提醒计时也会继续。
- 如果主动活动完成时距离原提醒不超过 10 分钟，则视为本轮活动已经满足，不会紧接着重复提醒；下一完整间隔从完成时开始。
- 取消「主动活动 1 分钟」不会计入目标，也不会重置原提醒节奏；如果此时已经到点，提醒会按正常流程出现。
- 取消由提醒发起的活动不会计入完成；本次提醒机会按未完成处理，后续提醒继续按既有机制安排。
- 「从现在重新计时」只重置提醒计时，不会增加活动次数。

主动活动和提醒后活动始终分开统计；临近到点时由主动活动满足本轮，也不会虚增提醒机会或提醒响应率。

## 本地运行

```bash
swift run
```

首次启动后，macOS 可能会请求通知权限。应用平时是菜单栏常驻形态，不显示 Dock 图标；打开标准设置窗口时会临时显示 Dock 图标和应用菜单，以支持 `⌘H` 等原生 macOS 命令。隐藏设置窗口后，仍可通过 `⌘Tab` 切回并恢复原窗口；关闭最后一个标准窗口后才会返回纯菜单栏模式。

应用内语言偏好默认为「自动（跟随系统）」，并以稳定值 `system_default` 保存在现有设置文件中：中文系统显示简体中文，其他系统语言显示英文，也可以手动固定为「简体中文」或 `English`。已有用户明确选择的语言保持不变。切换语言只改变展示文案，不会重新计时、改变活动统计、改变系统的 12/24 小时制或迁移活动历史；Widget 会通过 App Group 快照使用同一偏好。Dock 与应用菜单中的应用名称固定为「SitRight 坐正」，不会随应用内语言切换；macOS 自带菜单命令和 Sparkle 标准更新窗口中的系统级文案仍可能遵循系统语言，也无法随应用内偏好即时变化。

`swift run` 使用开发环境的 Application Support 目录；该数据不保证自动迁移到沙箱化的 `.app`。打包版本的 App 与 Widget 以 App Group 作为唯一共享数据源。

## Agent Workflow

代理接手开发前请先阅读 [`AGENTS.md`](AGENTS.md)。该文件记录项目结构、生成物禁改规则、现有构建/测试命令和 Codex 工作流入口。

## 开源与社区

SitRight 源代码采用 [MIT License](LICENSE)。你可以使用、修改、分发和商业使用，但分发的软件或主要代码副本必须保留原版权与许可声明；软件按现状提供，不附带担保。

「设置 → 关于 → 开源与社区」提供以下入口：

- 在应用内离线查看 SitRight 的 MIT 协议和 [Sparkle 2.9.2 第三方许可](Sources/Resources/Third-Party-Notices.txt)。
- 查看[源代码](https://github.com/leonthinking/SitRight)或为项目点 Star。
- 通过结构化表单提交[使用问题](https://github.com/leonthinking/SitRight/issues/new?template=support_request.yml)、[功能建议](https://github.com/leonthinking/SitRight/issues/new?template=feature_request.yml)和[问题报告](https://github.com/leonthinking/SitRight/issues/new?template=bug_report.yml)。
- 阅读[隐私说明](PRIVACY.md)、[安全政策](SECURITY.md)、[支持说明](SUPPORT.md)和[贡献指南](CONTRIBUTING.md)；未修复的安全漏洞请使用 GitHub 私密漏洞报告，不要创建公开 Issue。

提醒设置和提醒会话状态保存在主应用的本地容器；活动历史和 Widget 快照通过 App Group 在 App 与 Widget 之间共享。SitRight 不会向开发者或远程服务自动上传这些数据，也不会采集或上传诊断日志。提交 Issue 前请主动移除密码、令牌、私钥、个人文件路径及其他不必要的敏感信息。Sparkle 与其包含的第三方代码继续遵循各自的许可，SitRight 的 MIT 协议不会替代这些条款。

## 打包依赖

打包 `.app`、WidgetKit 扩展和更新器需要安装 Xcode 与 XcodeGen。构建会按 `Package.resolved` 下载固定的 Sparkle 2.9.2：

```bash
brew install xcodegen
```

## 打包为 .app

```bash
./Scripts/build_app.sh
```

打包产物会生成在：

```text
build/SitRight.app
```

打包后的 `.app` 会包含：

```text
build/SitRight.app/Contents/PlugIns/SitRightWidgetExtension.appex
```

Widget 与主应用共享数据要求 App 和 Widget 使用有效 Apple 签名身份，且 TeamIdentifier 为 `973KFG9CL9`。Sparkle Framework、Updater、Autoupdate 和两个 XPC 服务也必须按嵌套顺序使用同一身份签署。本地构建会自动选择可用的 Apple Development 身份，也可通过 `SITRIGHT_CODE_SIGN_IDENTITY` 显式指定；普通打包仍可生成结构验证用的 ad-hoc 产物，但脚本会拒绝把无 TeamIdentifier 的产物安装为可用 Widget。安装并运行共享数据版本：

```bash
SITRIGHT_INSTALL_TO_APPLICATIONS=1 ./Scripts/build_app.sh
open /Applications/SitRight.app
```

安装模式会把已验证的候选移动到 `/Applications`，并清除本次 `build/` 副本的系统登记与可发现 `.app` 形态，避免 macOS 从本地构建目录加载另一份 Widget。若还需要保留独立的 `build/SitRight.app`，请在完成安装验收后重新运行不带安装参数的普通构建命令；该副本不应与正式安装版本同时用于 Widget 验收。

“登录时打开 SitRight”使用 macOS ServiceManagement。系统若暂时无法识别登录项，
应用会提供重新检测和打开“登录项与扩展”的入口；该状态不能单独证明 App 未打包。

## 打包为 DMG

参考 CapCap 的可拖拽安装流程，SitRight 提供一条完整的 DMG 打包命令：

```bash
./Scripts/package_dmg.sh
```

脚本会重新构建 Release `.app`，并在创建镜像前强制校验主应用、Widget 和所有 Sparkle 嵌套组件的签名、版本、架构、App Group 和 TeamIdentifier。随后基于不可变的暂存 App 生成带 `Applications` 快捷方式的压缩 HFS+ 候选镜像，镜像顶层只允许 `SitRight.app` 与 `Applications` 链接；脚本还会执行 checksum、只读挂载、内容比对及挂载后签名复验。验证未通过时不会替换上一份输出；只有全部验证通过后才会同步发布 `build/` 中的 DMG 和对应 `.sha256`。

如需打包成功后自动打开镜像，可使用：

```bash
OPEN_DMG_ON_SUCCESS=1 ./Scripts/package_dmg.sh
```

该脚本不执行 Developer ID 公证或 stapling，因此它单独生成的 DMG 一律按内部测试安装包处理。`build/` 中的 App、DMG 和 checksum 都是本地生成物，不提交到源码仓库。

## GitHub 社区预览版与应用内更新

SitRight 使用公开的 [GitHub Releases](https://github.com/leonthinking/SitRight/releases) 与 Sparkle 2.9.2 提供社区预览版更新：

- 应用每天最多自动检查一次，不会每次启动都强制联网。
- 自动检查发现新版时，只在菜单面板显示「发现 SitRight vX」；不会抢占当前工作。
- 「设置 → 关于 → 版本更新」可关闭自动检查或手动打开 Sparkle 标准更新窗口。
- 手动检查未发现更高构建时，会明确显示当前版本、构建号和最近检查时间；当前版本不会把自己识别为更新。
- SitRight 禁用自动下载与静默安装。只有你在标准更新窗口确认后，才会校验、替换应用并重启。
- 更新 Feed 固定为 `https://github.com/leonthinking/SitRight/releases/latest/download/appcast.xml`。更新 ZIP 与 appcast 都必须通过 SitRight 专用 EdDSA 密钥验证，签名失败不会降级为不校验。

首个包含更新器的版本仍需要从 GitHub 手动下载安装；只有从该版本开始，后续版本才能应用内更新。`0.2.2 (7)` / `v0.2.2` 是引导版本，`0.2.3 (8)` / `v0.2.3` 首次验证了真实应用内替换与重启；`0.2.4 (9)` / `v0.2.4` 延续同一更新链路。实际可下载状态与资产以 [GitHub Releases](https://github.com/leonthinking/SitRight/releases) 为准。

### 首次安装限制

社区预览版没有 Developer ID、公证或 stapling。首次下载后请把 `SitRight.app` 从 DMG 拖到「应用程序」，再通过 Finder 的「右键 → 打开」确认；如果 macOS 仍阻止启动，可前往「系统设置 → 隐私与安全性」核对并手动允许。不同 macOS 版本的提示文字可能略有不同。

这条路线允许任何人从 GitHub 下载，但不等同于 Apple 正式独立发行：Gatekeeper 可能显示警告，`spctl` 也不会把它认定为已公证应用。若未来加入 Apple Developer Program，仍需改用 Developer ID、Hardened Runtime、公证和 stapling。

## 准备社区预览版 Release

发布必须在拥有 TeamIdentifier `973KFG9CL9` Apple Development 身份和 SitRight Sparkle 私钥的本机执行。私钥保存在钥匙串账户 `com.leon.SitRight`；仓库只保存公钥。首次公开发布前必须将私钥导出到受控的离线介质并验证可恢复，例如：

```bash
/已校验的/Sparkle-2.9.2/bin/generate_keys \
  --account com.leon.SitRight \
  -x /安全的离线位置/SitRight-sparkle-private-key
```

这里的工具必须来自 Sparkle 2.9.2 官方 SwiftPM 工具包，并核对其 SHA-256 为 `b83e37436774556ed055e0244b297ef2c790e0737393bf65bf495fcbba6eed65`。导出的文件等同于更新签名密码，禁止放入本仓库、聊天记录、日志、GitHub Secrets 或 Release。私钥丢失后，没有 Developer ID 作为信任回退的已有客户端将无法安全接受新密钥。

明确更新 `project.yml` 中的版本与构建号、完成源码提交并保持发布范围干净后，生成本地资产：

必须用 `SITRIGHT_RELEASE_NOTES_FILE` 指向已经复核的 Markdown 更新说明；脚本会把它嵌入并随 appcast 一起签名：

```bash
SITRIGHT_RELEASE_TAG=vX.Y.Z \
SITRIGHT_RELEASE_NOTES_FILE=/已复核/release-notes.md \
./Scripts/package_update.sh
```

脚本会从当前已提交的 commit 导出隔离源码快照，在快照中构建，再生成版本化目录 `build/community-releases/vX.Y.Z-buildN/`。目录中只有准备上传的 DMG、仅含 `SitRight.app` 的 ZIP、已签名 `appcast.xml`、`SHA256SUMS`，以及不上传的本地 `RELEASE-MANIFEST`。生成 appcast 时只扫描更新 ZIP，不会把供手动安装的 DMG 误选为更新载荷；经复核的更新说明直接嵌入签名 appcast。脚本每次都重新下载固定 URL 的 Sparkle 2.9.2 官方工具包，先核对固定 SHA-256，再把工具包和三个发布工具的哈希写入本地 manifest；发布阶段会独立下载并逐项复核。脚本还会验证版本、构建号、arm64 架构、Bundle ID、App/Widget/App Group、所有 Sparkle 嵌套签名、钥匙串公私钥匹配、ZIP 内容、appcast URL、EdDSA 签名和 SHA-256；同名不同哈希的旧资产不会被覆盖。

人工复核资产、离线密钥备份、源码提交和 Release Notes 后，先让远端 tag 指向候选提交，再进行一次显式确认发布：

```bash
SITRIGHT_RELEASE_CONFIRMATION=vX.Y.Z \
SITRIGHT_BOOTSTRAP_CONFIRMATION=vX.Y.Z \
SITRIGHT_SPARKLE_KEY_BACKUP_CONFIRMATION=vX.Y.Z \
SITRIGHT_RELEASE_NOTES_FILE=/已复核/release-notes.md \
./Scripts/publish_update_release.sh \
  build/community-releases/vX.Y.Z-buildN
```

`SITRIGHT_BOOTSTRAP_CONFIRMATION` 与 `SITRIGHT_SPARKLE_KEY_BACKUP_CONFIRMATION` 只在首个没有既有 appcast 的更新器版本需要；前者确认建立更新 Feed，后者确认私钥已经完成离线备份和恢复验证。

发布脚本要求工作区保持干净、当前提交与候选一致、Release Notes 与签名 appcast 中的复核版本一致、`gh auth status` 有效、`origin` 和所有 GitHub 操作都明确指向 `leonthinking/SitRight`、远端 tag 正确、构建号高于 GitHub 实际 `latest` Release 中已签名 appcast 的构建号，并且四项资产完整。它会先把四项资产和 Release Notes 复制到私有临时快照，只验证、上传和回下载比对这份不可变快照；验证内容包含 checksum、DMG/ZIP 内容、App/Widget/Sparkle 签名、精确沙盒 entitlement、打包 App 内的 Sparkle 安全设置、appcast 与 ZIP 的 EdDSA 签名，以及与资产 manifest 一致的官方 Sparkle 工具哈希。脚本先创建不可见的 Draft，只有 Draft 完整通过后才在最后一步转为普通的非 Prerelease Release。公开请求失败时，脚本会查询远端并尝试恢复为 Draft；若网络异常导致无法确认或恢复，则保留本地恢复状态并硬阻断后续发布，要求人工核对远端状态，不能绝对保证远端始终停留在 Draft。它不会创建 GitHub Actions 工作流，不会上传 Apple 或 Sparkle 私钥，也不会合并 PR。

包含“开源与社区”入口的版本发布前，许可、第三方告知、隐私、安全、支持、贡献指南、Issue Forms、Issue 配置和 PR 模板必须已经以精确内容进入远端默认分支 `main`。发布脚本还会验证仓库保持公开、默认分支为 `main`、Issues 与 Private Vulnerability Reporting 均已启用；任一条件不满足都会在创建 Draft Release 前停止。

## 添加桌面小组件

1. 按上面的安装命令构建，并运行 `/Applications/SitRight.app`
2. 打开 macOS 小组件选择器
3. 搜索 `SitRight 坐正`
4. 选择「最近 3 个月」组件

当前提供「SitRight 坐正 · 最近 3 个月」展示型组件，仅支持大号尺寸，展示滚动最近 90 天的可信活动热力图和月份标尺。

组件同时展示今日活动目标、提醒后活动、主动活动、本周统计、连续天数，以及当前提醒状态和相关时间信息。

组件正文会跟随 SitRight 的应用内语言偏好显示简体中文或英文；选择「自动」时，中文系统显示简体中文，其他系统语言显示英文。在应用中切换后会刷新共享快照和组件时间线。组件库自身的名称和系统按钮仍由 macOS 的系统语言决定。

热力图的绿色深浅表示当天相对活动目标的完成度，而不是固定活动次数；完整绿色表示已经达标。今天使用强调描边，已记录为暂停日或非工作日的日期以中性描边显示。首周中最近 90 天范围之前的格子，以及今天之后到本周结束的格子，都会使用比真实未活动日更浅的装饰灰占位，让热力图两端保持完整、对称；这些占位不代表未完成，也不计入活动、活跃天数、达标天数或连续天数。没有历史目标快照的旧活动只使用最浅绿色，避免把未知完成度误报为达标。当前没有保存首次追踪日期，因此安装前无数据和安装后未活动的日期暂时仍使用相同的基础灰色。

旧版的「最近 1 年」组件已停止提供。升级后，已经放置的年度组件无法由 WidgetKit 自动迁移成季度组件，需要先移除旧组件，再手动添加「最近 3 个月」。

## 后续可扩展

第一版把倒计时、统计、设置和提醒逻辑拆开了。后续可以增加 AppIntent，让小组件支持快速延后、暂停和完成本次提醒。
