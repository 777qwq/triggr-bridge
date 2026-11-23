include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TriggrBridgeRelay
TriggrBridgeRelay_LDFLAGS += -rpath /var/jb/Library/Frameworks -rpath /var/jb/usr/lib -rpath @loader_path/.jbroot/Library/Frameworks -rpath @loader_path/.jbroot/usr/lib
TriggrBridgeRelay_FILES = Relay.x
TriggrBridgeRelay_CFLAGS = -fobjc-arc
TriggrBridgeRelay_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
