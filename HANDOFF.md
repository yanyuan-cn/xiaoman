# 项目交接：小满（xiaoman）

> 最后更新：2026-11-05 · 对应 **v2.0.0+24**
>
> 先读这份，再读 `KNOWN-ISSUES.md`（缺陷与取舍）和 `SETUP.md`（环境与命令）。
> `PATHS.md` / `ENVIRONMENT.md` / `git-state.txt` 是第一次交接时的环境快照，仅作历史参考。

## 1. 这是什么

个人自用、**本地优先**的 Android 记账 App。

- 技术栈：Flutter 3.47.9 / Dart 3.13.7 + sqflite（手写 SQL，无 ORM）
- 目标平台：仅 Android（`minSdk` 由 Flutter 模板决定，真机 Android 16 可用）
- 唯一联网行为：检查更新（GET `version.json`）+ 下载新 APK
- 包名 `com.xiaoman.xiaoman`，桌面名「小满」

## 2. 现在是什么状态

- **仓库和本机一致**，`main` 干净，CI（debug 构建）为绿。
- **能构建**：`flutter build apk --release` 实测通过（约 55 MB）。
- **能发版**：`scripts/release.ps1` 一条命令跑完全流程（见 §4）。
- **有视觉规范**：全部颜色/字号/圆角/动效曲线收在 `lib/core/theme.dart`，
  来源是设计交付包《小满设计规范》（§2 设计系统、§4 页面、§5 动效）。
- **有深色模式**：跟随系统 / 浅色 / 深色，我的 → 外观 → 外观模式。

功能面：记账（收支转）、流水、资产/账户、CSV 导入、CSV/JSON 导出、**从备份恢复**、
统计图表、预算、定期扣款、分类管理、**搜索筛选**、应用内更新、**应用图标切换**。

仍然缺的：xlsx/xls 导入、统计的更多维度、心情/状态的统计视图。
（历史缺口见 `KNOWN-ISSUES.md` 文末「已关闭」。）

## 3. 代码结构

```
lib/
  main.dart                 入口：开库 → 清缓存 → 补跑定期扣款 → 申请高刷 → runApp
  core/
    theme.dart              设计 token（颜色/字号/圆角/阴影/渐变）+ ThemeData
    theme_mode.dart         外观模式控制器（system/light/dark）
    money.dart              元/分互转与格式化
    dates.dart              日期工具、UTC 毫秒
    storage.dart            缓存/数据库体积、清理
    display.dart            高刷新率
    version.dart            版本号 + 更新日志 + 更新源列表
    budget_period.dart      预算周期
    app_icon.dart           桌面图标切换（MethodChannel 到 MainActivity）
  data/
    db.dart                 建表与迁移（kDbVersion = 4）
    models.dart             Txn / Account / TxnCategory / BudgetRule / RecurringRule / XmMood
    repo.dart               所有读写（唯一数据入口）
    update_service.dart     取 version.json、多源回退
    apk_updater.dart        下载 APK、SHA-256、调起安装
    import/decode.dart      编码探测（UTF-8 / BOM / GBK / GB18030）
    import/csv.dart         手写 CSV 解析
    import/draft.dart       表头定位、逐行转换
  ui/motion.dart            「从这一行放大进来」的路由与面板（XmExpandRoute / showXmExpandSheet）
  ui/components.dart        原子组件 + 统一界面语言（XmPageScaffold / XmSegmented / XmChoice / XmField / XmScrollTabs）
  state/                    首页状态、跨页刷新信号
  features/<模块>/          一页一目录
assets/icon/res/            启动图标（D1 深色 + D3 浅色两套，含自适应图标 XML）
scripts/init_android.ps1    生成 android/、权限、图标别名、Kotlin 模板
scripts/release.ps1         一键发版
scripts/android/MainActivity.kt  图标切换的原生实现（生成目录会被覆盖，源文件放这里）
test/                       金额与编码的单测
```

**自动生成、不要手改**：`android/`、`build/`、`.dart_tool/`。
`android/` 里的东西全部由 `scripts/init_android.ps1` 重建，**要改就改脚本**。

## 4. 构建与发版

```powershell
# 本地跑
powershell -ExecutionPolicy Bypass -File scripts\init_android.ps1
flutter pub get
flutter run

# 发版（自动：构建 → 校验版本 → 建 Release → 传 APK → 改 version.json → 推送）
powershell -ExecutionPolicy Bypass -File scripts\release.ps1 -Yes -Notes "这次改了什么"
```

发版前要手动做的一件事：把 `pubspec.yaml` 与 `lib/core/version.dart` 的版本号一起加一
（脚本会校验两者一致，不一致直接拒绝发版）。`version.json` 由脚本自动改。

环境要求见 `SETUP.md`：Flutter 3.47.9、JDK 17、Android SDK platform 36、
NDK 28.2.13676358。

## 5. 关键决策（别顺手改回去）

1. 金额一律存「分」的 int，禁止 double；时间存 UTC 毫秒。
2. 转账是 txns 的单条记录（`kind='transfer'` + `to_account_id`）。
3. 软删除（`deleted_at`），删除后 3 秒内可撤销。
4. 导入去重用指纹 `FNV-1a(kind|amount|分钟|note)`，写进 `dedup_hash`。
5. 不用 provider/riverpod/bloc，只有 `DataBus` 单例广播刷新。
6. 更新机制不用 GitHub API，用仓库 `version.json` 比 versionCode，多镜像回退。
7. 继续用 debug keystore 签名 —— 换签名会让已装用户无法覆盖安装（丢数据）。
8. `android/` 不入库，靠脚本生成；图标切换的 activity-alias 也由脚本注入。
9. 版本号三处同步：`pubspec.yaml`、`lib/core/version.dart`、`version.json`（最后一项脚本管）。
10. 主题颜色全部走 `Xm.*` 的 getter（内部读当前调色板），不要在页面里写死 `Color(0x...)`，
    否则深色模式下会瞎。

## 6. 坑和地雷

1. 必须先 `init_android.ps1` 再 build，否则图标是默认的、权限也缺。
2. release 包缺 `INTERNET` 权限 → 应用内检查更新永远失败（清单模板只写进 debug）。
3. Release 附件没上传也能 Publish，发完一定点开确认。
4. `version.json` 的 sha256 必须 64 位，且与上传的 APK 一致。
5. **先发 Release 再改 `version.json`**，否则用户点到 404。
6. 网络：`uploads.github.com` 直连更稳；git push 报
   `schannel failed to receive handshake` 时加 `-c http.proxy=` 走直连。
7. 图标切换后，部分启动器要回桌面才刷新；两个 alias **不能同时禁用**，
   `MainActivity.kt` 里是「先启用目标、再停用另一个」。
8. 大字号金额要给足容器高度，否则会被圆角裁切。
9. Gradle 增量缓存偶发失败时，`android/gradle.properties` 里加
   `kotlin.incremental=false`、`org.gradle.caching=false`（脚本已包含）。
10. `.ps1` 一律用纯 ASCII 写：Windows PowerShell 5.1 按 ANSI 读脚本，中文会解析失败。

## 7. 接手后的顺序（建议）

1. 读 `KNOWN-ISSUES.md`，先看 O-1（预算按分类名硬匹配）。
2. 跑一次 `init_android.ps1` + `flutter build apk --release`，确认环境通。
3. 再动功能，每次发版前跑 `flutter analyze` 和 `flutter test`。
