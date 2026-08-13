//
//  DKSettingsMenu.xm
//  ============================================================
//  100% 独立的设置页方案（修复"设置空白"根本原因）
//
//  之前空白的原因：
//    旧代码 hook 了 AWESettingsViewModel 的 init，在 init 时把 sectionDataArray
//    覆写成只含我们入口项的数组 —— 直接把抖音整个设置页的数据冲掉了。
//
//  新方案（零破坏性）：
//    1) 入口 A：hook AWESettingBaseViewController.viewDidLoad，加一个右上角导航按钮
//       "DYLite" —— 完全不碰数据源，绝对不会让设置页空白。
//    2) 入口 B（备份）：hook AWESettingsViewModel.sectionDataArray 的 getter，
//       非破坏性地在末尾追加一个"插件"入口分区（只读不改原数据）。
//    3) 设置详情页：完全自建的 UIKit UITableViewController（DKStandaloneSettingsVC），
//       不依赖 AWESettingBaseViewController / AWESettingsViewModel 的任何渲染逻辑。
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
    NSMutableArray *registry = DKSectionRegistry();
    @synchronized(registry) {
        [registry addObject:@{ @"header": sectionHeader, @"builder": [builder copy] }];
    }
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

    DKGlassLockItemIfNeeded(item);
    return item;
}

#pragma mark - 读取开关值（带默认值）

static BOOL DKSettingsReadValue(NSString *key) {
    // 数字缩写功能默认开
    if ([key isEqualToString:DKKeyNumberAbbreviation]) {
        if ([[NSUserDefaults standardUserDefaults] objectForKey:key] == nil) return YES;
    }
    return DKPrefBool(key);
}

#pragma mark - ============================================================
//  独立设置页 VC（纯 UIKit，零抖音依赖）
//  ============================================================

@interface DKStandaloneSettingsVC : UITableViewController
@end

@implementation DKStandaloneSettingsVC {
    // 每个元素: @{ @"header": NSString, @"items": NSArray }
    // items 里的元素要么是 AWESettingItemModel，要么是关于分区的 NSDictionary
    NSArray *_dkSections;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.title = @"DYLite 设置";
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.estimatedRowHeight = 60;
    self.tableView.rowHeight = UITableViewAutomaticDimension;

    [self dk_buildSections];
}

- (void)dk_buildSections {
    NSMutableArray *sections = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray *> *groups = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *order = [NSMutableArray array];

    NSMutableArray *registry = DKSectionRegistry();
    NSArray *snapshot;
    @synchronized(registry) {
        snapshot = [registry copy];
    }

    for (NSDictionary *entry in snapshot) {
        NSString *header = entry[@"header"];
        DKSettingItemBuilder builder = entry[@"builder"];
        if (!header || !builder) continue;
        @try {
            AWESettingItemModel *item = builder();
            if (!item) continue;
            if (!groups[header]) {
                groups[header] = [NSMutableArray array];
                [order addObject:header];
            }
            [groups[header] addObject:item];
        } @catch (__unused NSException *e) {}
    }

    for (NSString *header in order) {
        [sections addObject:@{ @"header": header, @"items": [groups[header] copy] }];
    }

    // 关于分区（始终存在，保证页面永远不会空白）
    [sections addObject:@{
        @"header": @"关于",
        @"items": @[
            @{ @"__about__": @(YES),
               @"title": [NSString stringWithFormat:@"DYLite v%@", DK_VERSION],
               @"detail": @"抖音增强插件 · 独立设置页" }
        ]
    }];

    _dkSections = [sections copy];
}

#pragma mark - Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    return _dkSections.count;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if (section < 0 || section >= (NSInteger)_dkSections.count) return 0;
    return [_dkSections[section][@"items"] count];
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    if (section < 0 || section >= (NSInteger)_dkSections.count) return nil;
    return _dkSections[section][@"header"];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    id raw = nil;
    @try {
        raw = _dkSections[indexPath.section][@"items"][indexPath.row];
    } @catch (__unused NSException *e) {}

    // 关于分区
    if ([raw isKindOfClass:[NSDictionary class]]) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                       reuseIdentifier:@"dk_about"];
        NSDictionary *d = (NSDictionary *)raw;
        cell.textLabel.text = d[@"title"];
        cell.detailTextLabel.text = d[@"detail"];
        cell.detailTextLabel.textColor = [UIColor grayColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.numberOfLines = 0;
        return cell;
    }

    AWESettingItemModel *item = (AWESettingItemModel *)raw;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                   reuseIdentifier:@"dk_switch"];
    cell.textLabel.text       = item.title ?: @"";
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.text = item.detail ?: @"";
    cell.detailTextLabel.textColor = [UIColor grayColor];
    cell.detailTextLabel.numberOfLines = 0;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    UISwitch *sw = [[UISwitch alloc] init];
    sw.tag = (NSInteger)indexPath.section * 10000 + (NSInteger)indexPath.row;
    [sw addTarget:self action:@selector(dk_switchChanged:) forControlEvents:UIControlEventValueChanged];
    sw.on = DKSettingsReadValue(item.identifier);
    sw.enabled = item.isEnable;
    cell.accessoryView = sw;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tv deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - Switch 回调

- (void)dk_switchChanged:(UISwitch *)sender {
    NSInteger section = sender.tag / 10000;
    NSInteger row = sender.tag % 10000;
    @try {
        id raw = _dkSections[section][@"items"][row];
        if (![raw isKindOfClass:NSClassFromString(@"AWESettingItemModel")]) return;
        AWESettingItemModel *item = (AWESettingItemModel *)raw;
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud setBool:sender.on forKey:item.identifier];
        [ud synchronize];
        item.isSwitchOn = sender.on;
    } @catch (__unused NSException *e) {}
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:section]]
                          withRowAnimation:UITableViewRowAnimationNone];
}

@end

#pragma mark - ============================================================
//  入口跳转 Target（导航按钮 & cell 点击都用它）
//  ============================================================

@interface DKSettingsEntryTarget : NSObject
+ (instancetype)shared;
- (void)openSettings;
@end

@implementation DKSettingsEntryTarget

+ (instancetype)shared {
    static DKSettingsEntryTarget *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [DKSettingsEntryTarget new]; });
    return s;
}

- (void)openSettings {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = [UIApplication sharedApplication].keyWindow;
        if (!w) {
            for (UIWindow *win in [UIApplication sharedApplication].windows) {
                if (win.windowLevel == UIWindowLevelNormal && win.bounds.size.width > 0) {
                    w = win;
                    break;
                }
            }
        }
        if (!w) return;

        UIViewController *top = w.rootViewController;
        while (top.presentedViewController) top = top.presentedViewController;
        while ([top isKindOfClass:[UINavigationController class]]) {
            UINavigationController *nav = (UINavigationController *)top;
            UIViewController *visible = nav.visibleViewController ?: nav.topViewController;
            if (visible && visible != top) {
                top = visible;
                if (top.presentedViewController) {
                    top = top.presentedViewController;
                    continue;
                }
            }
            break;
        }

        DKStandaloneSettingsVC *vc = [[DKStandaloneSettingsVC alloc] initWithStyle:UITableViewStyleGrouped];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        [top presentViewController:nav animated:YES completion:nil];
    });
}

@end

#pragma mark - ============================================================
//  入口 A：抖音设置页右上角导航按钮（非破坏性，推荐入口）
//  ============================================================

%group DKEntryNavButton

%hook AWESettingBaseViewController

- (void)viewDidLoad {
    %orig;
    @try {
        UIBarButtonItem *btn = [[UIBarButtonItem alloc] initWithTitle:@"DYLite"
                                                                 style:UIBarButtonItemStylePlain
                                                                target:[DKSettingsEntryTarget shared]
                                                                action:@selector(openSettings)];
        self.navigationItem.rightBarButtonItem = btn;
    } @catch (__unused NSException *e) {}
}

%end

%end

#pragma mark - ============================================================
//  入口 B（备份）：sectionDataArray getter 末尾追加"插件"入口
//  非破坏性 —— 只读 %orig 再追加，永远不调用 setter，不会冲掉原数据
//  ============================================================

%group DKEntrySection

%hook AWESettingsViewModel

- (NSArray *)sectionDataArray {
    NSArray *orig = %orig;
    if (!orig) orig = @[];

    // 安全检查：如果原数据里已经有 DYLiteEntry 就不重复追加
    for (id sec in orig) {
        if (![sec isKindOfClass:NSClassFromString(@"AWESettingSectionModel")]) continue;
        NSArray *items = [(AWESettingSectionModel *)sec itemArray];
        for (id it in items) {
            if (![it isKindOfClass:NSClassFromString(@"AWESettingItemModel")]) continue;
            if ([[(AWESettingItemModel *)it identifier] isEqualToString:@"DYLiteEntry"]) {
                return orig;
            }
        }
    }

    AWESettingItemModel *entryItem = [[%c(AWESettingItemModel) alloc] init];
    if (!entryItem) return orig;
    entryItem.identifier = @"DYLiteEntry";
    entryItem.title      = @"DYLite 增强设置";
    entryItem.detail     = [NSString stringWithFormat:@"v%@  >  点击进入", DK_VERSION];
    entryItem.type       = 0;
    entryItem.cellType   = 26;           // 可点击：右侧箭头
    entryItem.colorStyle = 0;
    entryItem.isEnable   = YES;
    entryItem.cellTappedBlock = ^{
        [[DKSettingsEntryTarget shared] openSettings];
    };

    AWESettingSectionModel *entrySection = [[%c(AWESettingSectionModel) alloc] init];
    if (!entrySection) return orig;
    entrySection.sectionHeaderTitle  = @"插件";
    entrySection.sectionHeaderHeight = 44.0f;
    entrySection.itemArray           = @[ entryItem ];

    return [orig arrayByAddingObject:entrySection];
}

%end

%end

#pragma mark - 构造函数

%ctor {
    %init(DKEntryNavButton);
    %init(DKEntrySection);
}
