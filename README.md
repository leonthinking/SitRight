# SitRight 坐正

SitRight 坐正是一个轻量的 macOS 菜单栏久坐体态提醒应用，适合长时间办公时定时提醒自己抬头、挺胸、起身活动。

## 第一版功能

- 菜单栏实时倒计时
- 到点弹窗提醒：抬头挺胸、起身活动
- `已活动` 轻打卡
- 今日完成进度和目标
- 15 / 30 / 45 / 60 分钟快捷间隔
- 自定义提醒间隔
- 延后 10 分钟
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
4. 添加小号或中号组件

当前小组件展示下次提醒倒计时、今日完成进度和提醒状态。它是展示型组件，延后/暂停等交互按钮后续可以通过 AppIntent 增加。

## 后续可扩展

第一版把倒计时、统计、设置和提醒逻辑拆开了。后续可以增加 AppIntent，让小组件支持快速延后、暂停和完成本次活动。
