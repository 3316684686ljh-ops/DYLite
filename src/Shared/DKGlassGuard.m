//
//  DKGlassGuard.m
//

#import "DKGlassGuard.h"
#import "DKKeys.h"

static NSSet<NSString *> *DKGlassGatedKeySet(void) {
    static NSSet<NSString *> *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSSet setWithObjects:
               DKKeyCommentGlass,
               DKKeyCommentGlassClear,
               DKKeySharePanelGlass,
               DKKeySharePanelGlassClear,
               nil];
    });
    return set;
}

BOOL DKGlassOSAvailable(void) {
    static BOOL available;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // 运行时比较系统版本，避免旧 SDK 下 @available(iOS 26.0, *) 报 warning
        NSOperatingSystemVersion os26 = (NSOperatingSystemVersion){26, 0, 0};
        available = [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:os26];
    });
    return available;
}

BOOL DKGlassIsGatedKey(NSString *key) {
    return key.length && [DKGlassGatedKeySet() containsObject:key];
}

// 低系统清掉旧版留下的开值
static void DKGlassResetPrefsIfUnsupported(void) {
    if (DKGlassOSAvailable()) return;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    for (NSString *key in DKGlassGatedKeySet()) {
        [defaults removeObjectForKey:key];
    }
    [defaults synchronize];
}

__attribute__((constructor))
static void DKGlassGuardCtor(void) {
    DKGlassResetPrefsIfUnsupported();
}
