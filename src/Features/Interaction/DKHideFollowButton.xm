//
//  DKHideFollowButton.xm
//  移除视频页面右侧的「+ 关注」按钮
//
//  抖音的关注按钮主要出现在：
//  1. AWEPlayInteractionFollowPromptView —— 头像下方的「关注(+)」容器
//  2. 其他地方的关注按钮（通过 accessibilityLabel 匹配）
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"

#pragma mark - 关键词匹配

static BOOL DKIsFollowRelatedText(NSString *text) {
    if (!text || text.length == 0) return NO;
    // 匹配"关注"关键词，但要排除"已关注"
    if ([text containsString:@"关注"] && ![text containsString:@"已关注"]) {
        return YES;
    }
    if ([text containsString:@"Follow"] && ![text containsString:@"Following"]) {
        return YES;
    }
    return NO;
}

// 递归隐藏关注相关视图
static BOOL DKHideFollowInView(UIView *view) {
    if (!view || view.isHidden) return NO;
    BOOL found = NO;

    // 1. 类名匹配：抖音的关注提示视图
    NSString *clsName = NSStringFromClass(view.class);
    if ([clsName containsString:@"FollowPrompt"] ||
        [clsName containsString:@"FollowButton"]) {
        if (!view.hidden) {
            view.hidden = YES;
            return YES;
        }
    }

    // 2. UILabel 文字匹配
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        if (DKIsFollowRelatedText(label.text)) {
            // 向上找 2-3 层作为容器隐藏
            UIView *target = view;
            for (NSUInteger i = 0; i < 3 && target.superview; i++) {
                target = target.superview;
                // 如果找到按钮类，就停在按钮这层
                if ([target isKindOfClass:UIButton.class]) break;
            }
            if (!target.hidden) {
                target.hidden = YES;
                return YES;
            }
        }
    }

    // 3. UIButton 文字匹配
    if ([view isKindOfClass:UIButton.class]) {
        UIButton *btn = (UIButton *)view;
        if (DKIsFollowRelatedText(btn.currentTitle) ||
            DKIsFollowRelatedText(btn.accessibilityLabel)) {
            if (!btn.hidden) {
                btn.hidden = YES;
                return YES;
            }
        }
    }

    // 4. accessibilityLabel 匹配
    if (DKIsFollowRelatedText(view.accessibilityLabel)) {
        if (!view.hidden) {
            view.hidden = YES;
            return YES;
        }
    }

    // 递归子视图
    for (UIView *sub in view.subviews) {
        if (DKHideFollowInView(sub)) found = YES;
    }
    return found;
}

#pragma mark - Hook

// HUD 控制器：关注按钮通常在这里
%hook AWEPlayInteractionViewController

- (void)viewDidLayoutSubviews {
    %orig;
    if (DKPrefBool(DKKeyRemoveFollowButton)) {
        DKHideFollowInView(self.view);
    }
}

%end

// Feed 表中的关注按钮
%hook AWEFeedTableView

- (void)layoutSubviews {
    %orig;
    if (DKPrefBool(DKKeyRemoveFollowButton)) {
        for (UIView *cell in self.visibleCells) {
            DKHideFollowInView(cell);
        }
    }
}

%end

// 兜底：直接钩 AWEPlayInteractionFollowPromptView 的显隐
%hook AWEPlayInteractionFollowPromptView

- (void)didMoveToSuperview {
    %orig;
    if (DKPrefBool(DKKeyRemoveFollowButton) && !self.hidden) {
        self.hidden = YES;
    }
}

- (void)layoutSubviews {
    %orig;
    if (DKPrefBool(DKKeyRemoveFollowButton) && !self.hidden) {
        self.hidden = YES;
    }
}

%end

#pragma mark - 设置项注册

%ctor {
    DKSettingsRegisterItem(@"元素清理", ^AWESettingItemModel *{
        return DKMakeSwitch(
            DKKeyRemoveFollowButton,
            @"移除关注按钮",
            @"隐藏视频页面右侧的「+ 关注」按钮入口"
        );
    });
}
