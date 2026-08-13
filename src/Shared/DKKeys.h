//
//  DKKeys.h
//  集中管理所有 NSUserDefaults 开关键
//

#ifndef DKKeys_h
#define DKKeys_h

#import <Foundation/Foundation.h>

#ifndef DK_VERSION
#error DK_VERSION must be injected by Makefile from control Version.
#endif

#pragma mark - 视频全屏

static NSString *const DKKeyVideoFullscreen = @"DYLiteVideoFullscreen";

#pragma mark - 评论区

// 评论区液态玻璃（仅 iOS 26+）
static NSString *const DKKeyCommentGlass      = @"DYLiteCommentGlass";
// 清透玻璃开关（总开关开启时生效）
static NSString *const DKKeyCommentGlassClear = @"DYLiteCommentGlassClear";

#pragma mark - 分享面板

// 分享面板液态玻璃（仅 iOS 26+）
static NSString *const DKKeySharePanelGlass      = @"DYLiteSharePanelGlass";
// 清透玻璃开关
static NSString *const DKKeySharePanelGlassClear = @"DYLiteSharePanelGlassClear";

#pragma mark - 元素清理

// 移除"去汽水听"
static NSString *const DKKeyRemoveQushuiting = @"DYLiteRemoveQushuiting";

// 移除关注按钮
static NSString *const DKKeyRemoveFollowButton = @"DYLiteRemoveFollowButton";

#endif /* DKKeys_h */
