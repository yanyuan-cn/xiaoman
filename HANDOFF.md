# 项目交接：小满（xiaoman）— v1.1.0

> 本包由原开发环境（Android 手机上的 Ubuntu）打包。目标是让另一个智能体/开发者能在一个 Windows 机器上接手：改 bug、加功能、发版。
> 包内：`xiaoman/`（源码，57 文件）、`HANDOFF.md`（本文）、`KNOWN-ISSUES.md`（**需要修的问题清单，先看这个**）、`PATHS.md`、`ENVIRONMENT.md`、`git-state.txt`、`reference/`（已修好的 CI 配置与线上 version.json 原文）。

## 1. 这是什么

个人自用、**本地优先**的 Android 记账 App。

- 技术栈：Flutter（Dart）+ 本地 SQLite（sqflite），无后端、无账号、无云同步
- 目标平台：仅 Android（已适配 Android 8+ 自适应图标）；无 iOS 工程
- 唯一网络行为：检查更新（GET `version.json`）+ 下载新 APK
- 包名 `com.xiaoman.xiaoman`，桌面名「小满」
- 当前版本 **1.1.0+13**，已发布并在真机安装验证

## 2. 当前状态

### 仓库同步状态（2026-11-04 实测）

GitHub `main` 已经和本包源码基本同步。用 git blob SHA 逐文件比对（57 个源码文件 + 远端 58 个含 `pubspec.lock`）：

| 结果 | 数量 | 明细 |
|---|---|---|
| 完全一致 | 54 | `lib/**`、`assets/**`、`pubspec.yaml`、`scripts/**` 等 |
| 内容不同 | 2 | `.github/workflows/android.yml`（远端缺 INTERNET 注入）、`analysis_options.yaml`（远端更好） |
| 远端缺 | 1 | `tools/gen_icon.py` |
| 本地缺 | 1 | `pubspec.lock`（远端有，是好事） |
| 刻意不同步 | 1 | `version.json`（本地这份是旧的 1.0.2/12，**绝不要上传**） |

也就是说：**v1.1.0 源码已经在仓库里了**，剩下的差异只有上面 4 项，都在 `KNOWN-ISSUES.md` 里。

### 能不能构建

- **打包环境里不能**：aarch64 Linux，没有 Flutter，官方 Linux 包只有 x64（细节见 `ENVIRONMENT.md`）。
- **你的 Windows 上可以**：v1.1.0 就是在那台机器上构建、签名、发版并真机安装成功的。

在项目根目录（PowerShell）：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\init_android.ps1
flutter pub get
flutter build apk --release
```

产物 `build\app\outputs\flutter-apk\app-release.apk`（约 54.7 MB）。

**必须先跑 `init_android.ps1`**，它做四件事：生成 `android/`、改桌面名为「小满」、注入 `INTERNET` 与 `REQUEST_INSTALL_PACKAGES` 权限、把 `assets\icon\res\*` 复制成启动图标。漏了它，release 包会没有联网权限。

### 功能清单（均已在真机验证）

| 模块 | 内容 |
|---|---|
| 记账 | 支出/收入/转账；一级分类必选、二级可选；自绘数字键盘；日期、账户、备注；逐笔「计入预算」开关 |
| 流水 | 首页按月、按日分组、月度支出/收入/结余；详情页；编辑；删除后 5 秒可撤销 |
| 资产 | 账户增改、类型（活期/定期/银行卡/钱包/现金）、余额（填实际值反推期初）、负债标记、是否计入总资产；净资产 = 资产 − 负债 |
| 导入 | CSV 自研解析；指纹去重；批次可整批撤销；导入可勾「不计入预算」 |
| 导出 | 流水 CSV、全量备份 JSON（**只导不进**） |
| 统计 | 月/年切换；月视图环形饼图（一级分类，>6 项归并「其他」）+ 分类榜 + 近 6 月柱状；年视图 12 月双柱 + 支出/收入分布条 |
| 预算 | 总额/餐饮/购物三档；周期「每月固定日 1–28」或「每周」；首页收支卡下方显示已用/剩余/进度条，负数标红 |
| 定期扣款 | 规则（金额、每月几号、扣款账户、可选还款账户、分类、备注）；到日自动生成；启动与首页都补跑；可撤销 |
| 分类管理 | 新建一级/二级、重命名、隐藏、级联归档 |
| 系统 | 应用内检查更新→下载→SHA-256 校验→调起安装；更新源可自定义；存储占用统计与清理；启动申请高刷 |

**已知缺口**：备份不能恢复；导入只吃 CSV；预算的餐饮/购物靠分类名硬匹配；CI 只出 debug 包。

## 3. 关键决策及理由

**这些决定是有意的，不要顺手改回去。**

- **金额一律存「分」的 int，禁止 double** —— 浮点误差会让人对不上账。
- **时间存 UTC 毫秒**，只在显示时转本地。
- **转账是 txns 的单条记录**（`kind='transfer'` + `to_account_id`），不是两条 —— 不会重复计入支出，撤销只需删一条。
- **软删除**（`deleted_at`），首页删除后 5 秒可撤销。
- **导入去重用指纹** `FNV-1a(kind|amount|分钟|note)`，写进 `dedup_hash`。
- **sqflite 手写 SQL，不用 drift** —— 开发期本机没有 Flutter，跑不了 `build_runner`。换 drift 等于重写 `repo.dart`。
- **不用 provider/riverpod/bloc** —— 只有 `DataBus`（ChangeNotifier 单例）做跨页刷新，其余手写 `setState`。
- **更新机制不用 GitHub API**，用仓库里的 `version.json` 比 `versionCode`；四级回退：GitHub Pages → ghproxy → jsdelivr → raw.githubusercontent.com。
- **继续用 Flutter 默认 debug keystore 签名** —— 换正式签名会导致已装用户无法覆盖安装、只能卸载（丢数据）。要换必须先做备份恢复。
- **`android/` 被 `.gitignore` 排除**，靠 `scripts/init_android.ps1` 现场生成；图标放 `assets/icon/res/` 由脚本复制进去。
- **版本号三段式**：第二位=功能、第三位=修复、满 10 进位。三处同步：`pubspec.yaml`、`lib/core/version.dart`（`kAppVersion`/`kAppBuild`）、仓库根 `version.json` 的 `versionCode`。
- **发布是手工的**：build → `Get-FileHash` → 发 Release（Tag 和 Title 都写 `vX.Y.Z`）→ 改 `version.json`（apkUrl + sha256）→ 手机检查更新。

## 4. 代码结构

```
lib/
  main.dart                 入口：开库 → 清更新缓存 → 补跑定期扣款 → 申请高刷 → runApp
  core/
    money.dart              元/分互转与格式化
    dates.dart              日期工具、UTC 毫秒
    storage.dart            缓存/数据库体积、清理
    display.dart            高刷新率（flutter_displaymode）
    version.dart            版本号 + 更新日志
    budget_period.dart      预算周期（每月固定日 / 每周）
  data/
    db.dart                 建表与迁移（kDbVersion = 3）
    models.dart             Txn / Account / TxnCategory / BudgetRule / RecurringRule
    repo.dart               所有读写（唯一数据入口，约 800 行）
    update_service.dart     取 version.json、多源回退、自定义源
    apk_updater.dart        下载 APK、SHA-256、调起安装
    import/csv.dart         手写 CSV 解析
    import/draft.dart       表头定位、逐行转换
  state/
    ledger.dart             首页状态（含预算汇总）
    data_bus.dart           跨页刷新信号
  features/<模块>/          一页一目录：home ledger record detail assets account stats
                            categories import profile budget recurring
assets/icon/res/            启动图标（由 tools/gen_icon.py 生成，勿手改 PNG）
tools/gen_icon.py           图标生成脚本（Pillow + 中文字体）
scripts/init_android.ps1    生成 android/、中文名、权限、图标
test/money_test.dart        金额工具单测
.github/workflows/android.yml 云端构建（debug）
```

**自动生成、不要手改**：`android/`、`build/`、`.dart_tool/`、`assets/icon/res/*.png`（改样式就改 `tools/gen_icon.py` 重跑）。

## 5. 环境

必须匹配的只有三样：

| 组件 | 要求 | 不匹配会怎样 |
|---|---|---|
| Flutter | 3.47.9 stable | 版本差异会报 API 不存在 |
| JDK | 17 | Gradle 直接拒绝 |
| Android SDK | platform 36 + build-tools + NDK **28.2.13676358** | 报 `did not install NDK 28.2.13676358` |

详见 `ENVIRONMENT.md`。国内建议设镜像：`PUB_HOSTED_URL=https://pub.flutter-io.cn`、`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`。

## 6. 接手后的顺序（建议）

1. 读 `KNOWN-ISSUES.md`，先修 I-1（CI 缺 INTERNET）和 I-2/I-3/I-4 这几个「仓库与本地不一致」的小问题。
2. 在 Windows 上跑一遍 `init_android.ps1` + `flutter build apk --release`，确认能出包（这一步原环境从未验证过）。
3. 然后按优先级做功能：**备份恢复**（最大数据风险）→ 搜索筛选 → 导入增强 → 预算按分类 id。
4. 清 `flutter analyze` 的 info（15 条，不影响构建）。

## 7. 坑和地雷

1. **release 包缺 INTERNET 权限**（踩过一次，浪费一整轮发布）：现象是应用内检查更新永远「连接失败，已尝试 5 个地址」，但浏览器能打开同一 URL。原因：Flutter 模板只把 `INTERNET` 写进 `debug/AndroidManifest.xml`，主清单没有。注入必须在**打包之前**。
2. **必须先 `init_android.ps1` 再 build**，否则图标是默认 Flutter 图标、权限也缺。
3. **签名一致性**：现在是 `C:\Users\<用户名>\.android\debug.keystore`。换电脑/重装/删文件都会生成新 keystore → `INSTALL_FAILED_UPDATE_INCOMPATIBLE`，只能卸载（丢数据）。
4. **Release 附件没上传也能 Publish**：发完一定点开 Release 看有没有 `app-release.apk`（v1.1.0 因此 404 过一次）。
5. **`version.json` 的 sha256 必须 64 位**，取自 `Get-FileHash app-release.apk -Algorithm SHA256`。
6. **GitHub Pages 有缓存**，应用请求已带 `?t=时间戳`，但 Pages 本身可能滞后几分钟。
7. **`DropdownButtonFormField(initialValue:)` 新版行为不稳**，`recurring_page.dart` 已改成自定义 `_dropdown<T>`，别改回去。
8. **数据库迁移只真机跑过 v1.0.2 → v1.1.0（v2→v3）**；`v1→v3` 连续升级、空库直接建 v3 后升级都没单独测。迁移用 `PRAGMA table_info` 判断，理论幂等。
9. **预算按分类名硬匹配**（`食品餐饮`、`购物消费`），改名即失联。
10. **试过但失败的路（别重复）**：arm64 装 Flutter（官方只有 x64）；qemu + `libc6:amd64`（apt 源只有 arm64）；`excel` 包解析 `.xls`（只支持 xlsx）；Windows 记事本另存 `.yml` 会变成 `.yml.txt`（隐藏扩展名）。
11. **Gradle 增量缓存偶发失败**（`Could not close incremental caches ... caches-jvm`）：`android/gradle.properties` 加 `kotlin.incremental=false` 与 `org.gradle.caching=false`；`android/` 重新生成后这两行会丢，要重加。
12. **YAML heredoc 缩进敏感**：`.github/workflows/android.yml` 里 `PY` 结束符必须与 `import` 行同缩进（10 空格），多一个空格整段 python 就失效。

## 8. 我还不确定的地方

- **没有 git 历史**：项目从未在本地 `git init`，所有上传走 GitHub 网页，所以给不出 commit hash / diff。见 `git-state.txt`（已按今天的实测重写）。
- **本包源码没有经过任何编译**（打包环境不能构建）。v1.1.0 的 APK 是原用户在 Windows 上构建的，构建前 `flutter analyze` 报过 1 个 error（`repo.dart:612`，已修）和 2 个未使用 import（已删），修完后没再跑过 analyze。
- **`minSdk`/`targetSdk` 看不到**：`android/` 不在包里，由 `flutter create` 决定；真机 Android 16 可跑。
- **`pubspec.lock` 不在本包**，但在仓库里（远端有）。以仓库那份为准，`sqflite` 已知解析到 2.4.5。
- `test/money_test.dart` 只测金额工具，其余逻辑零测试。
