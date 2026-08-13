//
//  DKVideoFullscreen.h
//  视频全屏功能共享接口
//

#ifndef DKVideoFullscreen_h
#define DKVideoFullscreen_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 视频全屏总开关
BOOL DKVideoFullscreenOn(void);

/// 两个矩形是否接近一致（容差覆盖 @3x 亚像素漂移）
BOOL DKRectsClose(CGRect lhs, CGRect rhs);

/// 视频容器此刻应有的目标 frame；开关关着或算不出来时返回 CGRectNull
CGRect DKVideoContainerTargetFrame(UIView *view);

/// 首页/朋友页 HUD 钉位调整：不在已撑高的 feed 内返回 CGRectNull 放行
CGRect DKFeedHUDAdjustFrame(UIView *view, CGRect frame);

#ifdef __cplusplus
}
#endif

#endif /* DKVideoFullscreen_h */
