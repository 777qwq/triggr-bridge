# TriggrBridge · RC

精简手势桥：把 16 种 RemoteCompanion 原生没有的边缘 / 多指手势，转换成 RC 触发器。
与 Triggr 5.3.x 完全独立、可共存；本插件自身不执行任何动作。

## 工作方式

```
手指手势 → TriggrBridge(SpringBoard 识别 → Darwin 通知) → RC Add-on JSON(events → trigger) → 你在 RC 里指派动作
```

- **TriggrBridge.dylib**（注入 SpringBoard）：识别 16 种手势，识别成功发 `com.johndie.triggrbridge/<手势 id>`。
- **TriggrBridgeRelay.dylib**（注入所有 App）：手势期间冻结列表 / 照片，结束后还原。
- **triggrbridge.json**：装到 RC 的 Add-ons 目录，把 16 个通知注册成 `Add-on: …` 触发器。

## 16 个手势

| 类别 | 手势 |
|---|---|
| 边缘（2） | 从左侧滑入、从右侧滑入 |
| 双指（7） | 点按、上滑、下滑、左滑、右滑、捏合、张开 |
| 三指（7） | 点按、上滑、下滑、左滑、右滑、捏合、张开 |

> 只映射 RC 原生没有的手势。左 / 右缘竖滑、状态栏双指下滑、底部双指上滑是 RC 自带的，
> 本插件**不接管**，避免双重触发。

## 用法

1. 安装本 deb（依赖 RemoteCompanion 已装）。
2. 打开「设置 → Triggr 手势桥」：总开关与冻结开关默认开，16 个手势默认都开，按需关掉不用的。
3. 打开 RemoteCompanion → 触发器，找到 `Add-on: 从左侧滑入`、`Add-on: 双指上滑` 等 16 条，
   给它们指派你想要的 RC 动作。
4. 改完设置即时生效（不需要 respring）；首次安装识别器会在解锁后挂上。

## 与 RC 自带双指手势同时用

RC 的「状态栏双指下滑」「底部双指上滑」只在状态栏 / 底部栏起手时触发；本插件的双指上下滑是全屏识别。
若你两者都装，建议**把 RC 原生那两条触发器的动作留空**，动作只挂在对应的 `Add-on:` 触发器上，
一次手势就只有一条路径执行。

## 构建

macOS 上：

```bash
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
```

arm64e 必须在 macOS 上用 Xcode 工具链构建（CI 已配置）。Linux 上只能做语法编译验证。
