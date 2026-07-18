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
open build/SitRight.app
```

打包产物会生成在：

```text
build/SitRight.app
```

打包后的 `.app` 会包含：

```text
build/SitRight.app/Contents/PlugIns/SitRightWidgetExtension.appex
```

## 添加桌面小组件

1. 运行 `build/SitRight.app`
2. 打开 macOS 小组件选择器
3. 搜索 `SitRight 坐正`
4. 添加中号或大号组件

当前小组件是展示型组件，展示今日活动目标、提醒后活动、主动活动、本周统计、连续天数和最近一年的可信活动热力图，并携带当前阶段和截止时间。

## 后续可扩展

第一版把倒计时、统计、设置和提醒逻辑拆开了。后续可以增加 AppIntent，让小组件支持快速延后、暂停和完成本次提醒。
