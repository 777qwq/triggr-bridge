// TriggrBridge · RC — gesture catalog shared by the tweak, the relay and Settings.
//
// This is a deliberately tiny bridge: it recognizes 16 gestures that RemoteCompanion
// does not natively have, and posts one Darwin notification per gesture. The RC
// Add-on JSON turns those notifications into triggers the user assigns actions to.
// There is no action execution, no shell, no plugin API in this project.

#define TGBridgeDomain      @"com.johndie.triggrbridge"
#define TGBridgeMasterKey   @"启用"        // master switch, default on
#define TGBridgeFreezeKey   @"冻结画面"    // freeze scrolling during multi-touch, default on

// Posted by Settings after any switch changes so the tweak re-reads preferences.
#define TGBridgeReloadNotify "com.johndie.triggrbridge/reload"

// One notification per recognized gesture: prefix + gesture id.
#define TGBridgeNotifyPrefix @"com.johndie.triggrbridge/"

// App-side freeze coordination (the tweak posts, the Relay in every app listens).
#define TGBridgeFreezeSnapshot "com.johndie.triggrbridge/freeze-snapshot"
#define TGBridgeFreezeBegin    "com.johndie.triggrbridge/freeze-begin"
#define TGBridgeFreezeEnd      "com.johndie.triggrbridge/freeze-end"

static inline NSString *TGBridgeNotification(NSString *gestureId) {
    return [TGBridgeNotifyPrefix stringByAppendingString:gestureId];
}

// The 16 gestures, in a fixed order.
//   [0] edge.left, [1] edge.right
//   [2..8]   two-finger: tap, up, down, left, right, pinch in, pinch out
//   [9..15]  three-finger: tap, up, down, left, right, pinch in, pinch out
static inline NSArray<NSString *> *TGBridgeGestureIds(void) {
    return @[
        @"edge.left", @"edge.right",
        @"inapp.twotap", @"inapp.twoup", @"inapp.twodown", @"inapp.twoleft", @"inapp.tworight",
        @"inapp.twopinchin", @"inapp.twopinchout",
        @"inapp.threetap", @"inapp.threeup", @"inapp.threedown", @"inapp.threeleft", @"inapp.threeright",
        @"inapp.pinchin", @"inapp.pinchout",
    ];
}

// Human-readable names, same order as TGBridgeGestureIds().
static inline NSArray<NSString *> *TGBridgeGestureNames(void) {
    return @[
        @"从左侧滑入", @"从右侧滑入",
        @"双指点按", @"双指上滑", @"双指下滑", @"双指左滑", @"双指右滑", @"双指捏合", @"双指张开",
        @"三指点按", @"三指上滑", @"三指下滑", @"三指左滑", @"三指右滑", @"三指捏合", @"三指张开",
    ];
}

// SF Symbol shown next to each switch, same order.
static inline NSArray<NSString *> *TGBridgeGestureIcons(void) {
    return @[
        @"arrow.left", @"arrow.right",
        @"hand.tap.fill", @"arrow.up", @"arrow.down", @"arrow.left", @"arrow.right",
        @"arrow.right.left", @"arrow.left.right",
        @"hand.tap.fill", @"arrow.up", @"arrow.down", @"arrow.left", @"arrow.right",
        @"arrow.right.left", @"arrow.left.right",
    ];
}
