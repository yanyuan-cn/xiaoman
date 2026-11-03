# 绝对路径清单

## 结论先说

**应用代码里只有一处写死的绝对路径**：`tools/gen_icon.py:15` 的字体路径（见下面第 1 条），且只在重新生成图标时用到。
`lib/`、`scripts/`、`.github/`、`assets/` 里 grep `/sdcard`、`/data/data`、`/storage/`、`C:\`、`D:\`、`/root/`、`/tmp/` **均无命中**。

所有运行时目录都由系统 API 在运行时决定（见「二、运行时路径」），换到 Windows 上不需要改任何代码。

但仍有 **6 处环境路径**散落在脚本、工具和文档里，逐条列在下面。

---

## 一、写死的环境路径（需要你处理）

### 1. `/usr/share/fonts/truetype/arphic/uming.ttc`

| 项 | 内容 |
|---|---|
| 出现位置 | `xiaoman/tools/gen_icon.py:15`（`FONT_PATH = ...`），注释在 `:5` |
| 用途 | 生成启动图标时加载宋体（AR PL UMing）渲染「满」字 |
| 何时触发 | **只在重新生成图标时**。产物已在 `assets/icon/res/` 里，正常构建不需要跑这个脚本 |
| Windows 对应 | 改成 `C:\Windows\Fonts\simsun.ttc`（宋体）或 `C:\Windows\Fonts\msyh.ttc`（微软雅黑）。注意 `ImageFont.truetype` 能读 `.ttc`，但可能默认取第一个字面，字体粗细会变 |
| 建议 | 除非要改图标，否则不要动这个脚本，也不要在 Windows 上重跑（重跑会覆盖已验收的 PNG） |

### 2. `/sdcard/Download/DSH-Go/`

| 项 | 内容 |
|---|---|
| 出现位置 | **不在包内任何文件里**，只是原开发者与用户之间传文件的目录 |
| 用途 | 手机端接收补丁包/完整包 |
| Windows 对应 | **无需修改**。你在 Windows 上随便选个目录解压即可，例如 `D:\handoff` |

### 3. `D:\code\xiaoman`

| 项 | 内容 |
|---|---|
| 出现位置 | **不在包内任何文件里**。这是原用户 Windows 机器上的工程目录，出现在开发过程的构建日志中 |
| 用途 | `flutter build` 的工作目录 |
| Windows 对应 | **换成你自己的工程目录**。包内脚本全部用相对路径（`$PSScriptRoot`），不依赖它 |

### 4. `C:\src\flutter`

| 项 | 内容 |
|---|---|
| 出现位置 | **不在包内任何文件里**，只出现在原机器的构建日志（`C:\src\flutter\bin\flutter.bat`） |
| 用途 | 原用户的 Flutter SDK 安装位置 |
| Windows 对应 | **无需修改**，按你机器上 Flutter 的实际位置即可（只要 `flutter` 在 PATH 里） |

### 5. `C:\Android\Sdk`

| 项 | 内容 |
|---|---|
| 出现位置 | **不在包内任何文件里**，只出现在原机器的报错日志（`Android sdkmanager did not install NDK ... into C:\Android\Sdk`） |
| 用途 | Android SDK 根目录（含 NDK 28.2.13676358） |
| Windows 对应 | **无需修改**，用 `ANDROID_HOME` 指向你机器上的实际位置 |

### 6. `C:\Users\<用户名>\.android\debug.keystore`

| 项 | 内容 |
|---|---|
| 出现位置 | 不在包内任何文件里（`android/` 被 gitignore，由 `flutter create` 现场生成，其 `android/app/build.gradle.kts` 里 release 用 debug 签名） |
| 用途 | **决定能否覆盖安装**。已安装的 App 与这个 keystore 绑定 |
| 原值 | 原机器用户名是中文：`C:\Users\颛顼\.android\debug.keystore` |
| Windows 对应 | 你机器上是 `C:\Users\<你的用户名>\.android\debug.keystore`。**如果和原机器的不是同一个文件，新包装不上（`INSTALL_FAILED_UPDATE_INCOMPATIBLE`），必须先卸载，数据会丢** |

> 这个 keystore 文件**没有**包含在交接包里（属于凭据，且是生成物）。如果接手后要延续原用户的安装，需要向他索取该文件，或接受「卸载重装 + 数据丢失」。

---

## 二、运行时路径（Android 上由系统决定，无需修改）

这些不是写死的，列出来是为了让你知道数据实际在哪、迁移时该拷什么。

| 内容 | 位置 | 来源 |
|---|---|---|
| SQLite 数据库 | `/data/data/com.xiaoman.xiaoman/databases/xiaoman.db` | `lib/data/db.dart:8`，`p.join(await getDatabasesPath(), kDbName)`，`kDbName = 'xiaoman.db'`（`:4`） |
| 更新下载的 APK | `/data/data/com.xiaoman.xiaoman/cache/...` | `lib/data/apk_updater.dart:42`，`getTemporaryDirectory()` |
| 缓存统计与清理 | 同上 | `lib/core/storage.dart:25,45,65` |
| 导出的 CSV / JSON | 用户自选（通常 `/storage/emulated/0/Download/`） | `lib/features/profile/profile_page.dart:321`，`FilePicker.saveFile(...)` |
| 导入的账单文件 | 用户自选 | `lib/features/import/import_page.dart:116`，`FilePicker.pickFiles(...)` |

在手机上查看数据库（调试用，需要 root 或 adb backup）：
`adb shell run-as com.xiaoman.xiaoman ls databases/`

---

## 三、包里相对的路径约定

| 路径 | 说明 |
|---|---|
| `scripts/init_android.ps1` | 用 `Split-Path -Parent $PSScriptRoot` 取项目根目录，**不依赖调用时的 cwd**，可以在任意目录调用 |
| `assets/icon/res/` | 由脚本复制到 `android/app/src/main/res/`，源目录必须在仓库里（因为 `android/` 被 gitignore） |
| `.github/workflows/android.yml` | 全部相对路径（`cp -r assets/icon/res/. android/app/src/main/res/`），无绝对路径 |
