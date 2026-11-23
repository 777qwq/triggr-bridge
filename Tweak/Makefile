include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TriggrBridge
TriggrBridge_LDFLAGS += -rpath /var/jb/Library/Frameworks -rpath /var/jb/usr/lib -rpath @loader_path/.jbroot/Library/Frameworks -rpath @loader_path/.jbroot/usr/lib
TriggrBridge_FILES = Tweak.x
TriggrBridge_CFLAGS = -fobjc-arc
TriggrBridge_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
