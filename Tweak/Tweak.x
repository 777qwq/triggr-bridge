// TriggrBridge · RC — SpringBoard side.
//
// Recognizes 16 gestures RemoteCompanion does not natively have and posts one
// Darwin notification per gesture (com.johndie.triggrbridge/<gesture id>). The
// RC Add-on JSON listens on those names and exposes them as triggers; the user
// assigns RC actions there. This tweak performs no action itself.
//
// Recognizer code (thresholds, orthogonal pinch/swipe judgement, freeze) is
// ported unchanged from Triggr, where it was tuned on a real device over many
// versions. Only the hand-off at the end changed: TGFire -> notify_post.

#import <UIKit/UIKit.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
#import <notify.h>
#import <objc/runtime.h>
#import <objc/message.h>

#import "../Shared/TGBridge.h"
#import "../Shared/TGFreeze.h"

// SpringBoard's system gesture layer: recognizers here see touches over apps,
// the lock screen and the Home Screen alike.
@interface SBSystemGestureManager : NSObject
+ (instancetype)mainDisplayManager;
- (void)addGestureRecognizer:(UIGestureRecognizer *)recognizer withType:(unsigned long long)type;
- (void)removeGestureRecognizer:(UIGestureRecognizer *)recognizer;
@end

// Type numbers far from iOS's own so the system's gesture arbitration leaves us alone.
// Triggr uses 0x7467000; this bridge uses a different base so both can coexist.
static const unsigned long long TGBGestureTypeBase = 0x7468000;

#pragma mark - Preferences / enabled gestures

static NSMutableSet<NSString *> *tgEnabled;      // gesture ids currently enabled
static BOOL tgMasterOn = YES;
static BOOL tgFreezeOn = YES;

static void TGReadPrefs(void) {
    CFStringRef domain = (__bridge CFStringRef)TGBridgeDomain;
    CFPreferencesAppSynchronize(domain);
    id v = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)TGBridgeMasterKey, domain));
    tgMasterOn = v ? [v boolValue] : YES;
    v = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)TGBridgeFreezeKey, domain));
    tgFreezeOn = v ? [v boolValue] : YES;

    NSMutableSet *set = [NSMutableSet set];
    if (tgMasterOn) {
        for (NSString *gid in TGBridgeGestureIds()) {
            // 每个手势单独存一个开关。没写过 = 默认开启（装好就能用）。
            id on = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)gid, domain));
            if (!on || [on boolValue]) [set addObject:gid];
        }
    }
    tgEnabled = set;
}

static BOOL TGIsEnabled(NSString *gestureId) {
    return gestureId && [tgEnabled containsObject:gestureId];
}

// The whole "action": one notification. No shell, no app launch, no state.
static void TGFire(NSString *gestureId) {
    if (!TGIsEnabled(gestureId)) return;
    notify_post(TGBridgeNotification(gestureId).UTF8String);
}

#pragma mark - Freeze (port from Triggr 2.1)

static void TGMultiFreezeBegin(void) {
    if (!tgFreezeOn) return;
    TGFreezeBegin();
    notify_post(TGBridgeFreezeBegin);
}
static void TGMultiFreezeEnd(void) {
    if (!tgFreezeOn) return;
    TGFreezeEnd();
    notify_post(TGBridgeFreezeEnd);
}
static void TGMultiSnapshotBegan(void) {
    TGFreezeSnapshotBegan();
    notify_post(TGBridgeFreezeSnapshot);
}
static BOOL TGMultiTouchesFinished(UIEvent *event) {
    for (UITouch *touch in event.allTouches)
        if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled) return NO;
    return YES;
}

#pragma mark - Multi-touch recognizers (14 slots)

typedef struct { uint8_t fingers; uint8_t kind; } TGGestureSlot;
// kind: 0 点按, 1 上, 2 下, 3 左, 4 右, 5 捏合, 6 张开
static const TGGestureSlot kTGSlots[] = {
    {2, 0}, {2, 1}, {2, 2}, {2, 3}, {2, 4}, {2, 5}, {2, 6},
    {3, 0}, {3, 1}, {3, 2}, {3, 3}, {3, 4}, {3, 5}, {3, 6},
};
#define TG_SLOT_COUNT ((int)(sizeof(kTGSlots) / sizeof(kTGSlots[0])))
// Gesture id for a slot: index 2 + slot in TGBridgeGestureIds().
static NSString *TGSlotGestureId(int idx) {
    NSArray *ids = TGBridgeGestureIds();
    int i = 2 + idx;
    return i < (int)ids.count ? ids[i] : nil;
}
static const unsigned long long TGMultiTypeBase = TGBGestureTypeBase + 16;

static CGFloat TGMultiRadiusForTouches(NSSet<UITouch *> *touches, UIView *view) {
    NSUInteger n = touches.count;
    if (n < 2 || n > 3) return 0;
    CGPoint pts[3];
    NSUInteger i = 0;
    for (UITouch *t in touches) pts[i++] = [t locationInView:view];
    CGPoint c = CGPointZero;
    for (NSUInteger k = 0; k < n; k++) { c.x += pts[k].x; c.y += pts[k].y; }
    c.x /= n; c.y /= n;
    CGFloat sum = 0;
    for (NSUInteger k = 0; k < n; k++) sum += hypot(pts[k].x - c.x, pts[k].y - c.y);
    return sum / n;
}

// 捏合/张开：量各指到质心的半径变化。
@interface TGPinchRecognizer : UIGestureRecognizer
@property (nonatomic) NSUInteger fingers;
@property (nonatomic) NSInteger desiredDirection; // -1 只认捏合，+1 只认张开
@property (nonatomic) NSInteger direction;
@property (nonatomic) CGFloat scale;
@property (nonatomic) CGFloat initialRadius;
@property (nonatomic) BOOL didFreeze;
@end

@implementation TGPinchRecognizer
- (CGFloat)radiusForTouches:(NSSet<UITouch *> *)touches {
    return TGMultiRadiusForTouches(touches, self.view);
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    TGMultiSnapshotBegan();
    if (event.allTouches.count > self.fingers) { self.state = UIGestureRecognizerStateFailed; return; }
    if (event.allTouches.count == self.fingers && self.initialRadius <= 0)
        self.initialRadius = [self radiusForTouches:event.allTouches];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.state != UIGestureRecognizerStatePossible) return;
    if (event.allTouches.count != self.fingers || self.initialRadius <= 0) return;
    CGFloat r = [self radiusForTouches:event.allTouches];
    if (r <= 0) return;
    self.scale = r / self.initialRadius;
    BOOL scaleMatches = (self.desiredDirection < 0) ? (self.scale < 0.95)
                      : (self.desiredDirection > 0) ? (self.scale > 1.05) : NO;
    if (!self.didFreeze && scaleMatches) { self.didFreeze = YES; TGMultiFreezeBegin(); }
    if (self.scale < 0.7 || self.scale > 1.4) {
        NSInteger d = self.scale < 0.7 ? -1 : 1;
        if (self.desiredDirection != d) { self.state = UIGestureRecognizerStateFailed; return; }
        self.direction = d;
        self.state = UIGestureRecognizerStateEnded;
    }
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.state == UIGestureRecognizerStatePossible) self.state = UIGestureRecognizerStateFailed;
    if (TGMultiTouchesFinished(event)) TGMultiFreezeEnd();
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.state == UIGestureRecognizerStatePossible) self.state = UIGestureRecognizerStateFailed;
    if (TGMultiTouchesFinished(event)) TGMultiFreezeEnd();
}
- (void)reset {
    [super reset];
    self.direction = 0; self.scale = 1; self.initialRadius = 0; self.didFreeze = NO;
}
@end

// 多指轻扫：位移矢量拆成平移分量 c 与偏差分量 e，保证捏合不误冻。
static const CGFloat TGSwipePanLimit = 16.0;
static const CGFloat TGSwipeSpreadLimit = 5.0;
static const CGFloat TGSwipeAxisDominance = 0.82;
static BOOL TGSwipeDirectionMatches(CGPoint c, UISwipeGestureRecognizerDirection dir) {
    CGFloat ax = fabs(c.x), ay = fabs(c.y);
    CGFloat len = hypot(ax, ay);
    if (len <= 0) return NO;
    BOOL vertical = ay >= ax;
    if (vertical ? (ay < len * TGSwipeAxisDominance) : (ax < len * TGSwipeAxisDominance)) return NO;
    if (dir & UISwipeGestureRecognizerDirectionUp)    return vertical && c.y < 0;
    if (dir & UISwipeGestureRecognizerDirectionDown)  return vertical && c.y > 0;
    if (dir & UISwipeGestureRecognizerDirectionLeft)  return !vertical && c.x < 0;
    if (dir & UISwipeGestureRecognizerDirectionRight) return !vertical && c.x > 0;
    return NO;
}
@interface TGSwipeRecognizer : UISwipeGestureRecognizer
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSValue *> *origins;
@property (nonatomic) BOOL didFreeze;
@end
@implementation TGSwipeRecognizer
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    TGMultiSnapshotBegan();
    NSUInteger n = event.allTouches.count;
    if (n > self.numberOfTouchesRequired) {
        if (self.didFreeze) TGMultiFreezeEnd();
        self.state = UIGestureRecognizerStateFailed;
        return;
    }
    if (n == self.numberOfTouchesRequired && !self.origins) {
        self.origins = [NSMutableDictionary dictionary];
        for (UITouch *t in event.allTouches)
            self.origins[@(t.hash)] = [NSValue valueWithCGPoint:[t locationInView:self.view]];
    }
    [super touchesBegan:touches withEvent:event];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!self.didFreeze && self.state == UIGestureRecognizerStatePossible &&
        self.origins.count == self.numberOfTouchesRequired &&
        event.allTouches.count == self.numberOfTouchesRequired) {
        NSUInteger n = 0;
        CGPoint sum = CGPointZero;
        CGPoint d[4];
        for (UITouch *t in event.allTouches) {
            NSValue *v = self.origins[@(t.hash)];
            if (!v) { n = 0; break; }
            CGPoint o = v.CGPointValue, p = [t locationInView:self.view];
            d[n].x = p.x - o.x; d[n].y = p.y - o.y;
            sum.x += d[n].x; sum.y += d[n].y;
            n++;
        }
        if (n == self.numberOfTouchesRequired) {
            CGPoint c = { sum.x / n, sum.y / n };
            CGFloat spread = 0;
            for (NSUInteger i = 0; i < n; i++) {
                CGFloat ex = d[i].x - c.x, ey = d[i].y - c.y;
                spread = MAX(spread, hypot(ex, ey));
            }
            if (hypot(c.x, c.y) > TGSwipePanLimit && spread <= TGSwipeSpreadLimit &&
                TGSwipeDirectionMatches(c, self.direction)) {
                self.didFreeze = YES;
                TGMultiFreezeBegin();
            }
        }
    }
    [super touchesMoved:touches withEvent:event];
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    if (TGMultiTouchesFinished(event)) TGMultiFreezeEnd();
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    if (TGMultiTouchesFinished(event)) TGMultiFreezeEnd();
}
- (void)reset {
    [super reset];
    self.origins = nil; self.didFreeze = NO;
}
@end

// 多指轻点：自己按位移判定，不依赖别的识别器。
static const CGFloat TGTapMoveLimit = 10.0;
@interface TGTapRecognizer : UIGestureRecognizer
@property (nonatomic) NSUInteger fingers;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSValue *> *origins;
@end
@implementation TGTapRecognizer
- (BOOL)movedTooFar:(NSSet<UITouch *> *)touches {
    for (UITouch *t in touches) {
        NSValue *v = self.origins[@(t.hash)];
        if (!v) continue;
        CGPoint o = v.CGPointValue, p = [t locationInView:self.view];
        if (hypot(p.x - o.x, p.y - o.y) > TGTapMoveLimit) return YES;
    }
    return NO;
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    TGMultiSnapshotBegan();
    NSUInteger n = event.allTouches.count;
    if (n > self.fingers) { self.state = UIGestureRecognizerStateFailed; return; }
    if (n != self.fingers) return;
    self.origins = [NSMutableDictionary dictionary];
    for (UITouch *t in event.allTouches)
        self.origins[@(t.hash)] = [NSValue valueWithCGPoint:[t locationInView:self.view]];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.state != UIGestureRecognizerStatePossible) return;
    if ([self movedTooFar:event.allTouches]) self.state = UIGestureRecognizerStateFailed;
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.state != UIGestureRecognizerStatePossible) return;
    if (self.origins.count != self.fingers) { self.state = UIGestureRecognizerStateFailed; return; }
    self.state = [self movedTooFar:event.allTouches] ? UIGestureRecognizerStateFailed : UIGestureRecognizerStateEnded;
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.state == UIGestureRecognizerStatePossible) self.state = UIGestureRecognizerStateFailed;
}
- (void)reset {
    [super reset];
    self.origins = nil;
}
@end

@interface TGMultiTouchTarget : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (UIGestureRecognizer *)recognizerFor:(int)idx;
- (void)recognized:(UIGestureRecognizer *)g;
@end
static const void *TGMultiIndexKey = &TGMultiIndexKey;
@implementation TGMultiTouchTarget
+ (instancetype)shared {
    static TGMultiTouchTarget *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [self new]; });
    return s;
}
- (UIGestureRecognizer *)recognizerFor:(int)idx {
    UIGestureRecognizer *g = nil;
    TGGestureSlot slot = kTGSlots[idx];
    if (slot.kind >= 5) {
        TGPinchRecognizer *p = [[TGPinchRecognizer alloc] initWithTarget:self action:@selector(recognized:)];
        p.fingers = slot.fingers;
        p.desiredDirection = slot.kind == 5 ? -1 : 1;
        g = p;
    } else if (slot.kind == 0) {
        TGTapRecognizer *t = [[TGTapRecognizer alloc] initWithTarget:self action:@selector(recognized:)];
        t.fingers = slot.fingers;
        g = t;
    } else {
        TGSwipeRecognizer *s = [[TGSwipeRecognizer alloc] initWithTarget:self action:@selector(recognized:)];
        s.numberOfTouchesRequired = slot.fingers;
        s.direction = (slot.kind == 1) ? UISwipeGestureRecognizerDirectionUp
                   : (slot.kind == 2) ? UISwipeGestureRecognizerDirectionDown
                   : (slot.kind == 3) ? UISwipeGestureRecognizerDirectionLeft
                                      : UISwipeGestureRecognizerDirectionRight;
        g = s;
    }
    g.delegate = self;
    g.cancelsTouchesInView = NO;
    g.delaysTouchesBegan = NO;
    g.delaysTouchesEnded = NO;
    objc_setAssociatedObject(g, TGMultiIndexKey, @(idx), OBJC_ASSOCIATION_RETAIN);
    return g;
}
- (void)recognized:(UIGestureRecognizer *)g {
    NSNumber *idxN = objc_getAssociatedObject(g, TGMultiIndexKey);
    int idx = idxN ? idxN.intValue : -1;
    if (idx < 0 || idx >= TG_SLOT_COUNT) return;
    if (g.state != UIGestureRecognizerStateEnded) return;
    if (kTGSlots[idx].kind >= 5 && [(TGPinchRecognizer *)g direction] == 0) return;
    TGFire(TGSlotGestureId(idx));
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        TGMultiFreezeEnd();
    });
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    NSNumber *idxN = objc_getAssociatedObject(g, TGMultiIndexKey);
    if (!idxN) return NO;
    int idx = idxN.intValue;
    if (idx < 0 || idx >= TG_SLOT_COUNT) return NO;
    return TGIsEnabled(TGSlotGestureId(idx));
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}
@end

static NSMutableArray<UIGestureRecognizer *> *tgMultiRecognizers;
static void TGUpdateMultiTouchGestures(SBSystemGestureManager *manager) {
    if (!manager) return;
    if (!tgMultiRecognizers) tgMultiRecognizers = [NSMutableArray array];
    TGMultiTouchTarget *target = [TGMultiTouchTarget shared];
    for (int idx = 0; idx < TG_SLOT_COUNT; idx++) {
        NSString *trigger = TGSlotGestureId(idx);
        BOOL want = TGIsEnabled(trigger);
        UIGestureRecognizer *existing = nil;
        for (UIGestureRecognizer *r in tgMultiRecognizers)
            if ([objc_getAssociatedObject(r, TGMultiIndexKey) intValue] == idx) { existing = r; break; }
        if (want && !existing) {
            UIGestureRecognizer *r = [target recognizerFor:idx];
            [manager addGestureRecognizer:r withType:TGMultiTypeBase + idx];
            [tgMultiRecognizers addObject:r];
        } else if (!want && existing) {
            [manager removeGestureRecognizer:existing];
            [tgMultiRecognizers removeObject:existing];
        }
    }
}

#pragma mark - Edge slide-ins (2 gestures)

static const CGFloat TGEdgeMargin = 20;
static const CGFloat TGEdgeDistance = 60;

// 从左侧滑入走普通 pan（保留系统原生返回）；从右侧滑入走系统级 screen-edge pan。
@interface TGGLeftPanRecognizer : UIPanGestureRecognizer
@property (nonatomic) BOOL fired;
@end
@implementation TGGLeftPanRecognizer
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (event.allTouches.count != 1) { self.state = UIGestureRecognizerStateFailed; return; }
    self.fired = NO;
    UITouch *touch = [touches anyObject];
    CGPoint p = [touch locationInView:nil];
    if (p.x > TGEdgeMargin || !TGIsEnabled(@"edge.left")) {
        self.state = UIGestureRecognizerStateFailed;
        return;
    }
    [super touchesBegan:touches withEvent:event];
}
@end

@interface TGGRightEdgeRecognizer : UIScreenEdgePanGestureRecognizer
@property (nonatomic) BOOL fired;
@end
@implementation TGGRightEdgeRecognizer
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    if (event.allTouches.count > 1) { self.state = UIGestureRecognizerStateFailed; return; }
    self.fired = NO;
    if (!TGIsEnabled(@"edge.right")) { self.state = UIGestureRecognizerStateFailed; return; }
}
@end

@interface TGGEdgeTarget : NSObject
@end
@implementation TGGEdgeTarget
- (void)slidLeft:(TGGLeftPanRecognizer *)recognizer {
    if (recognizer.fired) return;
    if (recognizer.state != UIGestureRecognizerStateChanged && recognizer.state != UIGestureRecognizerStateEnded) return;
    CGPoint t = [recognizer translationInView:nil];
    if (t.x < TGEdgeDistance || fabs(t.y) > t.x) return;
    recognizer.fired = YES;
    TGFire(@"edge.left");
}
- (void)slidRight:(TGGRightEdgeRecognizer *)recognizer {
    if (recognizer.fired) return;
    if (recognizer.state != UIGestureRecognizerStateChanged && recognizer.state != UIGestureRecognizerStateEnded) return;
    CGPoint t = [recognizer translationInView:nil];
    if (-t.x < TGEdgeDistance || fabs(t.y) > -t.x) return;
    recognizer.fired = YES;
    TGFire(@"edge.right");
}
@end

static TGGLeftPanRecognizer *tgLeftPan;
static TGGRightEdgeRecognizer *tgRightEdge;
static BOOL tgGestureManagerReady;

static void TGUpdateEdgeGestures(void) {
    if (!tgGestureManagerReady) return;
    SBSystemGestureManager *manager = [objc_getClass("SBSystemGestureManager") mainDisplayManager];
    if (!manager) return;
    static TGGEdgeTarget *target;
    if (!target) target = [TGGEdgeTarget new];

    // 左缘：普通 pan，不参与系统返回仲裁、cancelsTouchesInView=NO。
    if (TGIsEnabled(@"edge.left")) {
        if (!tgLeftPan) {
            tgLeftPan = [[TGGLeftPanRecognizer alloc] initWithTarget:target action:@selector(slidLeft:)];
            tgLeftPan.cancelsTouchesInView = NO;
            tgLeftPan.delaysTouchesBegan = NO;
            tgLeftPan.delaysTouchesEnded = NO;
            [manager addGestureRecognizer:tgLeftPan withType:TGBGestureTypeBase];
        }
    } else if (tgLeftPan) {
        [manager removeGestureRecognizer:tgLeftPan];
        tgLeftPan = nil;
    }

    // 右缘：系统级 screen-edge pan，识别到从源头取消 App 触摸。
    if (TGIsEnabled(@"edge.right")) {
        if (!tgRightEdge) {
            tgRightEdge = [[TGGRightEdgeRecognizer alloc] initWithTarget:target action:@selector(slidRight:)];
            tgRightEdge.edges = UIRectEdgeRight;
            tgRightEdge.cancelsTouchesInView = YES;
            tgRightEdge.delaysTouchesBegan = NO;
            tgRightEdge.delaysTouchesEnded = NO;
            [manager addGestureRecognizer:tgRightEdge withType:TGBGestureTypeBase + 1];
        }
    } else if (tgRightEdge) {
        [manager removeGestureRecognizer:tgRightEdge];
        tgRightEdge = nil;
    }

    TGUpdateMultiTouchGestures(manager);
}

#pragma mark - System gesture manager hooks

%hook SBMainDisplaySystemGestureManager
- (id)_init {
    id manager = %orig;
    tgGestureManagerReady = YES;
    dispatch_async(dispatch_get_main_queue(), ^{ TGUpdateEdgeGestures(); });
    return manager;
}
%end

%hook SBSystemGestureManager
- (BOOL)_isGestureWithTypeAllowed:(unsigned long long)type {
    if (type >= TGBGestureTypeBase && type < TGBGestureTypeBase + 32) return YES;
    return %orig;
}
- (BOOL)_shouldEnableSystemGestureWithType:(unsigned long long)type {
    if (type >= TGBGestureTypeBase && type < TGBGestureTypeBase + 32) return YES;
    return %orig;
}
%end

#pragma mark - Constructor

%ctor {
    TGReadPrefs();
    int token;
    notify_register_dispatch(TGBridgeReloadNotify, &token, dispatch_get_main_queue(), ^(int t) {
        TGReadPrefs();
        tgGestureManagerReady = NO; // force re-arm below
        tgGestureManagerReady = YES;
        TGUpdateEdgeGestures();
    });
}
