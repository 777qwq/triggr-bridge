include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = TriggrBridge
TriggrBridge_FILES = TGBridgeSettings.m
TriggrBridge_INSTALL_PATH = /Library/PreferenceBundles
TriggrBridge_FRAMEWORKS = UIKit
TriggrBridge_PRIVATE_FRAMEWORKS = Preferences
TriggrBridge_CFLAGS = -fobjc-arc
TriggrBridge_LDFLAGS += -rpath /var/jb/Library/Frameworks -rpath /var/jb/usr/lib -rpath @loader_path/.jbroot/Library/Frameworks -rpath @loader_path/.jbroot/usr/lib

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences"$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/TriggrBridge.plist"$(ECHO_END)
