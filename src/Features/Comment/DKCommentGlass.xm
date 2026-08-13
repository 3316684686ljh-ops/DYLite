//
//  DKCommentGlass.xm
//  评论区液态玻璃：给评论面板和输入框加上 iOS 26 原生 UIGlassEffect
//
//  核心思路：
//  1. 钩 AWECommentContainerViewController 的 viewDidAppear，找到面板的背景层槽位
//  2. 在槽位最底层插入 UIVisualEffectView（glassEffect = Clear/Regular）
//  3. 输入框同理，跟随尺寸变化
//  4. 深浅色从 UIWindowScene trait 取，因为抖音把 override 钉死为浅色
//

#import "DKCommentGlass.h"
#import "DouyinHeaders.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#pragma mark - 状态

static __weak UIView *gCurrentSlot = nil;
static __weak UIView *gCurrentField = nil;
static UIVisualEffectView *gSlotGlass = nil;
static UIVisualEffectView *gFieldGlass = nil;
static __weak UIWindowScene *gObservedScene = nil;
static UIUserInterfaceStyle gGlassStyle = UIUserInterfaceStyleUnspecified;

UIView *DKCommentGlassCurrentSlot(void) { return gCurrentSlot; }
UIView *DKCommentGlassCurrentField(void) { return gCurrentField; }

#pragma mark - 开关

static BOOL DKCommentGlassEnabled(void) {
    return DKGlassOSAvailable() && DKPrefBool(DKKeyCommentGlass);
}

static BOOL DKCommentGlassUsesClear(void) {
    return DKGlassOSAvailable() && DKPrefBool(DKKeyCommentGlassClear);
}

#pragma mark - 玻璃材质

static UIGlassEffect *DKMakeGlassEffect(UIUserInterfaceStyle style, BOOL interactive)
    API_AVAILABLE(ios(26.0)) {
    BOOL clear = DKCommentGlassUsesClear();
    UIGlassEffect *effect = [UIGlassEffect effectWithStyle:
        clear ? UIGlassEffectStyleClear : UIGlassEffectStyleRegular];
    if (clear) effect.tintColor = DKGlassTintForStyle(style);
    effect.interactive = interactive;
    return effect;
}

#pragma mark - 深浅色

static void DKApplyGlassStyle(UIUserInterfaceStyle style) API_AVAILABLE(ios(26.0)) {
    if (style == UIUserInterfaceStyleUnspecified || style == gGlassStyle) return;
    gGlassStyle = style;

    if (gSlotGlass) {
        gSlotGlass.overrideUserInterfaceStyle = style;
        gSlotGlass.effect = DKMakeGlassEffect(style, YES);
    }
    if (gFieldGlass) {
        gFieldGlass.overrideUserInterfaceStyle = style;
        gFieldGlass.effect = DKMakeGlassEffect(style, NO);
    }
}

static void DKObserveStyle(UIView *host) API_AVAILABLE(ios(26.0)) {
    UIWindowScene *scene = host.window.windowScene;
    if (!scene || scene == gObservedScene) return;
    gObservedScene = scene;
    [scene registerForTraitChanges:@[ UITraitUserInterfaceStyle.class ]
                       withHandler:^(UIWindowScene *changed, __unused UITraitCollection *previous) {
        DKApplyGlassStyle(changed.traitCollection.userInterfaceStyle);
    }];
}

#pragma mark - 玻璃安装/拆除

// 找一个视图里最底层的模糊/背景层，返回它的父视图（即玻璃要插入的槽位）
static UIView *DKFindBackdropSlot(UIView *root) {
    if (!root) return nil;
    // 找第一个背景层（blur/纯色背景）的父视图
    for (UIView *sub in root.subviews) {
        if ([sub isKindOfClass:UIVisualEffectView.class] ||
            [NSStringFromClass(sub.class) containsString:@"Blur"] ||
            [NSStringFromClass(sub.class) containsString:@"Backdrop"] ||
            [NSStringFromClass(sub.class) containsString:@"Background"]) {
            return root;
        }
    }
    // 如果子视图里找不到，继续深挖第一个子视图
    if (root.subviews.count > 0) {
        return DKFindBackdropSlot(root.subviews.firstObject);
    }
    return root;
}

static void DKInstallGlassOnSlot(UIView *slot, UIVisualEffectView **glassOut, BOOL interactive)
    API_AVAILABLE(ios(26.0)) {
    if (!slot || !glassOut) return;

    // 移除旧玻璃
    if (*glassOut) {
        [*glassOut removeFromSuperview];
        *glassOut = nil;
    }

    if (!DKCommentGlassEnabled()) return;

    UIVisualEffectView *glass =
        [[UIVisualEffectView alloc] initWithEffect:DKMakeGlassEffect(gGlassStyle, interactive)];
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    glass.frame = slot.bounds;
    [slot insertSubview:glass atIndex:0];   // 最底层，在所有内容之下

    // 把原来的背景层 opacity=0（如果存在）
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

static void DKRemoveGlassFromSlot(UIView *slot, UIVisualEffectView **glassOut) {
    if (!glassOut || !*glassOut) return;
    UIVisualEffectView *glass = *glassOut;

    // 还原原来的背景层 opacity
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

#pragma mark - 更新入口

static void DKCommentGlassUpdate(id controller) API_AVAILABLE(ios(26.0)) {
    if (![controller isKindOfClass:UIViewController.class]) return;
    UIViewController *vc = controller;

    UIView *rootView = vc.view;
    if (!rootView) return;

    DKObserveStyle(rootView);
    DKApplyGlassStyle(rootView.window.windowScene.traitCollection.userInterfaceStyle);

    if (!DKCommentGlassEnabled()) {
        // 关开关：拆除玻璃
        if (gSlotGlass) DKRemoveGlassFromSlot(gCurrentSlot, &gSlotGlass);
        if (gFieldGlass) DKRemoveGlassFromSlot(gCurrentField, &gFieldGlass);
        gCurrentSlot = nil;
        gCurrentField = nil;
        return;
    }

    // 1. 评论主面板
    UIView *slot = DKFindBackdropSlot(rootView);
    if (slot && slot != gCurrentSlot) {
        DKRemoveGlassFromSlot(gCurrentSlot, &gSlotGlass);
        DKInstallGlassOnSlot(slot, &gSlotGlass, YES);
        gCurrentSlot = slot;
    } else if (slot && gSlotGlass) {
        // 尺寸跟随
        if (!CGRectEqualToRect(gSlotGlass.frame, slot.bounds)) {
            gSlotGlass.frame = slot.bounds;
        }
    }

    // 2. 输入框：子视图树里找 AWECommentInputBackgroundView
    for (UIView *sub in rootView.subviews) {
        if ([NSStringFromClass(sub.class) isEqualToString:@"AWECommentInputBackgroundView"]) {
            if (sub != gCurrentField) {
                DKRemoveGlassFromSlot(gCurrentField, &gFieldGlass);
                DKInstallGlassOnSlot(sub, &gFieldGlass, NO);
                gCurrentField = sub;
            } else if (gFieldGlass) {
                if (!CGRectEqualToRect(gFieldGlass.frame, sub.bounds)) {
                    gFieldGlass.frame = sub.bounds;
                }
            }
            break;
        }
    }
}

#pragma mark - Hook

%group DKCommentGlassHooks

%hook AWECommentContainerViewController

- (void)viewDidLayoutSubviews {
    %orig;
    if (@available(iOS 26.0, *)) DKCommentGlassUpdate(self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (@available(iOS 26.0, *)) DKCommentGlassUpdate(self);
}

%end

%end

#pragma mark - 设置项注册

%ctor {
    DKSettingsRegisterItem(@"评论区", ^AWESettingItemModel *{
        return DKMakeSwitch(
            DKKeyCommentGlass,
            @"评论区液态玻璃",
            @"给评论面板加上 iOS 26 原生液态玻璃效果"
        );
    });

    DKSettingsRegisterItem(@"评论区", ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(
            DKKeyCommentGlassClear,
            @"清透玻璃",
            @"开启后使用清透玻璃（细节可辨），关闭则使用系统默认磨砂材质"
        );
        // 开关变化时立即刷新
        void (^origBlock)(void) = [item.switchChangedBlock copy];
        item.switchChangedBlock = ^{
            if (origBlock) origBlock();
            if (@available(iOS 26.0, *)) {
                gGlassStyle = UIUserInterfaceStyleUnspecified;
            }
        };
        return item;
    });

    if (DKGlassOSAvailable()) {
        %init(DKCommentGlassHooks);
    }
}
