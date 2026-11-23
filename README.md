# TriggrBridge · RC

手势桥：把 16 种 RemoteCompanion 原生没有的边缘 / 多指手势，转换成 RC 触发器。
与 Triggr 5.3.x 完全独立、可共存；本插件自身不执行任何动作。

## 工作方式

```
手指手势 → TriggrBridge(SpringBoard 识别 → Darwin 通知) → RC Add-on JSON(events → trigger) → 你在 RC 里指派动作
```

- **TriggrBridge.dylib**（注入 SpringBoard）：识别 16 种手势，识别成功发 `com.johndie.triggrbridge/<手势 id>`。边缘识别器与 Triggr **cn5.3.x** 同步：左侧普通 pan（保留系统原生返回），右侧系统级屏幕边缘手势（Began 即冻结回弹、50pt 抬手触发，横屏自动换算物理边）。
- **TriggrBridgeRelay.dylib**（注入所有 App）：手势期间冻结列表 / 照片，结束后还原；右侧滑入冻结时立即回弹。
- **triggrbridge.json**：装到 RC 的 Add-ons 目录，把 16 个通知注册成 `Add-on: …` 触发器。

**没有设置面板**。某条手势是否生效，取决于你在 RC 的 Add-on 触发器上有没有给它指派动作：桥读取 RC 的 `rc_triggers.plist`，只有该触发器「主开关开 + 触发器启用 + 至少一条动作」时才注册对应识别器。**没配动作的手势完全不注册**——不会冻结、不会影响正常滑屏。在 RC 里配 / 删动作会即时生效，不用 respring。所有已注册的识别器都声明了 `shouldRecognizeSimultaneously = YES`，和 RC 自带的边缘识别器在同一手势层上共存，互不抢占。

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
2. 打开 RemoteCompanion → 触发器，找到 `Add-on: 从左侧滑入`、`Add-on: 双指上滑` 等 16 条，
   给想用的手势指派 RC 动作。**指派后该手势才生效**；没指派的手势桥根本不接管，你正常滑屏、滚页面、缩放照片都不受影响。
   不想要某条手势了，把那条触发器的动作清空即可（识别器会自动移除）。
3. 无需 respring：识别器随你在 RC 里配 / 删动作即时挂上 / 移除。

## 构建

macOS 上：

```bash
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
```

arm64e 必须在 macOS 上用 Xcode 工具链构建（CI 已配置）。Linux 上只能做语法编译验证。
