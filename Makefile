export ARCHS = arm64 arm64e
export TARGET = iphone:clang:16.5:15.0

# TriggrBridge 是精简手势桥，只识别手势并发 Darwin 通知；动作由 RC 执行。
# 注入 SpringBoard（识别器挂系统手势层）+ 所有 App（冻结画面）。
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += Tweak
SUBPROJECTS += Relay

include $(THEOS_MAKE_PATH)/aggregate.mk
