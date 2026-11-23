export ARCHS = arm64 arm64e
export TARGET = iphone:clang:16.5:15.0

# TriggrBridge 是精简手势桥，只识别手势并发 Darwin 通知；动作由 RC 执行。
# 注入 SpringBoard（识别器挂系统手势层）+ 所有 App（冻结画面）。
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += Tweak
SUBPROJECTS += Relay
SUBPROJECTS += Prefs

include $(THEOS_MAKE_PATH)/aggregate.mk

# 版本号只在 control 里维护，stage 完写进 Info.plist（Linux 沙箱用 python3）。
TG_VERSION := $(shell sed -n 's/^Version: //p' $(THEOS_PROJECT_DIR)/control)

internal-stage::
	$(ECHO_NOTHING)set -e; \
	p="$(THEOS_STAGING_DIR)/Library/PreferenceBundles/TriggrBridge.bundle/Info.plist"; \
	[ -f "$$p" ] || exit 0; \
	if [ -x /usr/libexec/PlistBuddy ]; then \
	  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(TG_VERSION)" "$$p" 2>/dev/null \
	    || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $(TG_VERSION)" "$$p"; \
	  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(TG_VERSION)" "$$p" 2>/dev/null \
	    || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $(TG_VERSION)" "$$p"; \
	else \
	  python3 -c "import plistlib,sys; p=sys.argv[1]; d=plistlib.load(open(p,'rb')); d['CFBundleShortVersionString']=sys.argv[2]; d['CFBundleVersion']=sys.argv[2]; plistlib.dump(d,open(p,'wb'))" "$$p" "$(TG_VERSION)"; \
	fi$(ECHO_END)
