// TriggrBridge · RC — app side.
// Only listens for the freeze notifications the SpringBoard tweak posts during
// multi-touch gestures, so a swipe doesn't also scroll a list / zoom a photo.
// Nothing else: no status bar, no shake, no back cascade.

#import <UIKit/UIKit.h>
#import <notify.h>

#import "../Shared/TGBridge.h"
#import "../Shared/TGFreeze.h"

%ctor {
    int snapshotToken, beginToken, endToken;
    notify_register_dispatch(TGBridgeFreezeSnapshot, &snapshotToken, dispatch_get_main_queue(), ^(int t) {
        TGFreezeSnapshotBegan();
    });
    notify_register_dispatch(TGBridgeFreezeBegin, &beginToken, dispatch_get_main_queue(), ^(int t) {
        TGFreezeBegin();
    });
    notify_register_dispatch(TGBridgeFreezeEnd, &endToken, dispatch_get_main_queue(), ^(int t) {
        TGFreezeEnd();
    });
}
