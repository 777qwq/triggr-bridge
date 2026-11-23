// TriggrBridge · RC — SpringBoard side.
//
// Recognizes the 16 gestures RemoteCompanion does not natively have and posts one
// Darwin notification per gesture (com.johndie.triggrbridge/<gesture id>). The RC
// Add-on JSON listens on those names and exposes them as triggers; the user
// assigns RC actions there. This tweak performs no action itself.
//
// Edge recognizers are ported from Triggr cn5.3.33 (the current version):
//   - left slide-in: plain UIPanGestureRecognizer in visual coordinates, keeps
//     the system's native back-swipe.
//   - right slide-in: system-level UIScreenEdgePanRecognizer, freezes/rebounds
//     on Began, fires at 50pt on lift (cn5.3.30/31).
// Multi-touch recognizers are ported from Triggr's tuned implementation.
//
// No settings panel: every gesture is always on. Enable/disable is done on the
// RC Add-on's triggers. All recognizers declare shouldRecognizeSimultaneously=YES
// so they coexist with RC's own edge recognizers on the same gesture manager.

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

// The whole "action": one notification. No shell, no app launch, no state.
static void TGFire(NSString *gestureId) {
    if (!gestureId) return;
    notify_post(TGBridgeNotification(gestureId).UTF8String);
}

#pragma mark - Freeze (port from Triggr cn5.3.33)

static void TGMultiFreezeBegin(void) { TGFreezeBegin(); notify_post(TGBridgeFreezeBegin); }
static void TGMultiFreezeEnd(void)   { TGFreezeEnd();   notify_post(TGBridgeFreezeEnd); }
static void TGMultiSnapshotBegan(void) {
    TGFreezeSnapshotBegan();
    notify_post(TGBridgeFreezeSnapshot);
}
static BOOL TGMultiTouchesFinished(UIEvent *event) {
    for (UITouch *touch in event.allTouches)
        if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled) return NO;
    return YES;
}

// Edge freeze (cn5.3.33): on Began, freeze and immediately rebound to the
//落指 snapshot; the Relay in each app does the same via FreezeBeginNow.
static void TGEdgeFreezeBegin(void) {
    TGFreezeBegin();
    TGFreezeRestoreNow();
    notify_post(TGBridgeFreezeBeginNow);
}
static void TGEdgeFreezeEnd(void) { TGFreezeEnd(); notify_post(TGBridgeFreezeEnd); }

#pragma mark - Visual coordinate space (cn5.3.33)
// SpringBoard's window does not rotate with the interface, so locationInView:nil
// is physical portrait coordinates. UIScreen.coordinateSpace rotates with the
// interface; fixedCoordinateSpace is device-fixed. All gesture judgements use
// the visual space so rotation needs no direction/edge remapping.

static CGSize TGVisualScreenSize(void) {
    UIScreen *screen = [UIScreen mainScreen];
    if (!screen) return CGSizeZero;
    CGSize size = screen.coordinateSpace.bounds.size;
    return (size.width > 0 && size.height > 0) ? size : screen.bounds.size;
}

static CGPoint TGVisualPointFromWindowPoint(CGPoint p, UIWindow *window) {
    UIScreen *screen = window.screen ?: [UIScreen mainScreen];
    if (!screen) return p;
    if (window) return [window convertPoint:p toCoordinateSpace:screen.coordinateSpace];
    return [screen.fixedCoordinateSpace convertPoint:p toCoordinateSpace:screen.coordinateSpace];
}

static UIWindow *TGVisualFallbackWindow(void) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows)
            if (w.isKeyWindow) return w;
    }
    return nil;
}

static CGPoint TGVisualPointForTouch(UITouch *touch) {
    UIWindow *window = touch.window ?: TGVisualFallbackWindow();
    if (!window) return [touch locationInView:nil];
    return TGVisualPointFromWindowPoint([touch locationInView:window], window);
}

static CGPoint TGVisualPointForGesture(UIGestureRecognizer *g) {
    UIWindow *window = g.view.window ?: TGVisualFallbackWindow();
    if (!window) return [g locationInView:nil];
    return TGVisualPointFromWindowPoint([g locationInView:nil], window);
}

static CGPoint TGVisualCentroidForTouches(NSSet<UITouch *> *touches) {
    CGPoint sum = CGPointZero;
    NSUInteger n = 0;
    for (UITouch *t in touches) {
        CGPoint p = TGVisualPointForTouch(t);
        sum.x += p.x; sum.y += p.y; n++;
    }
    return n ? CGPointMake(sum.x / n, sum.y / n) : CGPointZero;
}

#pragma mark - Multi-touch recognizers (14 gestures)

typedef struct { uint8_t fingers; uint8_t kind; } TGGestureSlot;
// kind: 0 点按, 1 上, 2 下, 3 左, 4 右, 5 捏合, 6 张开
static const TGGestureSlot kTGSlots[] = {
    {2, 0}, {2, 1}, {2, 2}, {2, 3}, {2, 4}, {2, 5}, {2, 6},
    {3, 0}, {3, 1}, {3, 2}, {3, 3}, {3, 4}, {3, 5}, {3, 6},
};
#define TG_SLOT_COUNT ((int)(sizeof(kTGSlots) / sizeof(kTGSlots[0])))
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
    return objc_getAssociatedObject(g, TGMultiIndexKey) != nil;
}
// Coexist with RC's recognizers on the same manager — the fix for the
// "RC edge swipe blocks bridge slide-in" bug.
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
        UIGestureRecognizer *existing = nil;
        for (UIGestureRecognizer *r in tgMultiRecognizers)
            if ([objc_getAssociatedObject(r, TGMultiIndexKey) intValue] == idx) { existing = r; break; }
        if (!existing) {
            UIGestureRecognizer *r = [target recognizerFor:idx];
            [manager addGestureRecognizer:r withType:TGMultiTypeBase + idx];
            [tgMultiRecognizers addObject:r];
        }
    }
}

#pragma mark - Edge slide-ins (cn5.3.33)

static const CGFloat TGEdgeMargin = 20;          // 左缘起手贴边宽度（视觉坐标）
static const CGFloat TGEdgeDistance = 60;        // 左侧普通 pan 的滑入距离
static const CGFloat TGSystemEdgeDistance = 50;  // cn5.3.31：右侧系统手势 50pt，抬手触发

// 左侧「从左侧滑入」：普通 UIPanGestureRecognizer，保留系统原生返回（cn5.3.33）。
@interface TGGPlainPanRecognizer : UIPanGestureRecognizer
@property (nonatomic) BOOL fired;
@property (nonatomic) CGPoint visualStart;
@property (nonatomic) BOOL hasVisualStart;
@end
@implementation TGGPlainPanRecognizer
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    NSUInteger n = event.allTouches.count;
    if (n == 1) { self.fired = NO; self.hasVisualStart = NO; }
    if (n > 1) { self.state = UIGestureRecognizerStateFailed; return; }
    CGPoint p = TGVisualCentroidForTouches(event.allTouches);
    if (p.x > TGEdgeMargin) { self.state = UIGestureRecognizerStateFailed; return; }
    self.visualStart = p;
    self.hasVisualStart = YES;
    [super touchesBegan:touches withEvent:event];
}
- (void)reset {
    [super reset];
    self.fired = NO;
    self.hasVisualStart = NO;
}
@end

// 右侧「从右侧滑入」：系统级 UIScreenEdgePanGestureRecognizer（cn5.3.28+）。
// SpringBoard 事件路由层优先认领，App 内容不再跟着滚；Began 时冻结并回弹到落指快照，
// 抬手/取消解冻（cn5.3.30）。只认单指。
@interface TGGSystemEdgeRecognizer : UIScreenEdgePanGestureRecognizer
@property (nonatomic) BOOL fired;
@property (nonatomic) BOOL frozen;
@property (nonatomic) CGPoint visualStart;
@property (nonatomic) BOOL hasVisualStart;
@end
@implementation TGGSystemEdgeRecognizer
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    NSUInteger n = event.allTouches.count;
    if (n == 0 || n > 1) { self.state = UIGestureRecognizerStateFailed; return; }
    self.fired = NO;
    self.frozen = NO;
    self.visualStart = TGVisualCentroidForTouches(event.allTouches);
    self.hasVisualStart = YES;
    TGMultiSnapshotBegan();
    [super touchesBegan:touches withEvent:event];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesMoved:touches withEvent:event];
    if (self.state == UIGestureRecognizerStateBegan && !self.frozen) {
        self.frozen = YES;
        TGEdgeFreezeBegin();
    }
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    if (self.frozen) { self.frozen = NO; TGEdgeFreezeEnd(); }
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    if (self.frozen) { self.frozen = NO; TGEdgeFreezeEnd(); }
}
- (void)reset {
    [super reset];
    self.fired = NO;
    self.hasVisualStart = NO;
    if (self.frozen) { self.frozen = NO; TGEdgeFreezeEnd(); }
}
@end

@interface TGGEdgeTarget : NSObject <UIGestureRecognizerDelegate>
@end
@implementation TGGEdgeTarget
- (void)slidLeft:(TGGPlainPanRecognizer *)recognizer {
    if (recognizer.fired) return;
    if (recognizer.state != UIGestureRecognizerStateChanged && recognizer.state != UIGestureRecognizerStateEnded) return;
    if (!recognizer.hasVisualStart) return;
    CGPoint now = TGVisualPointForGesture(recognizer);
    CGFloat dx = now.x - recognizer.visualStart.x;
    CGFloat dy = now.y - recognizer.visualStart.y;
    if (dx < TGEdgeDistance || fabs(dy) > dx) return;
    recognizer.fired = YES;
    TGFire(@"edge.left");
}
- (void)slidRight:(TGGSystemEdgeRecognizer *)recognizer {
    if (recognizer.fired) return;
    // cn5.3.31：只在手指离开时触发；拖动过程中不 fire。
    if (recognizer.state != UIGestureRecognizerStateEnded) return;
    if (!recognizer.hasVisualStart) return;
    CGPoint now = TGVisualPointForGesture(recognizer);
    CGFloat inward = recognizer.visualStart.x - now.x; // 视觉右边缘往左滑
    CGFloat dy = now.y - recognizer.visualStart.y;
    if (inward < TGSystemEdgeDistance || fabs(dy) > inward) return;
    recognizer.fired = YES;
    TGFire(@"edge.right");
}
// Coexist with RC's own edge recognizers on the same manager.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}
@end

// 视觉右边缘在物理屏上对应哪条边（横屏时可能是物理上/下边）。
static UIRectEdge TGGSystemEdgeForVisualRight(void) {
    UIScreen *screen = [UIScreen mainScreen];
    if (!screen) return UIRectEdgeRight;
    CGSize visual = TGVisualScreenSize();
    CGSize fixed = screen.fixedCoordinateSpace.bounds.size;
    if (visual.width <= 0 || visual.height <= 0 || fixed.width <= 0 || fixed.height <= 0)
        return UIRectEdgeRight;
    CGPoint p = [screen.coordinateSpace convertPoint:CGPointMake(visual.width - 1, visual.height / 2)
                                  toCoordinateSpace:screen.fixedCoordinateSpace];
    CGFloat left = p.x, right = fixed.width - p.x, top = p.y, bottom = fixed.height - p.y;
    CGFloat minD = left;
    UIRectEdge edge = UIRectEdgeLeft;
    if (right < minD) { minD = right; edge = UIRectEdgeRight; }
    if (top < minD) { minD = top; edge = UIRectEdgeTop; }
    if (bottom < minD) { edge = UIRectEdgeBottom; }
    return edge;
}

static TGGPlainPanRecognizer *tgLeftPan;
static TGGSystemEdgeRecognizer *tgRightEdge;
static BOOL tgGestureManagerReady;
static BOOL tgEdgeOrientationObserved;

static void TGUpdateEdgeGestures(void) {
    if (!tgGestureManagerReady) return;
    SBSystemGestureManager *manager = [objc_getClass("SBSystemGestureManager") mainDisplayManager];
    if (!manager) return;
    static TGGEdgeTarget *target;
    if (!target) target = [TGGEdgeTarget new];
    if (!tgEdgeOrientationObserved) {
        tgEdgeOrientationObserved = YES;
        [NSNotificationCenter.defaultCenter addObserverForName:UIDeviceOrientationDidChangeNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(NSNotification *n) {
            TGUpdateEdgeGestures();
        }];
    }

    // 左侧：普通 pan，保留原生返回，delegate 允许与 RC 识别器同时识别。
    if (!tgLeftPan) {
        tgLeftPan = [[TGGPlainPanRecognizer alloc] initWithTarget:target action:@selector(slidLeft:)];
        tgLeftPan.delegate = target;
        tgLeftPan.cancelsTouchesInView = NO;
        tgLeftPan.delaysTouchesBegan = NO;
        tgLeftPan.delaysTouchesEnded = NO;
        [manager addGestureRecognizer:tgLeftPan withType:TGBGestureTypeBase];
    }

    // 右侧：系统级 screen-edge pan，delegate 允许与 RC 识别器同时识别。
    UIRectEdge physicalRight = TGGSystemEdgeForVisualRight();
    if (!tgRightEdge) {
        tgRightEdge = [[TGGSystemEdgeRecognizer alloc] initWithTarget:target action:@selector(slidRight:)];
        tgRightEdge.delegate = target;
        tgRightEdge.edges = physicalRight;
        tgRightEdge.minimumNumberOfTouches = 1;
        tgRightEdge.maximumNumberOfTouches = 1;
        tgRightEdge.cancelsTouchesInView = YES;
        tgRightEdge.delaysTouchesBegan = NO;
        tgRightEdge.delaysTouchesEnded = NO;
        [manager addGestureRecognizer:tgRightEdge withType:TGBGestureTypeBase + 1];
    } else {
        tgRightEdge.edges = physicalRight; // 旋转后更新物理边
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
    TGUpdateEdgeGestures();
}
