//
//  DKSettingsMenu.xm
//  注入 DYLite 设置入口 + 弹出插件设置页
//  ============================================================
//  修复"空白页"原因：
//  1) 自己 alloc 的 AWESettingsViewModel 不能直接 setSectionDataArray 就完事，
//     因为 sectionDataArray 里的 section / item 可能还需要经过官方的进一步处理
//     才能被 VC 的 data source 认出来。
//  2) 用 objc_setAssociatedObject 给我们 detailVm 打一个"DYLite VM"标签，
//     然后 hook sectionDataArray 的 getter，让它在运行时返回我们实时构建的数据，
//     完美避开各功能模块 %ctor 注册顺序导致的空数组。
//  3) 补齐 viewModel / item 常用属性，降低抖音内部数据源断言/异常的几率。
//

#import "DouyinHeaders.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import <objc/runtime.h>
#import <objc/message.h>

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
    if (!item) return nil;

    item.identifier = key.length ? key : [NSUUID UUID].UUIDString;
    item.title      = title ?: @"";
    item.detail     = detail ?: @"";
    item.type       = 0;
    item.cellType   = 6;               // 开关型 cell
    item.colorStyle = 0;
    item.isEnable   = YES;
    item.isSwitchOn = DKPrefBool(key);

    __weak AWESettingItemModel *weakItem = item;
    item.switchChangedBlock = ^{
        __strong AWESettingItemModel *it = weakItem;
        if (!it) return;
        BOOL v = !it.isSwitchOn;
        it.isSwitchOn = v;
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud setBool:v forKey:it.identifier];
        [ud synchronize];
    };
    DKGlassLockItemIfNeeded(item);
    return item;
}

#pragma mark - 动态构建设置页 section（每次 getter 调用都会重新构建，确保永远有数据）

static NSArray *DKBuildSectionData(void) {
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
        if (!section) continue;
        section.sectionHeaderTitle  = header;
        section.sectionHeaderHeight = 44.0f;
        section.itemArray           = groups[header];
        [sections addObject:section];
    }
    return sections;
}

#pragma mark - DYLite VM 标签 + getter hook

static const void *kDKIsDYLiteVMTagKey = &kDKIsDYLiteVMTagKey;
static const void *kDKCachedSectionsKey  = &kDKCachedSectionsKey;

static void DKTagAsDYLiteVM(AWESettingsViewModel *vm) {
    if (!vm) return;
    objc_setAssociatedObject(vm, kDKIsDYLiteVMTagKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL DKIsDYLiteVM(id vm) {
    return [objc_getAssociatedObject(vm, kDKIsDYLiteVMTagKey) boolValue];
}

%group DKSettingsVMHook

%hook AWESettingsViewModel

- (NSArray *)sectionDataArray {
    if (DKIsDYLiteVM(self)) {
        // 自己的 DYLite 设置页 VM：每次都返回实时构建数据 + 缓存
        NSArray *cached = objc_getAssociatedObject(self, kDKCachedSectionsKey);
        if (cached) return cached;
        NSArray *built = DKBuildSectionData();
        objc_setAssociatedObject(self, kDKCachedSectionsKey, built, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return built;
    }
    return %orig;
}

- (NSInteger)colorStyle {
    if (DKIsDYLiteVM(self)) return 0;
    return %orig;
}

- (void)setColorStyle:(NSInteger)style {
    if (DKIsDYLiteVM(self)) return;
    %orig;
}

%end

%end

#pragma mark - 入口注入：抖音主设置页 sectionDataArray 末尾追加 "插件" 分区

%group DKEntryHook

%hook AWESettingsViewModel

- (instancetype)init {
    self = %orig;
    if (!self) return nil;

    // 不要在 DYLite 自己的 VM 上再加入口了（否则无限递归）
    if (DKIsDYLiteVM(self)) return self;

    @try {
        NSMutableArray *sections = [self respondsToSelector:@selector(sectionDataArray)]
            ? [[(id)self sectionDataArray] mutableCopy]
            : nil;
        if (!sections) sections = [NSMutableArray array];

        AWESettingSectionModel *entrySection = [[%c(AWESettingSectionModel) alloc] init];
        entrySection.sectionHeaderTitle  = @"插件";
        entrySection.sectionHeaderHeight = 44.0f;

        AWESettingItemModel *entryItem = [[%c(AWESettingItemModel) alloc] init];
        entryItem.identifier = @"DYLiteEntry";
        entryItem.title      = @"DYLite 增强设置";
        entryItem.detail     = [NSString stringWithFormat:@"v%@", DK_VERSION];
        entryItem.type       = 0;
        entryItem.cellType   = 26;           // 可点击：右侧箭头
        entryItem.colorStyle = 0;
        entryItem.isEnable   = YES;

        __weak AWESettingsViewModel *weakSelf = self;
        entryItem.cellTappedBlock = ^{
            AWESettingsViewModel *strongSelf = weakSelf;
            if (!strongSelf) return;

            // 获取当前 VC presenter
            UIViewController *presenter = nil;
            @try {
                id del = [strongSelf valueForKey:@"controllerDelegate"];
                if ([del isKindOfClass:UIViewController.class]) presenter = del;
            } @catch (__unused NSException *e) {}
            if (!presenter) {
                // 兜底：取最顶层的 VC
                UIWindow *w = [UIApplication sharedApplication].keyWindow;
                presenter = w.rootViewController;
                while (presenter.presentedViewController) presenter = presenter.presentedViewController;
            }
            if (!presenter) return;

            // 创建 detail VM
            AWESettingsViewModel *detailVm = [[%c(AWESettingsViewModel) alloc] init];
            detailVm.colorStyle = 0;
            DKTagAsDYLiteVM(detailVm);
            // 先调用一下 sectionDataArray 强制预热缓存（可选）
            (void)[detailVm sectionDataArray];

            // 创建设置页 VC：优先尝试官方的初始化方法，失败再 fallback
            AWESettingBaseViewController *detailVc = nil;
            @try {
                // 尝试 initWithViewModel:（如有）
                SEL initSel = NSSelectorFromString(@"initWithViewModel:");
                if ([[AWESettingBaseViewController class] instancesRespondToSelector:initSel]) {
                    id (*msgSend)(id, SEL, id) = (typeof(msgSend))objc_msgSend;
                    detailVc = msgSend([%c(AWESettingBaseViewController) alloc], initSel, detailVm);
                }
            } @catch (__unused NSException *e) {}

            if (!detailVc) {
                detailVc = [[%c(AWESettingBaseViewController) alloc] init];
                if (detailVc) {
                    @try { [detailVc setValue:detailVm forKey:@"viewModel"]; } @catch (__unused NSException *e) {}
                }
            }
            if (!detailVc) return;

            detailVc.navigationItem.title = @"DYLite 设置";

            // 页面进去之后强制再刷新一次（解决空白页杀手锏）
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                @try {
                    SEL reloadSel = NSSelectorFromString(@"reloadData");
                    if ([detailVc respondsToSelector:reloadSel]) {
                        void (*msgSend)(id, SEL) = (typeof(msgSend))objc_msgSend;
                        msgSend(detailVc, reloadSel);
                    }
                    // 尝试获取内部 tableView 也 reload 一下
                    for (UIView *v in [detailVc.view subviews]) {
                        if ([v isKindOfClass:[UITableView class]]) {
                            [(UITableView *)v reloadData];
                        }
                    }
                } @catch (__unused NSException *e) {}
            });

            UINavigationController *nav = presenter.navigationController;
            if (nav) {
                [nav pushViewController:detailVc animated:YES];
            } else {
                UINavigationController *n = [[UINavigationController alloc] initWithRootViewController:detailVc];
                n.modalPresentationStyle = UIModalPresentationFullScreen;
                [presenter presentViewController:n animated:YES completion:nil];
            }
        };

        entrySection.itemArray = @[ entryItem ];
        [sections addObject:entrySection];

        // 赋值回去（如果不可写就用 KVC 兜底）
        @try {
            self.sectionDataArray = sections;
        } @catch (__unused NSException *e) {
            @try { [self setValue:sections forKey:@"sectionDataArray"]; } @catch (__unused NSException *e2) {}
        }
    } @catch (__unused NSException *e) {}

    return self;
}

%end

%end

#pragma mark - 构造函数

%ctor {
    // 先把 group 初始化（Logos 语法要求）
    %init(DKSettingsVMHook);
    %init(DKEntryHook);
}
