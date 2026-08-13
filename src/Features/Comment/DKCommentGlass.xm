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
//  兼容性说明：
//  - UIGlassEffect 是 iOS 26 新类，当前 Theos SDK 低于 26 时没有头文件声明
//  - 所以这里全部用运行时反射（NSClassFromString / objc_msgSend / id）动态构造
//

#import "DKCommentGlass.h"
#import "DouyinHeaders.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
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

#pragma mark - UIGlassEffect 运行时封装（兼容 SDK < iOS 26）

// 定义 SDK 里没有的枚举常量（和 UIGlassEffect.h 对齐）
// 如果将来 SDK 升级为 26+ 并真正声明，这里的命名也不会冲突
typedef NS_ENUM(NSInteger, DKGlassEffectStyleRT) {
    DKGlassEffectStyleRTClear   = 0,
    DKGlassEffectStyleRTRegular = 1,
};

static Class DKGlassEffectClass(void) {
    static Class cls = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cls = NSClassFromString(@"UIGlassEffect");
    });
    return cls;
}

static BOOL DKGlassEffectClassAvailable(void) {
    return DKGlassEffectClass() != Nil;
}

// 构造 UIGlassEffect 实例，通过 runtime 调 effectWithStyle:
static UIVisualEffect *DKMakeGlassEffectRT(UIUserInterfaceStyle style, BOOL interactive) {
    Class cls = DKGlassEffectClass();
    if (!cls) return nil;

    DKGlassEffectStyleRT s = DKCommentGlassUsesClear()
        ? DKGlassEffectStyleRTClear
        : DKGlassEffectStyleRTRegular;

    // 等价于 [UIGlassEffect effectWithStyle:s]
    id (*msgSend)(id, SEL, NSInteger) = (typeof(msgSend))objc_msgSend;
    SEL effectSel = NSSelectorFromString(@"effectWithStyle:");
    id effect = msgSend(cls, effectSel, (NSInteger)s);

    // 如果是 Clear 风格，设置 tintColor
    if (DKCommentGlassUsesClear() && effect) {
        UIColor *tint = DKGlassTintForStyle(style);
        if (tint) {
            [effect setValue:tint forKey:@"tintColor"];
        }
    }

    // 设置 interactive
    if (effect) {
        [effect setValue:@(interactive) forKey:@"interactive"];
    }

    return effect;
}

#pragma mark - 深浅色

static void DKApplyGlassStyle(UIUserInterfaceStyle style) {
    if (style == UIUserInterfaceStyleUnspecified || style == gGlassStyle) return;
    gGlassStyle = style;

    if (gSlotGlass) {
        gSlotGlass.overrideUserInterfaceStyle = style;
        gSlotGlass.effect = DKMakeGlassEffectRT(style, YES);
    }
    if (gFieldGlass) {
        gFieldGlass.overrideUserInterfaceStyle = style;
        gFieldGlass.effect = DKMakeGlassEffectRT(style, NO);
    }
}

static void DKObserveStyle(UIView *host) {
    UIWindowScene *scene = host.window.windowScene;
    if (!scene || scene == gObservedScene) return;
    gObservedScene = scene;

    // 用 respondsToSelector 保证旧 SDK 不会编译失败（selector 本身是字符串）
    SEL registerSel = NSSelectorFromString(@"registerForTraitChanges:withHandler:");
    if (![scene respondsToSelector:registerSel]) return;

    NSArray *traits = @[ UITraitUserInterfaceStyle.class ];
    void (^handler)(UIWindowScene *, UITraitCollection *) =
        ^(UIWindowScene *changed, __unused UITraitCollection *previous) {
        DKApplyGlassStyle(changed.traitCollection.userInterfaceStyle);
    };

    // 动态调用，参数签名: -(void)registerForTraitChanges:(NSArray*)t withHandler:(id)block
    void (*msgSend)(id, SEL, NSArray *, id) = (typeof(msgSend))objc_msgSend;
    msgSend(scene, registerSel, traits, handler);
}

#pragma mark - 玻璃安装/拆除（使用返回值，避免 __autoreleasing 双指针不匹配）

// 找一个视图里最底层的模糊/背景层，返回它的父视图（即玻璃要插入的槽位）
static UIView *DKFindBackdropSlot(UIView *root) {
    if (!root) return nil;
    for (UIView *sub in root.subviews) {
        if ([sub isKindOfClass:UIVisualEffectView.class] ||
            [NSStringFromClass(sub.class) containsString:@"Blur"] ||
            [NSStringFromClass(sub.class) containsString:@"Backdrop"] ||
            [NSStringFromClass(sub.class) containsString:@"Background"]) {
            return root;
        }
    }
    if (root.subviews.count > 0) {
        return DKFindBackdropSlot(root.subviews.firstObject);
    }
    return root;
}

// 安装玻璃，返回新的 glass 实例（由调用方保存到全局变量）
static UIVisualEffectView *DKInstallGlassOnSlotReturn(UIView *slot,
                                                      UIVisualEffectView *oldGlass,
                                                      BOOL interactive) {
    if (!slot) return oldGlass;

    // 移除旧玻璃
    if (oldGlass) {
        [oldGlass removeFromSuperview];
        oldGlass = nil;
    }

    if (!DKCommentGlassEnabled()) return nil;
    if (!DKGlassEffectClassAvailable()) return nil;   // 运行时类不存在直接退出

    UIVisualEffect *effect = DKMakeGlassEffectRT(gGlassStyle, interactive);
    if (!effect) return nil;

    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:effect];
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    glass.frame = slot.bounds;
    [slot insertSubview:glass atIndex:0];

    for (UIView *sub in slot.subviews) {
        if (sub == glass) continue;
        if ([sub isKindOfClass:UIVisualEffectView.class] ||
            [NSStringFromClass(sub.class) containsString:@"Blur"] ||
            [NSStringFromClass(sub.class) containsString:@"Backdrop"]) {
            if (sub.layer.opacity != 0.0f) sub.layer.opacity = 0.0f;
        }
    }
    return glass;
}

// 拆除玻璃，返回 nil（由调用方保存到全局变量）
static UIVisualEffectView *DKRemoveGlassFromSlotReturn(UIView *slot,
                                                       UIVisualEffectView *glass) {
    if (!glass) return nil;
    UIView *parent = glass.superview;
    if (parent) {
        for (UIView *sub in parent.subviews) {
            if (sub == glass) continue;
            if ([sub isKindOfClass:UIVisualEffectView.class] ||
                [NSStringFromClass(sub.class) containsString:@"Blur"] ||
                [NSStringFromClass(sub.class) containsString:@"Backdrop"]) {
                if (sub.layer.opacity != 1.0f) sub.layer.opacity = 1.0f;
            }
        }
    }
    [glass removeFromSuperview];
    return nil;
}

#pragma mark - 更新入口

static void DKCommentGlassUpdate(id controller) {
    if (![controller isKindOfClass:UIViewController.class]) return;
    UIViewController *vc = controller;

    UIView *rootView = vc.view;
    if (!rootView) return;

    DKObserveStyle(rootView);
    DKApplyGlassStyle(rootView.window.windowScene.traitCollection.userInterfaceStyle);

    if (!DKCommentGlassEnabled()) {
        // 关开关：拆除玻璃
        gSlotGlass = DKRemoveGlassFromSlotReturn(gCurrentSlot, gSlotGlass);
        gFieldGlass = DKRemoveGlassFromSlotReturn(gCurrentField, gFieldGlass);
        gCurrentSlot = nil;
        gCurrentField = nil;
        return;
    }

    // 1. 评论主面板
    UIView *slot = DKFindBackdropSlot(rootView);
    if (slot && slot != gCurrentSlot) {
        gSlotGlass = DKRemoveGlassFromSlotReturn(gCurrentSlot, gSlotGlass);
        gSlotGlass = DKInstallGlassOnSlotReturn(slot, gSlotGlass, YES);
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
                gFieldGlass = DKRemoveGlassFromSlotReturn(gCurrentField, gFieldGlass);
                gFieldGlass = DKInstallGlassOnSlotReturn(sub, gFieldGlass, NO);
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
    DKCommentGlassUpdate(self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    DKCommentGlassUpdate(self);
}

%end

%end

#pragma mark - 设置项注册

%ctor {
    DKSettingsRegisterItem(@"评论区", ^AWESettingItemModel *{
        return DKMakeSwitch(
            DKKeyCommentGlass,
            @"评论区液态玻璃",
            @"给评论面板和输入框添加 iOS 26 液态玻璃效果（需要 iOS 26+）");
    });
    DKSettingsRegisterItem(@"评论区", ^AWESettingItemModel *{
        return DKMakeSwitch(
            DKKeyCommentGlassClear,
            @"评论区玻璃 Clear 风格",
            @"使用透明的液态玻璃（需开启上面的开关）");
    });

    // 运行时守卫已在功能内部（DKCommentGlassEnabled/DKGlassEffectClassAvailable），
    // 这里直接 %init，避免 Logos if-block scope 错误
    %init(DKCommentGlassHooks);
}
