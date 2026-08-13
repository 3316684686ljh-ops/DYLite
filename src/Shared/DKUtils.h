//
//  DKUtils.h
//  跨功能复用的无状态工具：开关读取、子控制器查找
//

#ifndef DKUtils_h
#define DKUtils_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 读取某开关（NSUserDefaults BOOL），玻璃相关开关会自动检查系统版本
BOOL DKPrefBool(NSString *key);

/// 沿 childViewControllers 递归找指定类名的子控制器
UIViewController *DKChildControllerNamed(UIViewController *controller, NSString *className);

/// 液态玻璃染色：浅色档不染色，深色档黑 30%
UIColor *DKGlassTintForStyle(UIUserInterfaceStyle style);

/// 从 view 自身起向上找所在 Cell 的 contentView
UIView *DKCellContentView(UIView *view);

/// 视频要撑到的目标高度：所在 Cell contentView 的满高
CGFloat DKFullCellHeight(UIView *view);

#ifdef __cplusplus
}
#endif

#endif /* DKUtils_h */
