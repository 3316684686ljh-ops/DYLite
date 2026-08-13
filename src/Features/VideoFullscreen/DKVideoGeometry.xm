       //
//  DKVideoGeometry.xm
//  视频全屏的几何拦截：统一在 setFrame: 一个入口处理
//
//  拦截点：
//  1. AWEDPlayerViewController_Merge.view 的 setFrame: —— 视频容器撑满
//  2. AWEPlayInteractionViewController.view 的 setFrame: —— HUD 高度钉位
//

#import "DKVideoFullscreen.h"
#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"

#import <objc/runtime.h>

#pragma mark - 开关

BOOL DKVideoFullscreenOn(void) {
    return DKPrefBool(DKKeyVideoFullscreen);
}

#pragma mark - 工具

// 容差 0.5pt：@3x 下 0.33pt 一个像素
BOOL DKRectsClose(CGRect lhs, CGRect rhs) {
    return
        fabs(lhs.origin.x    - rhs.origin.x)    < 0.5 &&
        fabs(lhs.origin.y    - rhs.origin.y)    < 0.5 &&
        fabs(lhs.size.width  - rhs.size.width)  < 0.5 &&
        fabs(lhs.size.height - rhs.size.height) < 0.5;
}

// 判断一个 view 的 nextResponder 链里是否有指定类名的 VC
static BOOL DKViewBelongsToViewControllerNamed(UIView *view, NSString *targetName) {
    if (!view || !targetName) return NO;
    for (UIResponder *r = view.nextResponder; r; r = r.nextResponder) {
        if ([r isKindOfClass:UIViewController.class]) {
            NSString *name = NSStringFromClass([r class]);
            if ([name isEqualToString:targetName]) return YES;
            // 父控制器也检查（Swift 类名带点的场景）
            UIViewController *vc = (UIViewController *)r;
            if (vc.parentViewController) {
                NSString *pname = NSStringFromClass([vc.parentViewController class]);
                if ([pname isEqualToString:targetName]) return YES;
            }
        }
    }
    return NO;
}

// 获取 view 所在的 Merge VC
static AWEDPlayerViewController_Merge *DKFindMergeForView(UIView *view) {
    if (!view) return nil;
    for (UIResponder *r = view.nextResponder; r; r = r.nextResponder) {
        if ([r isKindOfClass:NSClassFromString(@"AWEDPlayerViewController_Merge")]) {
            return (AWEDPlayerViewController_Merge *)r;
        }
        if ([r isKindOfClass:UIViewController.class]) {
            UIViewController *vc = (UIViewController *)r;
            // 也查子控制器
            for (UIViewController *child in vc.childViewControllers) {
                if ([child isKindOfClass:NSClassFromString(@"AWEDPlayerViewController_Merge")]) {
                    return (AWEDPlayerViewController_Merge *)child;
                }
            }
        }
    }
    return nil;
}

// 判断是否横屏视频（横屏不做全屏，留黑边保持比例）
static BOOL DKIsLandscapeVideo(AWEDPlayerViewController_Merge *merge) {
    if (!merge) return NO;
    // hasInlandscape 属性
    if ([merge respondsToSelector:@selector(hasInlandscape)]) {
        if ([merge hasInlandscape]) return YES;
    }
    if ([merge respondsToSelector:@selector(isInLandscapeFeedStatus)]) {
        if ([merge isInLandscapeFeedStatus]) return YES;
    }
    // 检查宽高比
    AWEAwemeModel *model = nil;
    @try { model = [merge valueForKey:@"model"]; } @catch(id e) {}
    if (model && [model respondsToSelector:NSSelectorFromString(@"video")]) {
        AWEVideoModel *video = nil;
        @try { video = [model valueForKey:@"video"]; } @catch(id e) {}
        if (video) {
            NSNumber *w = nil, *h = nil;
            @try {
                w = [video valueForKey:@"width"];
                h = [video valueForKey:@"height"];
            } @catch(id e) {}
            if (w && h && w.doubleValue > 0 && h.doubleValue > 0) {
                if (w.doubleValue / h.doubleValue > 1.1) return YES;  // 宽:高 > 1.1 算横屏
            }
        }
    }
    return NO;
}

#pragma mark - 视频容器 frame 计算

CGRect DKVideoContainerTargetFrame(UIView *view) {
    if (!DKVideoFullscreenOn()) return CGRectNull;

    AWEDPlayerViewController_Merge *merge = DKFindMergeForView(view);
    if (!merge) return CGRectNull;

    // 横屏视频不强制全屏
    if (DKIsLandscapeVideo(merge)) return CGRectNull;

    // 取 Cell 满高：视频要撑到的目标高度
    CGFloat cellHeight = DKFullCellHeight(view);
    if (cellHeight <= 0) {
        // 找不到 Cell（详情页场景），用窗口高度
        UIWindow *window = view.window;
        if (!window) window = [UIApplication sharedApplication].keyWindow;
        cellHeight = window ? CGRectGetHeight(window.bounds) : CGRectGetHeight(view.bounds);
    }

    CGRect target = view.bounds;
    target.origin = CGPointZero;
    target.size.height = cellHeight;

    return target;
}

#pragma mark - HUD 钉位

CGRect DKFeedHUDAdjustFrame(UIView *view, CGRect frame) {
    if (!DKVideoFullscreenOn()) return CGRectNull;

    // 只处理 AWEPlayInteractionViewController.view
    if (!DKViewBelongsToViewControllerNamed(view, @"AWEPlayInteractionViewController")) {
        return CGRectNull;
    }

    // 如果视频容器被撑高了，HUD 也要按撑高前的高度来
    // 简化实现：直接把 HUD 的高度匹配 Cell 高度
    CGFloat cellHeight = DKFullCellHeight(view);
    if (cellHeight <= 0) return CGRectNull;

    CGRect adjusted = frame;
    adjusted.origin.y = 0;
    adjusted.size.height = cellHeight;
    return adjusted;
}

#pragma mark - 表撑高：把底栏占的高度补回来

static void DKPatchFeedTableContentInset(UITableView *tableView) {
    if (!DKVideoFullscreenOn()) return;
    if (!tableView) return;

    // 只处理 AWEFeedDataSafeTableView 及其子类
    NSString *clsName = NSStringFromClass(tableView.class);
    if (![clsName containsString:@"FeedDataSafe"] &&
        ![clsName containsString:@"FeedTable"] &&
        ![clsName containsString:@"AwemeDetailTable"]) {
        return;
    }

    UIEdgeInsets inset = tableView.contentInset;
    // 底栏高度大约 50~83，按 safeArea.bottom + 49 估算
    UIWindow *window = tableView.window;
    if (!window) window = [UIApplication sharedApplication].keyWindow;
    CGFloat bottomInset = 0;
    if (@available(iOS 11.0, *)) {
        bottomInset = window.safeAreaInsets.bottom;
    }
    // 补齐底栏：49pt 是 UITabBar 标准高
    CGFloat tabBarHeight = bottomInset + 49.0;

    if (inset.bottom > 0) {
        // 原来有底栏 inset，把它消掉 → 表就会延伸到底
        UIEdgeInsets newInset = inset;
        newInset.bottom = 0;
        if (!UIEdgeInsetsEqualToEdgeInsets(inset, newInset)) {
            tableView.contentInset = newInset;
        }
    }

    // scrollIndicatorInsets 也同步
    UIEdgeInsets scrollInset = tableView.scrollIndicatorInsets;
    if (scrollInset.bottom > 0) {
        UIEdgeInsets newScrollInset = scrollInset;
        newScrollInset.bottom = MAX(0, scrollInset.bottom - tabBarHeight);
        if (!UIEdgeInsetsEqualToEdgeInsets(scrollInset, newScrollInset)) {
            tableView.scrollIndicatorInsets = newScrollInset;
        }
    }
}

#pragma mark - Hook

%group DKVideoFullscreenHooks

// 统一拦截 setFrame: —— 只有一个全局钩子，不重复
%hook UIView

- (void)setFrame:(CGRect)frame {
    // 1. 视频容器：AWEDPlayerViewController_Merge.view
    if (DKViewBelongsToViewControllerNamed(self, @"AWEDPlayerViewController_Merge")) {
        CGRect target = DKVideoContainerTargetFrame(self);
        if (!CGRectIsNull(target) && !DKRectsClose(frame, target)) {
            // 只在视频真的需要撑高时改写
            // 但如果视频正在做缩小动画（origin.y≠0），不要拦评论区的缩放
            if (CGRectGetMinY(frame) >= -0.5) {
                %orig(target);
                return;
            }
        }
    }

    // 2. HUD 钉位：AWEPlayInteractionViewController.view
    CGRect hudAdjust = DKFeedHUDAdjustFrame(self, frame);
    if (!CGRectIsNull(hudAdjust) && !DKRectsClose(frame, hudAdjust)) {
        if (CGRectGetMinY(frame) >= -0.5) {
            %orig(hudAdjust);
            return;
        }
    }

    %orig(frame);
}

%end

// Feed 表：每轮布局补 contentInset
%hook AWEFeedDataSafeTableView

- (void)layoutSubviews {
    %orig;
    DKPatchFeedTableContentInset(self);
}

%end

%hook AWEFeedTableView

- (void)layoutSubviews {
    %orig;
    DKPatchFeedTableContentInset(self);
}

%end

%end

#pragma mark - 设置项注册

%ctor {
    DKSettingsRegisterItem(@"视频全屏", ^AWESettingItemModel *{
        return DKMakeSwitch(
            DKKeyVideoFullscreen,
            @"视频全屏",
            @"视频内容撑满整个屏幕，去除底栏遮挡（横屏视频自动跳过）"
        );
    });

    %init(DKVideoFullscreenHooks);
}
