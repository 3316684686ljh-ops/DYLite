//
//  DKGlassRuntime.h
//  运行时反射层：在编译期未知 iOS 26 API 时，用 NSClassFromString / KVC 访问 UIGlassEffect
//

#ifndef DKGlassRuntime_h
#define DKGlassRuntime_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

id DKCreateGlassEffect(BOOL clearStyle, UIColor *tint, BOOL interactive);
void DKApplyGlassToView(UIVisualEffectView *view, BOOL clearStyle, UIColor *tint, BOOL interactive);
void DKRemoveGlassFromView(UIVisualEffectView *view);
void DKInstallGlassOnSlot(UIView *slot, UIVisualEffectView **glassOut, BOOL interactive);
void DKRemoveGlassFromSlot(UIView *slot, UIVisualEffectView **glassOut);

#ifdef __cplusplus
}
#endif

#endif /* DKGlassRuntime_h */
