//
//  DKCommentGlass.h
//  评论区液态玻璃对外接口
//

#ifndef DKCommentGlass_h
#define DKCommentGlass_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 最近接管的评论面板槽位
UIView *DKCommentGlassCurrentSlot(void);

/// 最近接管的输入框槽位
UIView *DKCommentGlassCurrentField(void);

#ifdef __cplusplus
}
#endif

#endif /* DKCommentGlass_h */
