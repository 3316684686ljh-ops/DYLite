//
//  DouyinHeaders.h
//  抖音私有类的前向声明 —— 只声明本插件用到的成员
//  新增功能用到新类时在这里追加即可
//

#ifndef DouyinHeaders_h
#define DouyinHeaders_h

#import <UIKit/UIKit.h>

#pragma mark - 视频全屏功能用到的类

// 视频+交互合并容器，其 .view 用于视频容器布局调整
@interface AWEDPlayerViewController_Merge : UIViewController
@property (nonatomic, strong) AWEAwemeModel *model;
@property (nonatomic, assign) BOOL hasInlandscape;
- (BOOL)isInLandscapeFeedStatus;
- (NSString *)referString;
@end

@interface AWEVideoModel : NSObject
@property (nonatomic, strong) NSNumber *width;
@property (nonatomic, strong) NSNumber *height;
@end

@interface AWEAwemeModel : NSObject
@property (nonatomic, strong) AWEVideoModel *video;
@property (nonatomic, assign) long long awemeType;
@end

// 视频表基类，被底栏压高时就是视频不全屏的源头
@interface AWEFeedDataSafeTableView : UITableView
@end

@interface AWEFeedTableView : AWEFeedDataSafeTableView
@end

// HUD 控制器
@interface AWEPlayInteractionViewController : UIViewController
@property (nonatomic, copy) NSString *referString;
@end

// 头像下方的「关注(+)」容器
@interface AWEPlayInteractionFollowPromptView : UIView
@end

#pragma mark - 评论区功能用到的类

@interface AWECommentContainerViewController : UIViewController
@end

// 评论输入框背景
@interface AWECommentInputBackgroundView : UIView
@end

#pragma mark - 分享面板功能用到的类

@interface AWESharePanelContainerViewController : UIViewController
@end

@interface AWESharePanelViewController : UIViewController
- (void)awe_themeReload;
@end

#pragma mark - 抖音设置系统（注入设置菜单用）

@interface AWESettingItemModel : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, assign) NSInteger type;
@property (nonatomic, assign) NSInteger cellType;
@property (nonatomic, assign) BOOL isEnable;
@property (nonatomic, assign) BOOL isSwitchOn;
@property (nonatomic, copy) void (^cellTappedBlock)(void);
@property (nonatomic, copy) void (^switchChangedBlock)(void);
@end

@interface AWESettingSectionModel : NSObject
@property (nonatomic, assign) CGFloat sectionHeaderHeight;
@property (nonatomic, copy) NSString *sectionHeaderTitle;
@property (nonatomic, strong) NSArray *itemArray;
@end

@interface AWESettingsViewModel : NSObject
@property (nonatomic, strong) NSArray *sectionDataArray;
@property (nonatomic, assign) NSInteger colorStyle;
@property (nonatomic, weak) id controllerDelegate;
@end

@interface AWESettingBaseViewController : UIViewController
@property (nonatomic, strong) id viewModel;
@end

#endif /* DouyinHeaders_h */
