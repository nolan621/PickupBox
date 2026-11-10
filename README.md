# 取件夹 PickupBox

一个自用的 iOS 取件工具：**把取件短信自动变成结构化的取件码**，锁屏能看到，到期会提醒，走到取件点附近自动弹出。

整个 App 纯本地运行：没有服务器、没有账号体系、不联网、不上传任何数据。

## 功能

- **短信自动入库**：快捷指令监听含「取件」的短信，交给 App 解析并保存
- **取件码大卡片**：34pt 等宽字体，站在柜子前一眼看清
- **到期倒计时**：按剩余时间变色（绿 ≥12h、橙 ≥2h、红 <2h），到期前 2 小时本地提醒
- **地理围栏**：第一次站在取件点记住位置，以后进入 150 米范围自动弹出取件码
- **小组件**：主屏 / 锁屏显示待取件数量与取件点，数字颜色代表最急一件的紧急程度
- **本地备份**：导出 / 导入 JSON，配合快捷指令可做每日自动备份

## 它是怎么工作的

```
取件短信
   │
   ├─（快捷指令「收到信息时」自动化）
   ▼
AddPickupIntent（后台，不唤起界面）
   │  正则：取件码 + 取件点 + 时限
   ▼
pickups.json（App Group 容器，和小组件共享）
   │
   ├─ 主 App：列表 / 倒计时 / 通知
   ├─ 小组件：数量 + 地点
   └─ 地理围栏：进入范围弹通知
```

**关键设计**：不做「订单号 → 运单号 → 物流」的自动追踪。国内电商平台不对第三方开放买家订单物流接口，iOS 也不允许 App 读短信，所以追踪那一段在合规前提下无法自动化。这个项目只解决**最后一公里**：包裹入柜之后。

## 项目结构

| 路径 | 说明 |
|---|---|
| `PickupBox/PickupBoxApp.swift` | App 入口 |
| `PickupBox/PickupItem.swift` | 数据模型（兼容旧版 JSON 的自定义解码） |
| `PickupBox/PickupStore.swift` | 本地存储（App Group 容器）、排序、备份合并 |
| `PickupBox/PickupParser.swift` | **核心**：取件码 / 取件点 / 时限的正则解析 |
| `PickupBox/AddPickupIntent.swift` | 快捷指令调用的入口 |
| `PickupBox/BackupIntent.swift` | 生成备份文件供快捷指令保存 |
| `PickupBox/LocationService.swift` + `PickupSpot.swift` | 地理围栏 |
| `PickupBox/Notifier.swift` | 本地通知 |
| `PickupBox/ContentView.swift` | 列表页、倒计时卡片、备份导入导出 |
| `PickupBoxWidgets/` | Widget Extension：数量 + 地点 |

## 构建前必须改的 4 处

这个工程里留着原作者的签名配置，你必须换成自己的，否则会因为签名冲突装不上。

| 项 | 位置 | 怎么改 |
|---|---|---|
| **Team** | 两个 target 的 Signing & Capabilities | 改成你的 Apple ID（免费的 Personal Team 也能跑） |
| **Bundle ID** | 两个 target 的 General → Bundle Identifier | 改成 `com.你的名字.PickupBox` |
| **App Group** | `PickupBox/PickupBox.entitlements` | 改成 `group.你的BundleID` |
| **App Group** | `PickupBoxWidgetsExtension.entitlements` | 同上 |
| **App Group** | `PickupBox/PickupStore.swift` 里的 `appGroupID` | 同上 |
| **App Group** | `PickupBoxWidgets/PickupWidgetData.swift` 里的 `appGroupID` | 同上 |

App Group 一共 4 处，**必须完全一致**，任何一处不一致，小组件就会读不到数据。

> 改完 App Group 后，Xcode 会自动向开发者门户注册这个组；如果报错说组不存在，在 Signing & Capabilities → App Groups 里点 `+` 手动创建一次。

## 构建

### 方式 A：一条命令搞定（推荐）

```bash
./scripts/setup.sh
```

脚本会问你要 Team ID 和 Bundle ID，然后自动改好上表里的所有位置，改完还会逐项校验。

也支持非交互：

```bash
./scripts/setup.sh --team ABCDE12345 --bundle com.you.PickupBox
./scripts/setup.sh --dry-run          # 只看会改什么，不动文件
```

脚本会先把原文件备份到 `.setup-backup-<时间戳>/`，出问题可以还原。

### 方式 B：手动改

1. 用 Xcode 打开 `PickupBox.xcodeproj`
2. 按上表改好 Team / Bundle ID / App Group
3. 选真机（模拟器收不到短信，自动化无法测试）
4. ⌘R

首次运行会请求通知权限，允许即可。

## 配置短信自动化

1. 打开「快捷指令」→ **自动化** → **+** → 选 **信息**
2. 条件：信息包含 `取件` → 下一步 → **立即运行**
3. **新建空白自动化** → 添加操作 **「添加取件码」**
4. 点操作里的「短信内容」参数 → 选择变量 **「快捷指令输入」**
5. 完成

第 4 步是最容易漏的，参数没绑上就永远解析失败。

## 依赖

无第三方库。全部使用系统框架：

`SwiftUI` · `AppIntents` · `WidgetKit` · `CoreLocation` · `UserNotifications` · `Foundation`

## 已知限制

- **iOS 不允许 App 读取短信**，所以必须依赖快捷指令自动化。安卓上可以直接用通知监听实现全自动。
- **免费 Apple ID 签名 7 天过期**，到期要重新 ⌘R；重装可能清空数据，建议先用「导出备份」存一份。
- **小组件刷新由系统调度**，数据变化时会主动请求重载，但系统仍可能延迟。
- **工程使用新版项目格式**（Xcode 26/27 的 `project.xcproj`），旧版 Xcode 打不开。
- 取件点名称靠短信文本解析，遇到没覆盖的文案，往 `PickupParser.stationSuffixes` / `codePatterns` 里加一条即可。

## 许可

未指定。如果要开源，建议补一个 MIT 或 Apache-2.0 的 LICENSE 文件。
