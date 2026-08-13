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
        if (@available(iOS 26.0, *)) {
            available = YES;
        } else {
            available = NO;
        }
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
