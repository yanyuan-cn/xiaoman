# 运行环境与版本清单

## 一、打包机的环境（事实，供你判断哪些结论可信）

| 项 | 值 |
|---|---|
| 设备 | Android 手机（Redmi 23127PN0CC，Android 16 / API 36） |
| 系统 | Ubuntu 24.04.5 LTS（proot 容器，**不是 Termux**，也不是真机 root） |
| 架构 | `aarch64`，内核 `6.1.138-android14` |
| Shell | GNU bash 5.2.21(1)-release |
| CPU / 内存 | 8 核 / 15 GB |
| 存储 | 手机内部存储挂在 `/sdcard`（481 G，已用 361 G） |
| 权限 | 免 root；文件沙箱后端（bubblewrap/Landlock）不可用 |

**这套环境能写代码、能跑 Python、能联网，但跑不了 Flutter。** 具体原因见下面第三节。

## 二、工具版本（实测输出）

| 工具 | 版本 | 在本项目里的用途 |
|---|---|---|
| Python | `Python 3.12.15` | 仅 `tools/gen_icon.py` 生成图标（Pillow） |
| Node | `v24.22.1` | 无关 |
| pnpm | `11.28.5` | 无关 |
| git | 已安装（`/usr/bin/git`） | **但项目从未 `git init`**，见 `git-state.txt` |
| JDK | **未安装**（`java: command not found`） | 缺失 → 无法运行 Gradle |
| Flutter / Dart | **未安装** | 缺失 → 无法编译、无法 `flutter analyze` |

Python 额外装过：`pillow`（生成图标用）、字体包 `fonts-arphic-uming`。

## 三、为什么这台机器不能构建（别重复尝试）

1. Flutter 官方 Linux 包**只有 x64**。下了 `flutter_linux_3.47.9-stable.tar.xz`（1.58 GB）解压后，`dart` 报
   `dart: cannot execute: required file not found`（缺 x86-64 动态链接器）。
2. 想用 qemu-user + amd64 libc 兜底：apt 源里只有 arm64，
   `apt-get install libc6:amd64` → `E: Unable to locate package libc6:amd64`。
3. 结论：**本机静态检查不可行**，v1.1.0 的编译错误是靠你在 Windows 上跑 `flutter analyze` 发现的（18 条，其中 1 个 error）。
4. 目录 `/root/sdk/` 里还留着那 1.58 GB 的 tar 包和解压产物（约 2.5 GB），没有清理，可以直接删。

## 四、手机特有、Windows 上必须换做法的操作

| 手机上的做法 | Windows 上怎么办 |
|---|---|
| 文件放 `/sdcard/Download/DSH-Go/` 让用户手机下载 | 直接用 `D:\` 等本地目录 |
| 直接 `adb install` / 应用内更新装到真机验收 | 需要 USB 数据线 + 手机开「USB 调试」和「USB 安装」，或把 APK 传到手机手动装 |
| 读写 `/sdcard`（手机存储） | 手机用 MTP 挂载，或 `adb pull/push` |
| 长命令直接跑（无沙箱） | 正常 PowerShell 即可 |
| 用 `proot` 里的 Ubuntu 工具链 | 不适用，Windows 用原生工具链 |

**没有「只能在手机上做」的必要步骤**：构建、打包、发布全都能在 Windows 完成，手机只用于安装验收。

## 五、Windows 侧必须准备好的版本

| 组件 | 必须的版本 | 说明 |
|---|---|---|
| Flutter | **3.47.9 stable** | v1.1.0 就是用它构建的。换大版本前先跑 `flutter analyze` 看有没有 API 变动 |
| Dart | 随 Flutter（`sdk: ">=3.4.0 <4.0.0"`） | 见 `pubspec.yaml` |
| JDK | **17**（原机器是 Temurin `17.0.20.1`） | Gradle 只认这个范围 |
| Android SDK | platform **36**、build-tools、platform-tools、cmdline-tools (latest) | `flutter doctor` 里 Android toolchain 要全绿 |
| NDK | **28.2.13676358** | 必须用 SDK Manager 勾「Show Package Details」单独装；在 `build.gradle.kts` 里注释掉 `ndkVersion` 没用（Flutter 插件会自己设） |
| PowerShell | 5.1（Windows 自带） | `scripts/init_android.ps1` 用纯 ASCII 写，因为 PS 5.1 按 ANSI 读取 `.ps1`，含中文会解析失败 |

国内网络建议设的镜像环境变量（原机器就是这样，否则 `pub get` 极慢）：

```powershell
$env:PUB_HOSTED_URL="https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
```

## 六、版本不符会怎样（对症表）

| 症状 | 原因 |
|---|---|
| `Execution failed for task ':app:compileFlutterBuildDebug'` + 某个 Widget 的属性/构造不存在 | Flutter 版本与代码不匹配（代码按 3.47 写） |
| `Android sdkmanager did not install NDK 28.2.13676358 into ...` | 没装对应 NDK（在 `build.gradle.kts` 里改 `ndkVersion` 无效） |
| `Unsupported class file major version` / Gradle 启动即失败 | JDK 不是 17 |
| `Could not close incremental caches in ...\kotlin\caches-jvm` | Gradle 增量缓存 bug，在 `android/gradle.properties` 加 `kotlin.incremental=false`、`org.gradle.caching=false` |
| 应用内检查更新永远「连接失败」，浏览器能打开 | release 包缺 `INTERNET` 权限（先跑 `init_android.ps1` 再 build） |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | 签名 keystore 与已装版本不一致 → 只能卸载（丢数据） |
| `INSTALL_FAILED_USER_RESTRICTED` | 手机开发者选项里没开「USB 安装」 |

## 七、我没能验证的部分

- 我**没有在 Windows 上执行过**这里的任何命令。上面 Windows 侧的版本与命令，来自原用户的真实执行记录与构建日志，不是我实测的。
- 包内**没有 `pubspec.lock`**（打包环境从未 `pub get`）。依赖版本以你本机第一次 `flutter pub get` 生成的 lock 为准；已知 `sqflite` 解析到 2.4.5。
- `flutter test` 只覆盖 `test/money_test.dart`（金额工具），其余无测试。
