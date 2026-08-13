//
//  DKRemoveQushuiting.xm
//  移除视频文案下方的"去汽水听"推广入口
//
//  思路：
//  1. 钩视频详情页（或 feed 表）中相关视图的布局方法
//  2. 遍历子视图，查找 label 文字包含 "汽水听" / "汽水" / "听完整版" 等关键词
//  3. 把对应的父视图 hidden = YES
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"

// 匹配关键词：命中任意一个即视为"去汽水听"相关
static NSArray<NSString *> *DKQushuitingKeywords(void) {
    static NSArray *keywords;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keywords = @[
            @"去汽水听",
            @"汽水听",
            @"汽水",
            @"听完整版",
            @"听全曲",
        ];
    });
    return keywords;
}

static BOOL DKTextMatchesQushuiting(NSString *text) {
    if (!text || text.length == 0) return NO;
    for (NSString *kw in DKQushuitingKeywords()) {
        if ([text containsString:kw]) return YES;
    }
    return NO;
}

// 递归查找：把包含目标文字的整个容器隐藏
static BOOL DKHideQushuitingInView(UIView *view) {
    if (!view || view.isHidden) return NO;
    BOOL found = NO;

    // 先查 UILabel
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        if (DKTextMatchesQushuiting(label.text)) {
            // 找到 label，向上找父视图直到容器
            UIView *target = view;
            // 最多向上 3 层，找到合适的容器整体隐藏
            for (NSUInteger i = 0; i < 3 && target.superview; i++) {
                target = target.superview;
            }
            if (!target.hidden) target.hidden = YES;
            return YES;
        }
    }

    // 查 UIButton 的 title
    if ([view isKindOfClass:UIButton.class]) {
        UIButton *btn = (UIButton *)view;
        if (DKTextMatchesQushuiting(btn.currentTitle)) {
            UIView *target = view;
            for (NSUInteger i = 0; i < 3 && target.superview; i++) {
                target = target.superview;
            }
            if (!target.hidden) target.hidden = YES;
            return YES;
        }
    }

    // 递归子视图
    for (UIView *sub in view.subviews) {
        if (DKHideQushuitingInView(sub)) found = YES;
    }
    return found;
}

#pragma mark - Hook

%hook AWEDPlayerViewController_Merge

- (void)viewDidLayoutSubviews {
    %orig;
    if (DKPrefBool(DKKeyRemoveQushuiting)) {
        DKHideQushuitingInView(self.view);
    }
}

%end

// Feed 首页的视频也要处理
%hook AWEFeedTableView

- (void)layoutSubviews {
    %orig;
    if (DKPrefBool(DKKeyRemoveQushuiting)) {
        for (UIView *cell in self.visibleCells) {
            DKHideQushuitingInView(cell);
        }
    }
}

%end

#pragma mark - 设置项注册

%ctor {
    DKSettingsRegisterItem(@"元素清理", ^AWESettingItemModel *{
        return DKMakeSwitch(
            DKKeyRemoveQushuiting,
            @"移除「去汽水听」",
            @"隐藏视频文案下方的「去汽水听」「听完整版」等推广入口"
        );
    });
}
