//
//  DKSharePanelGlass.xm
//  分享面板液态玻璃：给抖音分享弹层加上 iOS 26 原生玻璃
//
//  思路：
//  1. 分享弹层由 AWESharePanelContainerViewController 控制
//  2. 内容层在 AWESharePanelViewController 的 view 里（DUXVisualEffectView 包装）
//  3. 找到弹层的背景槽位，替换成 UIGlassEffect
//
//  兼容性：全部用 runtime 反射 UIGlassEffect，兼容 SDK < iOS 26 编译
//

#import "DouyinHeaders.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>

#pragma mark - 状态

static __weak UIView *gCurrentPanelSlot = nil;
static UIVisualEffectView *gPanelGlass = nil;
static __weak UIWindowScene *gObservedScene = nil;
static UIUserInterfaceStyle gGlassStyle = UIUserInterfaceStyleUnspecified;

#pragma mark - 开关

static BOOL DKShareGlassEnabled(void) {
    return DKGlassOSAvailable() && DKPrefBool(DKKeySharePanelGlass);
}

static BOOL DKShareGlassUsesClear(void) {
    return DKGlassOSAvailable() && DKPrefBool(DKKeySharePanelGlassClear);
}

#pragma mark - UIGlassEffect 运行时封装

typedef NS_ENUM(NSInteger, DKShareGlassStyleRT) {
    DKShareGlassStyleRTClear   = 0,
    DKShareGlassStyleRTRegular = 1,
};

static Class DKShareGlassClass(void) {
    static Class cls = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cls = NSClassFromString(@"UIGlassEffect");
    });
    return cls;
}

static UIVisualEffect *DKShareMakeGlassEffect(UIUserInterfaceStyle style) {
    Class cls = DKShareGlassClass();
    if (!cls) return nil;

    DKShareGlassStyleRT s = DKShareGlassUsesClear()
        ? DKShareGlassStyleRTClear
        : DKShareGlassStyleRTRegular;

    id (*msgSend)(id, SEL, NSInteger) = (typeof(msgSend))objc_msgSend;
    SEL effectSel = NSSelectorFromString(@"effectWithStyle:");
    id effect = msgSend(cls, effectSel, (NSInteger)s);

    if (DKShareGlassUsesClear() && effect) {
        UIColor *tint = DKGlassTintForStyle(style);
        if (tint) [effect setValue:tint forKey:@"tintColor"];
    }
    if (effect) [effect setValue:@YES forKey:@"interactive"];

    return effect;
}

#pragma mark - 深浅色

static void DKApplyGlassStyle(UIUserInterfaceStyle style) {
    if (style == UIUserInterfaceStyleUnspecified || style == gGlassStyle) return;
    gGlassStyle = style;

    if (gPanelGlass) {
        gPanelGlass.overrideUserInterfaceStyle = style;
        gPanelGlass.effect = DKShareMakeGlassEffect(style);
    }
}

static void DKObserveStyle(UIView *host) {
    UIWindowScene *scene = host.window.windowScene;
    if (!scene || scene == gObservedScene) return;
    gObservedScene = scene;

    SEL registerSel = NSSelectorFromString(@"registerForTraitChanges:withHandler:");
    if (![scene respondsToSelector:registerSel]) return;

    NSArray *traits = @[ UITraitUserInterfaceStyle.class ];
    void (^handler)(UIWindowScene *, UITraitCollection *) =
        ^(UIWindowScene *changed, __unused UITraitCollection *previous) {
        DKApplyGlassStyle(changed.traitCollection.userInterfaceStyle);
    };

    void (*msgSend)(id, SEL, NSArray *, id) = (typeof(msgSend))objc_msgSend;
    msgSend(scene, registerSel, traits, handler);
}

#pragma mark - 安装/拆除

// 找分享面板的背景层容器
static UIView *DKFindPanelSlot(UIView *root) {
    if (!root) return nil;
    // 优先找 DUXVisualEffectView 或 blur 背景
    for (UIView *sub in root.subviews) {
        if ([NSStringFromClass(sub.class) containsString:@"VisualEffect"] ||
            [NSStringFromClass(sub.class) containsString:@"Blur"] ||
            [NSStringFromClass(sub.class) containsString:@"DUX"]) {
            return root;
        }
    }
    if (root.subviews.count > 0) {
        return DKFindPanelSlot(root.subviews.firstObject);
    }
    return root;
}

static void DKInstallGlass(UIView *slot) {
    if (!slot) return;

    // 移除旧玻璃
    if (gPanelGlass && gPanelGlass.superview != slot) {
        [gPanelGlass removeFromSuperview];
        gPanelGlass = nil;
    }

    if (!DKShareGlassEnabled()) return;
    if (!DKShareGlassClass()) return;

    if (!gPanelGlass) {
        UIVisualEffect *eff = DKShareMakeGlassEffect(gGlassStyle);
        if (!eff) return;
        gPanelGlass = [[UIVisualEffectView alloc] initWithEffect:eff];
        gPanelGlass.autoresizingMask =
            UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }

    gPanelGlass.frame = slot.bounds;
    if (gPanelGlass.superview != slot) {
        [slot insertSubview:gPanelGlass atIndex:0];
    }

    // 把原来的模糊层隐藏
    for (UIView *sub in slot.subviews) {
        if (sub == gPanelGlass) continue;
        if ([sub isKindOfClass:UIVisualEffectView.class] ||
            [NSStringFromClass(sub.class) containsString:@"Blur"] ||
            [NSStringFromClass(sub.class) containsString:@"VisualEffect"]) {
            if (sub.layer.opacity != 0.0f) sub.layer.opacity = 0.0f;
        }
    }
}

static void DKRemoveGlass(void) {
    if (!gPanelGlass) return;
    UIView *parent = gPanelGlass.superview;
    if (parent) {
        for (UIView *sub in parent.subviews) {
            if (sub == gPanelGlass) continue;
            if ([sub isKindOfClass:UIVisualEffectView.class] ||
                [NSStringFromClass(sub.class) containsString:@"Blur"] ||
                [NSStringFromClass(sub.class) containsString:@"VisualEffect"]) {
                if (sub.layer.opacity != 1.0f) sub.layer.opacity = 1.0f;
            }
        }
    }
    [gPanelGlass removeFromSuperview];
    gPanelGlass = nil;
    gCurrentPanelSlot = nil;
}

#pragma mark - 更新入口

static void DKShareGlassUpdate(id container) {
    if (![container isKindOfClass:UIViewController.class]) return;
    UIViewController *vc = container;
    UIView *rootView = vc.view;
    if (!rootView) return;

    DKObserveStyle(rootView);
    DKApplyGlassStyle(rootView.window.windowScene.traitCollection.userInterfaceStyle);

    if (!DKShareGlassEnabled()) {
        DKRemoveGlass();
        return;
    }

    UIView *slot = DKFindPanelSlot(rootView);
    if (slot) {
        if (slot != gCurrentPanelSlot) {
            DKRemoveGlass();
            gCurrentPanelSlot = slot;
        }
        DKInstallGlass(slot);
    }
}

// 主题刷新时重装
static void DKShareGlassThemeReload(void) {
    if (!DKShareGlassEnabled()) return;
    if (gCurrentPanelSlot) {
        UIView *slot = gCurrentPanelSlot;
        gPanelGlass = nil;
        gCurrentPanelSlot = nil;
        DKInstallGlass(slot);
        gCurrentPanelSlot = slot;
    }
}

#pragma mark - Hook

%group DKShareGlassHooks

%hook AWESharePanelContainerViewController

- (void)viewDidLayoutSubviews {
    %orig;
    DKShareGlassUpdate(self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    DKShareGlassUpdate(self);
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    DKRemoveGlass();
}

%end

%hook AWESharePanelViewController

- (void)awe_themeReload {
    %orig;
    DKShareGlassThemeReload();
}

- (void)viewDidLayoutSubviews {
    %orig;
    DKShareGlassUpdate(self);
}

%end

%end

#pragma mark - 设置项注册

%ctor {
    DKSettingsRegisterItem(@"分享面板", ^AWESettingItemModel *{
        return DKMakeSwitch(
            DKKeySharePanelGlass,
            @"分享面板液态玻璃",
            @"给分享弹层加上 iOS 26 原生液态玻璃效果"
        );
    });

    DKSettingsRegisterItem(@"分享面板", ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(
            DKKeySharePanelGlassClear,
            @"清透玻璃",
            @"开启后使用清透玻璃（细节可辨），关闭则使用系统默认磨砂材质"
        );
        void (^origBlock)(void) = [item.switchChangedBlock copy];
        item.switchChangedBlock = ^{
            if (origBlock) origBlock();
            gGlassStyle = UIUserInterfaceStyleUnspecified;
        };
        return item;
    });

    if (DKGlassOSAvailable()) {
        %init(DKShareGlassHooks);
    }
}
