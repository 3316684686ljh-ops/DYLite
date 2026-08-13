//
//  DKNumberAbbreviation.xm
//  数字显示：点赞/评论/收藏/分享 全部改成 k 单位（类似海外 TikTok 风格）
//  ============================================================
//  规则：
//   0~999    → 原样显示
//   ≥1000    → 全部用 k 显示，保留 1 位小数；小数是 0 时去掉
//              13000   → 13k   （不要 M / B 等百万/十亿单位）
//              13500   → 13.5k
//              1.2万   → 解析成 12000 → 12k
//              130万   → 1,300,000 → 1300k
//  解析能力：
//   同时识别数字本身以及抖音中国版常显示的"万 / 亿"中文字符串，
//   先还原成真实 long long 再按 k 格式化。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import <UIKit/UIKit.h>

#pragma mark - 核心格式化

// 把 long long 数字格式化成 k 风格字符串（不使用 M/B）
static NSString *DKFormatK(long long num) {
    if (num < 0) num = 0;
    if (num < 1000) {
        return [NSString stringWithFormat:@"%lld", num];
    }
    double k = num / 1000.0;
    // 保留 1 位小数，四舍五入
    double rounded = round(k * 10.0) / 10.0;
    // 如果是整数（小数位是 0），直接显示整数 k
    if (fabs(rounded - (long long)rounded) < 0.0001) {
        return [NSString stringWithFormat:@"%lldk", (long long)rounded];
    }
    // 有小数位的情况
    return [NSString stringWithFormat:@"%.1fk", rounded];
}

#pragma mark - 反向解析（把中文"1.2万"/"13亿"或纯数字字符串转成 long long）

static long long DKParseCountString(NSString *text) {
    if (!text.length) return -1;
    NSString *s = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!s.length) return -1;

    // 英文逗号等剥离（1,234）
    s = [s stringByReplacingOccurrencesOfString:@"," withString:@""];

    NSScanner *scan = [NSScanner scannerWithString:s];
    double value = 0;
    if (![scan scanDouble:&value]) return -1;

    // 扫描剩下的字符看是否包含"万/亿"
    NSString *rest = [s substringFromIndex:scan.scanLocation];
    if ([rest containsString:@"亿"]) {
        return (long long)(value * 100000000.0);
    }
    if ([rest containsString:@"万"]) {
        return (long long)(value * 10000.0);
    }
    // 没有中文单位，当成纯数字
    return (long long)value;
}

#pragma mark - 判断 label 文本是否需要转换

static BOOL DKShouldTransformLabelText(NSString *text) {
    if (!text.length) return NO;
    // 包含数字，并且数字 ≥ 1000，或者包含"万/亿"
    return DKParseCountString(text) >= 1000;
}

#pragma mark - 递归遍历所有子视图中的 UILabel

// 用 id 做参数类型，避免 hook 不同 cell 类时 self（__unsafe_unretained const 指针）到 UIView* 的转换报错
static void DKTransformLabelsInView(id viewRef) {
    if (!viewRef || ![viewRef isKindOfClass:[UIView class]]) return;
    UIView *view = (UIView *)viewRef;
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)sub;
            NSString *oldText = label.text;
            if (!DKShouldTransformLabelText(oldText)) continue;
            long long num = DKParseCountString(oldText);
            if (num < 0) continue;
            NSString *newText = DKFormatK(num);
            if (newText.length && ![newText isEqualToString:oldText]) {
                label.text = newText;
            }
        }
        DKTransformLabelsInView(sub);
    }
}

#pragma mark - 开关（默认开）

static BOOL DKNumberAbbrevEnabled(void) {
    // DKPrefBool(key) 默认返回 NO，我们要默认开，所以手动判空
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud objectForKey:DKKeyNumberAbbreviation] == nil) return YES;
    return [ud boolForKey:DKKeyNumberAbbreviation];
}

#pragma mark - Hook 常用 cell 类（layoutSubviews 之后递归替换所有 label）

%group DKNumberAbbrevHook

// 1) Feed 视频卡片
%hook AWEAwemeFeedCell
- (void)layoutSubviews {
    %orig;
    if (DKNumberAbbrevEnabled()) DKTransformLabelsInView(self);
}
%end

// 2) 个人页作品卡片（可能是多个类名，都覆盖一下）
%hook AWEAwemePersonalDetailCell
- (void)layoutSubviews {
    %orig;
    if (DKNumberAbbrevEnabled()) DKTransformLabelsInView(self);
}
%end

%hook AWEAwemePersonalDetailCollectionViewCell
- (void)layoutSubviews {
    %orig;
    if (DKNumberAbbrevEnabled()) DKTransformLabelsInView(self);
}
%end

%hook AWEAwemeCollectionViewCell
- (void)layoutSubviews {
    %orig;
    if (DKNumberAbbrevEnabled()) DKTransformLabelsInView(self);
}
%end

// 3) 评论 cell
%hook AWECommentCell
- (void)layoutSubviews {
    %orig;
    if (DKNumberAbbrevEnabled()) DKTransformLabelsInView(self);
}
%end

// 4) 搜索音乐/通用列表 cell
%hook AWESearchMusicAwemeListCell
- (void)layoutSubviews {
    %orig;
    if (DKNumberAbbrevEnabled()) DKTransformLabelsInView(self);
}
%end

// 5) 通用 AWELikeButton（单独处理，确保点赞按钮旁边数字生效）
%hook AWELikeButton
- (void)layoutSubviews {
    %orig;
    if (DKNumberAbbrevEnabled()) DKTransformLabelsInView(self);
}
- (void)setTitle:(NSString *)title forState:(UIControlState)state {
    NSString *newTitle = title;
    if (DKNumberAbbrevEnabled() && DKShouldTransformLabelText(title)) {
        long long n = DKParseCountString(title);
        if (n >= 0) newTitle = DKFormatK(n);
    }
    %orig(newTitle, state);
}
%end

// 6) 评论数专用 View（如果抖音真的有这个类）
%hook AWECommentCountView
- (void)layoutSubviews {
    %orig;
    if (DKNumberAbbrevEnabled()) DKTransformLabelsInView(self);
}
%end

%end

#pragma mark - 注册设置开关

%ctor {
    %init(DKNumberAbbrevHook);

    // 向设置页注册：新增"数字显示"分区 + 开关
    DKSettingsRegisterItem(@"数字显示", ^AWESettingItemModel *{
        return DKMakeSwitch(
            DKKeyNumberAbbreviation,
            @"点赞/评论/收藏以 k 显示",
            @"国际版TikTok风格：13000 显示为 13k（不使用 M 等其他大单位，默认开启）"
        );
    });
}
