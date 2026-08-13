# DYLite —— 抖音 UI 增强插件

> Windows 用户专属指南 | 无需安装任何开发环境 | 云端自动编译

---

## 功能列表

| 功能 | 说明 | 系统要求 |
|------|------|----------|
| 评论区液态玻璃 | 评论面板+输入框加 iOS 26 原生玻璃 | iOS 26+ |
| 分享面板液态玻璃 | 分享弹层加玻璃效果 | iOS 26+ |
| 视频全屏 | 去除底栏遮挡，视频撑满屏幕 | iOS 14+ |
| 移除「去汽水听」 | 隐藏视频下方推广入口 | iOS 14+ |
| 移除关注按钮 | 隐藏视频页右侧「+关注」 | iOS 14+ |

---

## Windows 用户：3 步拿到安装包

### 第 1 步：注册 GitHub 账号（5 分钟）

1. 打开 https://github.com/signup
2. 填邮箱、密码、用户名，完成注册
3. 登录 GitHub

### 第 2 步：上传项目到 GitHub（1 分钟）

**直接双击 `推送代码(点我).bat` 即可！**

脚本会自动：
- 设置 Token（已嵌入）
- 推送全部代码
- 自动清理 Token URL
- 打开 GitHub Actions 编译页面

> 如果双击失败，改用手动：
> 1. 创建 GitHub 空仓库 https://github.com/new （名字 DYLite，不勾任何选项）
> 2. 在项目目录右键 → Git Bash Here → 执行：
>    ```git remote set-url origin https://3316684686LJH-ops/DYLite.git && git push -u origin main```

### 第 3 步：下载安装包（等 3-5 分钟）

1. 脚本自动打开 https://github.com/3316684686LJH-ops/DYLite/actions
2. 看到绿色 ✅ 说明编译成功
3. 点进去 → 滚到底部 Artifacts → 下载 DYLite-packages ZIP
4. 解压得到 3 个 .deb 文件

---

## 安装到手机

### 你需要：
- 一台已越狱的 iPhone（iOS 14+）
- 越狱商店（Sileo / Zebra / Cydia）

### 步骤：

1. **选对 deb 包**——根据你的越狱类型选：
   | 越狱工具 | 越狱类型 | 对应的 deb |
   |----------|----------|-----------|
   | Dopamine | rootless | `arm64-rootless.deb` |
   | Taurine | rootless | `arm64-rootless.deb` |
   | checkra1n | rootful | `arm-rootful.deb` |
   | palera1n | rootful | `arm-rootful.deb` |
   | Bootstrap | roothide | `arm64e-roothide.deb` |

2. **传到手机**——任选一种：
   - AirDrop 传到手机 → 用"文件"App 打开
   - 用爱思助手 / 3uTools 传文件
   - 上传到网盘 → 手机下载

3. **安装 deb**——任选一种：
   - "文件"App → 点 deb → "用 Sileo 安装"
   - Filza 文件管理器 → 点 deb → 安装
   - 终端：`dpkg -i /path/to/DYLite.deb`

4. **使用插件**：
   - 杀掉抖音重开
   - 进入 `我 → 设置 → 拉到最底部 → 插件 → DYLite 设置`
   - 打开你想要的功能开关

---

## 修改版本号 / 作者名

打开 `control` 文件，修改：
```
Package: com.你的名字.dylite     ← 包名（唯一标识）
Name: DYLite                     ← 显示名
Version: 0.1.0                   ← 版本号
Maintainer: 你的名字              ← 作者
Author: 你的名字                  ← 作者
```

改完后重新上传到 GitHub，会自动重新编译。

---

## 常见问题

### Q: GitHub Actions 编译失败怎么办？
A: 打开 Actions 页面，点击失败的记录，查看红色错误信息。常见原因：
- SDK 下载失败（网络问题，重新触发即可）
- 代码语法错误（错误信息会告诉你是哪个文件哪一行）

### Q: 编译成功但装上没效果？
A:
1. 确认选对了 deb 架构（rootful/rootless/roothide）
2. 安装后杀掉抖音重开
3. 去 `抖音设置 → 插件 → DYLite 设置` 开开关
4. 开关后可能需要退出当前页面再进才生效

### Q: 液态玻璃开关是灰色的？
A: 液态玻璃需要 iOS 26+，你的系统版本不够。其他功能不受影响。

### Q: 推送代码时提示密码错误？
A: GitHub 已不支持用密码推送，必须用 Token：
1. 打开 https://github.com/settings/tokens/new
2. 勾选 `repo` → 生成 token
3. 把 token 当密码粘贴

### Q: 不会用 Git，有没有更简单的上传方式？
A: 可以直接在 GitHub 网页上传：
1. 创建空仓库（不勾选 README）
2. 点 `uploading an existing file`
3. 把项目所有文件拖进去（不要传 `.theos` 和 `packages` 文件夹）
4. 点 `Commit changes`

> 注意：网页上传不会包含 `.github/workflows/build.yml` 的话就不会自动编译。
> 一定要确保 `.github` 文件夹也上传了。

---

## 项目结构

```
DYLite/
├── .github/workflows/build.yml   ← GitHub 自动编译配置
├── 推送代码(点我).bat             ← Windows 一键上传（含Token）
├── Makefile                      ← Theos 编译配置
├── control                       ← deb 包信息
├── DYLite.plist                  ← 注入过滤器
└── src/
    ├── Headers/DouyinHeaders.h   ← 抖音私有类声明
    ├── Shared/                   ← 共享工具
    │   ├── DKKeys.h              ← 开关键定义
    │   ├── DKGlassGuard.h/.m     ← 玻璃版本守卫
    │   ├── DKGlassRuntime.h/.m   ← 运行时反射层（iOS 26 API 访问）
    │   └── DKUtils.h/.m          ← 工具函数
    ├── Settings/
    │   └── DKSettingsMenu.xm     ← 设置菜单注入
    └── Features/                 ← 功能模块
        ├── Comment/DKCommentGlass.xm      ← 评论区玻璃
        ├── Share/DKSharePanelGlass.xm     ← 分享面板玻璃
        ├── VideoFullscreen/DKVideoGeometry.xm ← 视频全屏
        └── Interaction/
            ├── DKRemoveQushuiting.xm      ← 移除去汽水听
            └── DKHideFollowButton.xm      ← 移除关注按钮
```

---

## 免责声明

仅供学习研究使用，严禁商业用途。使用者自行承担风险。
