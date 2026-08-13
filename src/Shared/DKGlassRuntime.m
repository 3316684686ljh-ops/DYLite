//
//  DKGlassRuntime.m
//  运行时反射实现：用 NSClassFromString / KVC 访问 iOS 26 UIGlassEffect
//  编译期链接 iOS 17 SDK 也能过，运行期在 iOS 26 上才真正启用玻璃效果
//

#import "DKGlassRuntime.h"
#import "DKGlassGuard.h"
#import "DKUtils.h"
#import <objc/runtime.h>

id DKCreateGlassEffect(BOOL clearStyle, UIColor *tint, BOOL interactive) {
    if (!DKGlassOSAvailable()) return nil;

    Class glassClass = NSClassFromString(@"UIGlassEffect");
    if (!glassClass) return nil;

    SEL effectSel = @selector(effectWithStyle:);
    if (![glassClass respondsToSelector:effectSel]) return nil;

    NSInteger styleValue = clearStyle ? 1 : 0;

    id effect = ((id (*)(id, SEL, NSInteger))objc_msgSend)(glassClass, effectSel, styleValue);
    if (!effect) return nil;

    if (clearStyle && tint) {
        @try { [effect setValue:tint forKey:@"tintColor"]; } @catch (__unused NSException *e) {}
    }

    @try { [effect setValue:@(interactive) forKey:@"interactive"]; } @catch (__unused NSException *e) {}

    return effect;
}

void DKApplyGlassToView(UIVisualEffectView *view, BOOL clearStyle, UIColor *tint, BOOL interactive) {
    if (!view || !DKGlassOSAvailable()) return;

    id glassEffect = DKCreateGlassEffect(clearStyle, tint, interactive);
    if (!glassEffect) return;

    @try {
        [view setValue:glassEffect forKey:@"glassEffect"];
    } @catch (__unused NSException *e) {
        view.effect = glassEffect;
    }
}

void DKRemoveGlassFromView(UIVisualEffectView *view) {
    if (!view || !DKGlassOSAvailable()) return;
    @try { [view setValue:nil forKey:@"glassEffect"]; } @catch (__unused NSException *e) {}
}

void DKInstallGlassOnSlot(UIView *slot, UIVisualEffectView **glassOut, BOOL interactive) {
    if (!slot || !glassOut) return;

    if (*glassOut) {
        [*glassOut removeFromSuperview];
        *glassOut = nil;
    }

    if (!DKGlassOSAvailable()) return;

    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:nil];
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    glass.frame = slot.bounds;

    UIColor *tint = DKGlassTintForStyle(slot.traitCollection.userInterfaceStyle);
    DKApplyGlassToView(glass, YES, tint, interactive);

    [slot insertSubview:glass atIndex:0];

    for (UIView *sub in slot.subviews) {
        if (sub == glass) continue;
        if ([sub isKindOfClass:UIVisualEffectView.class] ||
            [NSStringFromClass(sub.class) containsString:@"Blur"] ||
            [NSStringFromClass(sub.class) containsString:@"Backdrop"]) {
            if (sub.layer.opacity != 0.0f) sub.layer.opacity = 0.0f;
        }
    }

    *glassOut = glass;
}

void DKRemoveGlassFromSlot(UIView *slot, UIVisualEffectView **glassOut) {
    if (!glassOut || !*glassOut) return;
    UIVisualEffectView *glass = *glassOut;

    UIView *parent = glass.superview;
    for (UIView *sub in parent.subviews) {
        if (sub == glass) continue;
        if ([sub isKindOfClass:UIVisualEffectView.class] ||
            [NSStringFromClass(sub.class) containsString:@"Blur"] ||
            [NSStringFromClass(sub.class) containsString:@"Backdrop"]) {
            if (sub.layer.opacity != 1.0f) sub.layer.opacity = 1.0f;
        }
    }
    [glass removeFromSuperview];
    *glassOut = nil;
}
