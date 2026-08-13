//
//  DKSettings.h
//  设置菜单的对外 API：功能模块用它把开关注册进「抖音设置 → DYLite」
//

#ifndef DKSettings_h
#define DKSettings_h

#import "DouyinHeaders.h"

/// 打开设置页时调用，返回一个新构建的设置项
typedef AWESettingItemModel *(^DKSettingItemBuilder)(void);

#ifdef __cplusplus
extern "C" {
#endif

/// 把一个设置项注册到某分区，相同 header 的项归入同一分区
void DKSettingsRegisterItem(NSString *sectionHeader, DKSettingItemBuilder builder);

/// 生成一个开关型设置项（identifier 即 NSUserDefaults 键）
AWESettingItemModel *DKMakeSwitch(NSString *key, NSString *title, NSString *detail);

#ifdef __cplusplus
}
#endif

#endif /* DKSettings_h */
