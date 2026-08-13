//
//  DKUtils.m
//

#import "DKUtils.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DouyinHeaders.h"

BOOL DKPrefBool(NSString *key) {
    if (DKGlassIsGatedKey(key) && !DKGlassOSAvailable()) return NO;
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

#pragma mark - 控制器查找

static UIViewController *DKSearchChildController(UIViewController *controller, NSString *className, NSUInteger depth) {
    if (!controller || depth > 12) return nil;
    for (UIViewController *child in controller.childViewControllers) {
        if ([NSStringFromClass(child.class) isEqualToString:className]) return child;
        UIViewController *match = DKSearchChildController(child, className, depth + 1);
        if (match) return match;
    }
    return nil;
}

UIViewController *DKChildControllerNamed(UIViewController *controller, NSString *className) {
    return DKSearchChildController(controller, className, 0);
}

#pragma mark - 液态玻璃染色

static const CGFloat kDKGlassDarkTintAlpha = 0.30;

UIColor *DKGlassTintForStyle(UIUserInterfaceStyle style) {
    if (style != UIUserInterfaceStyleDark) return nil;
    return [UIColor colorWithWhite:0.0 alpha:kDKGlassDarkTintAlpha];
}

#pragma mark - Cell 几何

UIView *DKCellContentView(UIView *view) {
    static Class contentCls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ contentCls = NSClassFromString(@"UITableViewCellContentView"); });
    if (!contentCls) return nil;

    for (NSUInteger i = 0; view && i < 12; i++) {
        if ([view isKindOfClass:contentCls]) return view;
        view = view.superview;
    }
    return nil;
}

CGFloat DKFullCellHeight(UIView *view) {
    UIView *contentView = DKCellContentView(view.superview);
    return contentView ? CGRectGetHeight(contentView.bounds) : 0.0;
}
