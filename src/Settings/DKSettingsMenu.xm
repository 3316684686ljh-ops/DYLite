//
//  DKSettingsMenu.xm
//  在「抖音设置」主页插入 DYLite 入口，点击进入本插件设置页
//  设置页内容由各功能模块通过 DKSettingsRegisterItem 注册
//

#import "DouyinHeaders.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import <objc/runtime.h>

#pragma mark - 分区注册表

static NSMutableArray<NSDictionary *> *DKSectionRegistry(void) {
    static NSMutableArray *registry;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ registry = [NSMutableArray array]; });
    return registry;
}

void DKSettingsRegisterItem(NSString *sectionHeader, DKSettingItemBuilder builder) {
    if (!sectionHeader || !builder) return;
    [DKSectionRegistry() addObject:@{ @"header": sectionHeader, @"builder": [builder copy] }];
}

#pragma mark - 液态玻璃设置项守卫

static NSString *const kDKGlassOSTitleSuffix = @" (iOS26+)";

static void DKGlassLockItemIfNeeded(AWESettingItemModel *item) {
    if (!item || DKGlassOSAvailable() || !DKGlassIsGatedKey(item.identifier)) return;

    if (item.title.length && ![item.title hasSuffix:kDKGlassOSTitleSuffix]) {
        item.title = [item.title stringByAppendingString:kDKGlassOSTitleSuffix];
    }
    item.isEnable = NO;
    item.isSwitchOn = NO;
    __weak AWESettingItemModel *weakItem = item;
    item.switchChangedBlock = ^{
        weakItem.isSwitchOn = NO;
    };
    item.cellTappedBlock = nil;
}

#pragma mark - 开关项工厂

AWESettingItemModel *DKMakeSwitch(NSString *key, NSString *title, NSString *detail) {
    AWESettingItemModel *item = [[%c(AWESettingItemModel) alloc] init];
    item.identifier = key;
    item.title = title;
    item.detail = detail ?: @"";
    item.type = 0;
    item.cellType = 6;                 // 开关型 cell
    item.colorStyle = 0;
    item.isEnable = YES;
    item.isSwitchOn = DKPrefBool(key);

    __weak AWESettingItemModel *weakItem = item;
    item.switchChangedBlock = ^{
        __strong AWESettingItemModel *it = weakItem;
        if (!it) return;
        BOOL v = !it.isSwitchOn;
        it.isSwitchOn = v;
        [[NSUserDefaults standardUserDefaults] setBool:v forKey:it.identifier];
        [[NSUserDefaults standardUserDefaults] synchronize];
    };
    DKGlassLockItemIfNeeded(item);
    return item;
}

#pragma mark - 构建设置页数据

static NSArray *DKBuildSectionData(void) {
    // 按 header 分组
    NSMutableDictionary<NSString *, NSMutableArray *> *groups = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *headerOrder = [NSMutableArray array];

    for (NSDictionary *entry in DKSectionRegistry()) {
        NSString *header = entry[@"header"];
        DKSettingItemBuilder builder = entry[@"builder"];
        if (!header || !builder) continue;

        AWESettingItemModel *item = builder();
        if (!item) continue;

        if (!groups[header]) {
            groups[header] = [NSMutableArray array];
            [headerOrder addObject:header];
        }
        [groups[header] addObject:item];
    }

    NSMutableArray *sections = [NSMutableArray array];
    for (NSString *header in headerOrder) {
        AWESettingSectionModel *section = [[%c(AWESettingSectionModel) alloc] init];
        section.sectionHeaderTitle = header;
        section.sectionHeaderHeight = 44.0;
        section.itemArray = groups[header];
        [sections addObject:section];
    }
    return sections;
}

#pragma mark - Hook：在抖音设置列表注入入口

%hook AWESettingsViewModel

- (id)init {
    id result = %orig;
    // 在原有 section 后追加 DYLite 入口 section
    if ([result isKindOfClass:%c(AWESettingsViewModel)]) {
        AWESettingsViewModel *vm = result;
        NSMutableArray *sections = [vm.sectionDataArray mutableCopy];
        if (!sections) sections = [NSMutableArray array];

        AWESettingSectionModel *entrySection = [[%c(AWESettingSectionModel) alloc] init];
        entrySection.sectionHeaderTitle = @"插件";
        entrySection.sectionHeaderHeight = 44.0;

        AWESettingItemModel *entryItem = [[%c(AWESettingItemModel) alloc] init];
        entryItem.identifier = @"DYLiteEntry";
        entryItem.title = @"DYLite 增强设置";
        entryItem.detail = [NSString stringWithFormat:@"v%@", DK_VERSION];
        entryItem.type = 0;
        entryItem.cellType = 26;       // 可点击型：右侧箭头 + detail
        entryItem.colorStyle = 0;
        entryItem.isEnable = YES;

        __weak typeof(result) weakVm = result;
        entryItem.cellTappedBlock = ^{
            // 点击后弹出 DYLite 设置页
            AWESettingBaseViewController *presenter =
                (AWESettingBaseViewController *)[weakVm valueForKey:@"controllerDelegate"];
            if (![presenter isKindOfClass:UIViewController.class]) return;

            AWESettingsViewModel *detailVm = [[%c(AWESettingsViewModel) alloc] init];
            detailVm.sectionDataArray = DKBuildSectionData();
            detailVm.colorStyle = 0;
            detailVm.controllerDelegate = nil;  // 子页无需 delegate

            AWESettingBaseViewController *detailVc =
                [[%c(AWESettingBaseViewController) alloc] init];
            // 用 KVC 把 viewModel 注入进去
            @try {
                [detailVc setValue:detailVm forKey:@"viewModel"];
            } @catch (__unused NSException *e) {}

            detailVc.navigationItem.title = @"DYLite 设置";
            UINavigationController *nav =
                ((UIViewController *)presenter).navigationController;
            if (nav) {
                [nav pushViewController:detailVc animated:YES];
            } else {
                [(UIViewController *)presenter presentViewController:detailVc animated:YES completion:nil];
            }
        };

        entrySection.itemArray = @[ entryItem ];
        [sections addObject:entrySection];
        vm.sectionDataArray = sections;
    }
    return result;
}

%end
