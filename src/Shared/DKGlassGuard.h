//
//  DKGlassGuard.h
//  液态玻璃的系统守卫：低系统允许看见设置项，但不安装 hook
//

#ifndef DKGlassGuard_h
#define DKGlassGuard_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 当前系统是否具备液态玻璃 API（iOS 26.0+）
BOOL DKGlassOSAvailable(void);

/// 该键是否属于液态玻璃守卫表
BOOL DKGlassIsGatedKey(NSString *key);

#ifdef __cplusplus
}
#endif

#endif /* DKGlassGuard_h */
