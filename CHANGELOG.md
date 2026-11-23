# TriggrBridge 更新记录

## 1.0.2

- **修复「没配动作也冻结、多指滑不动屏幕」**：1.0.1 去掉设置面板时把原版 Triggr 的 gating 一起删了，14 个多指识别器无条件注册——正常双指 / 三指滚屏、缩放照片，位移一超过 16pt 就被当成手势并冻结画面，而 RC 那边没配动作、通知无人接收，等于白冻结。
  - 现恢复原版门槛：桥读取 RC 的 `rc_triggers.plist`，**只有当某手势的 Add-on 触发器 `masterEnabled` 开、`enabled` 开、`actions` 非空时才注册它的识别器**（判据与 RC 的 `RCExecuteTrigger` 完全一致，字段缺失一律视为 false）。
  - 没配动作的手势完全不注册识别器：不快照、不冻结、不误触，正常滑屏畅通。
  - 监听 `com.pizzaman.rc.configchanged`，在 RC 里配 / 删动作后识别器即时增删，不用重装、不用 respring。
  - 配了动作的手势仍保留原版冻结手感（识别瞬间钉住画面，防止跟着滚）。
- 双切片 arm64 + arm64e，rootless。

## 1.0.1

- **边缘识别器同步到 Triggr cn5.3.33**：
  - 左侧滑入：普通 `UIPanGestureRecognizer`，判定改用视觉坐标（`UIScreen.coordinateSpace`），横屏不再错位，保留系统原生左滑返回。
  - 右侧滑入：改回系统级 `UIScreenEdgePanGestureRecognizer`——SpringBoard 事件路由层优先认领，App 内容不再跟着滚；进入 Began 立即冻结并回弹到落指快照（Relay 侧同步），50pt 抬手才触发；视觉右边缘到物理边的换算覆盖横屏。
  - 这两个类在 5.3.28～5.3.33 经多轮真机迭代，1.0.0 用的是旧的 5.3.11 实现，本次整体替换。
- **修复 RC 边缘手势导致本插件滑入手势无法触发**：RC 的边缘识别器与本插件挂在同一个 `SBSystemGestureManager`，UIKit 默认互斥会把一方压成 Failed（即使 RC 没指派动作，识别器仍注册并参与互斥）。现所有识别器（边缘 + 多指）的 delegate 都返回 `shouldRecognizeSimultaneously = YES`，双方共存；方向判据各自独立，横滑与竖滑不会互相误触发。
- **移除设置面板**：删除 Prefs 子工程与所有偏好开关（总开关、冻结开关、16 手势开关）、reload 通知。全部手势常开，启用/停用与动作统一在 RemoteCompanion 的 Add-on 触发器上操作。包体只含 2 个 dylib + 1 个 Add-on JSON。
- 双切片 arm64 + arm64e，rootless。

## 1.0.0

首个版本。新建独立工程，与 Triggr 5.3.x 共存。

- 只保留 16 个手势识别器，全部来自 Triggr 经过真机调校的实现：
  - 边缘：从左侧滑入（普通 pan，保留系统原生返回）、从右侧滑入（系统级 screen-edge pan）。
  - 多指：双指 / 三指各自的点按、上 / 下 / 左 / 右滑、捏合、张开。
- 识别成功只发一条 Darwin 通知 `com.johndie.triggrbridge/<手势 id>`，不含任何动作执行代码。
- 新增 `triggrbridge.json` Add-on：16 个 event 监听通知，注册成 16 个 RC 触发器。
- 新增冻结协调 Relay：多指手势期间冻结列表 / 照片，结束后还原（可在设置中关闭）。
- 设置页：总开关、冻结开关、16 个手势开关，改动即时生效。
- 只映射 RC 原生没有的手势；左 / 右缘竖滑、状态栏双指下滑、底部双指上滑不接管，避免重复触发。
- 双切片 arm64 + arm64e，rootless。
