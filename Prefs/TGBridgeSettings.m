// TriggrBridge · RC — settings page.
// Master switch, freeze switch, and one switch per gesture. Writes straight to
// the preference domain the tweak reads, then posts the reload notification.

#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <notify.h>
#import "../Shared/TGBridge.h"

@interface TGBRootListController : PSListController
@end

@implementation TGBRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *s = [NSMutableArray array];

        PSSpecifier *master = [PSSpecifier preferenceSpecifierNamed:@"启用手势桥"
                                                             target:self
                                                                set:@selector(setValue:forSpecifier:)
                                                                get:@selector(getValueForSpecifier:)
                                                             detail:nil
                                                               cell:PSSwitchCell
                                                               edit:nil];
        [master setProperty:TGBridgeDomain forKey:@"defaults"];
        [master setProperty:TGBridgeMasterKey forKey:@"key"];
        [master setProperty:@YES forKey:@"default"];
        [s addObject:master];

        PSSpecifier *freeze = [PSSpecifier preferenceSpecifierNamed:@"手势时冻结画面"
                                                             target:self
                                                                set:@selector(setValue:forSpecifier:)
                                                                get:@selector(getValueForSpecifier:)
                                                             detail:nil
                                                               cell:PSSwitchCell
                                                               edit:nil];
        [freeze setProperty:TGBridgeDomain forKey:@"defaults"];
        [freeze setProperty:TGBridgeFreezeKey forKey:@"key"];
        [freeze setProperty:@YES forKey:@"default"];
        [freeze setProperty:@"多指滑动/捏合时钉住列表与照片，手势结束后还原。"
                    forKey:@"footerText"];
        [s addObject:freeze];

        // 分组 1：边缘手势
        [s addObject:[PSSpecifier groupSpecifierWithName:@"边缘手势"]];
        NSArray *ids = TGBridgeGestureIds();
        NSArray *names = TGBridgeGestureNames();
        for (int i = 0; i < 2; i++) [s addObject:[self switchSpecifierForId:ids[i] name:names[i]]];

        // 分组 2：双指手势
        [s addObject:[PSSpecifier groupSpecifierWithName:@"双指手势"]];
        for (int i = 2; i < 9; i++) [s addObject:[self switchSpecifierForId:ids[i] name:names[i]]];

        // 分组 3：三指手势
        [s addObject:[PSSpecifier groupSpecifierWithName:@"三指手势"]];
        for (int i = 9; i < 16; i++) [s addObject:[self switchSpecifierForId:ids[i] name:names[i]]];

        [s addObject:[PSSpecifier groupSpecifierWithName:@"说明"]];
        PSSpecifier *note = [PSSpecifier groupSpecifierWithName:
            @"每个开关对应 RemoteCompanion 里的一个「Add-on: …」触发器。\n"
            "在 RemoteCompanion 的触发器页面给它们指派动作即可。\n"
            "本插件不执行动作，只把手势通知发给 RC。"];
        [s addObject:note];

        _specifiers = s;
    }
    return _specifiers;
}

- (PSSpecifier *)switchSpecifierForId:(NSString *)gid name:(NSString *)name {
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:name
                                                       target:self
                                                          set:@selector(setValue:forSpecifier:)
                                                          get:@selector(getValueForSpecifier:)
                                                       detail:nil
                                                         cell:PSSwitchCell
                                                         edit:nil];
    [spec setProperty:TGBridgeDomain forKey:@"defaults"];
    [spec setProperty:gid forKey:@"key"];
    [spec setProperty:@YES forKey:@"default"];
    return spec;
}

// 直接读写偏好域，不经过 PSListController 默认的写盘路径，保证与 tweak 一致。
- (id)getValueForSpecifier:(PSSpecifier *)spec {
    NSString *key = [spec propertyForKey:@"key"];
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                           (__bridge CFStringRef)TGBridgeDomain));
    return value ?: [spec propertyForKey:@"default"];
}

- (void)setValue:(id)value forSpecifier:(PSSpecifier *)spec {
    NSString *key = [spec propertyForKey:@"key"];
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)TGBridgeDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)TGBridgeDomain);
    notify_post(TGBridgeReloadNotify);
}

@end
