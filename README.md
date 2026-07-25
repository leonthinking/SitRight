# SitRight 坐正

SitRight 坐正是一个轻量的 macOS 菜单栏活动提醒应用，借鉴 Apple 的“50 分钟节奏 + 1 分钟活动”体验，采用更适合 Mac 的滚动可提醒时间。

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
- 聚焦今日状态与快捷操作的菜单栏面板，低频选项集中在标准 macOS 设置窗口

## 本地运行

```bash
swift run
```

首次启动后，macOS 可能会请求通知权限。应用是菜单栏常驻形态，不会显示 Dock 图标。

`swift run` 使用开发环境的 Application Support 目录；该数据不保证自动迁移到沙箱化的 `.app`。打包版本的 App 与 Widget 以 App Group 作为唯一共享数据源。

## Agent Workflow

代理接手开发前请先阅读 [`AGENTS.md`](AGENTS.md)。该文件记录项目结构、生成物禁改规则、现有构建/测试命令和 Codex 工作流入口。

## 打包依赖

打包 `.app` 和 WidgetKit 扩展需要安装 Xcode 与 XcodeGen：

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

Widget 与主应用共享数据要求 App 和 Widget 使用有效 Apple 签名身份，且 TeamIdentifier 为 `973KFG9CL9`。本地构建会自动选择可用的 Apple Development 身份，也可通过 `SITRIGHT_CODE_SIGN_IDENTITY` 显式指定；普通打包仍可生成结构验证用的 ad-hoc 产物，但脚本会拒绝把无 TeamIdentifier 的产物安装为可用 Widget。安装并运行共享数据版本：

```bash
SITRIGHT_INSTALL_TO_APPLICATIONS=1 ./Scripts/build_app.sh
open /Applications/SitRight.app
```

## 打包为 DMG

参考 CapCap 的可拖拽安装流程，SitRight 提供一条完整的 DMG 打包命令：

```bash
./Scripts/package_dmg.sh
```

脚本会重新构建 Release `.app`，并在创建镜像前强制校验主应用与 Widget 的签名、版本、架构、App Group 和 TeamIdentifier。随后基于不可变的暂存 App 生成带 `Applications` 快捷方式的压缩 HFS+ 候选镜像，执行 checksum、只读挂载、内容比对及挂载后签名复验。验证未通过时不会替换上一份输出；只有全部验证通过后才会同步发布 `build/` 中的 DMG 和对应 `.sha256`。

如需打包成功后自动打开镜像，可使用：

```bash
OPEN_DMG_ON_SUCCESS=1 ./Scripts/package_dmg.sh
```

该脚本不执行 Developer ID 公证或 stapling，因此输出一律按内部测试安装包处理。公开分发仍需要 Developer ID Application、Hardened Runtime、可信时间戳、公证、stapling，以及带 quarantine 的首次启动验证。`build/` 中的 App、DMG 和 checksum 都是本地生成物，不提交到源码仓库。

## 添加桌面小组件

1. 按上面的安装命令构建，并运行 `/Applications/SitRight.app`
2. 打开 macOS 小组件选择器
3. 搜索 `SitRight 坐正`
4. 选择「最近 3 个月」或「最近 1 年」组件

当前提供两种展示型组件：

- 「SitRight 坐正 · 最近 3 个月」仅提供大号尺寸，展示滚动最近 90 天的可信活动热力图。
- 「SitRight 坐正 · 最近 1 年」提供中号和大号尺寸，展示滚动最近 365 天的可信活动热力图。

两种组件都展示今日活动目标、提醒后活动、主动活动、本周统计、连续天数，以及当前提醒状态和相关时间信息。

## 后续可扩展

第一版把倒计时、统计、设置和提醒逻辑拆开了。后续可以增加 AppIntent，让小组件支持快速延后、暂停和完成本次提醒。
