# 小满 · 上手说明

## 一、本地运行（Windows）

### 1. 生成 android 目录

在项目根目录右键打开 PowerShell，运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\init_android.ps1
```

这个脚本做了两件事：生成 `android/`，并把桌面显示名改成「小满」。

不想用脚本就手动执行两步：

```powershell
flutter create --platforms=android --org com.xiaoman --project-name xiaoman _tmp
Copy-Item -Recurse _tmp\android .\android
Remove-Item -Recurse -Force _tmp
```

然后手动把 `android\app\src\main\AndroidManifest.xml` 里的
`android:label="xiaoman"` 改成 `android:label="小满"`。

### 2. 跑起来

```powershell
flutter pub get
flutter run
```

手机要用 USB 连接并开启「USB 调试」。

## 二、云端构建

推送到 `main` 后，GitHub Actions 自动构建 debug APK：

1. 仓库 → Actions → 最新的 `android`
2. 页面底部 Artifacts → 下载 `xiaoman-apk`
3. 解压得到 `app-debug.apk`，装到手机

workflow 里已经有 `sed` 命令改中文名，所以云端出的包桌面显示也是「小满」。

## 三、目录结构

```
lib/
  main.dart                          入口
  core/money.dart                    金额（分为单位，整数运算）
  core/dates.dart                    日期格式化
  data/db.dart                       建表、种子数据、版本迁移
  data/models.dart                   Account / Category / Txn
  data/repo.dart                     查询与写入
  state/ledger.dart                  首页状态
  features/ledger/ledger_page.dart   流水首页
  features/record/record_page.dart   记一笔
scripts/init_android.ps1             生成 android 目录 + 改中文名
test/money_test.dart                 金额解析与格式化单测
```

## 四、改数据要注意

1. 金额永远存「分」的整数，别改 double
2. 改表结构必须升 `kDbVersion` 并在 `_upgrade` 里写迁移
3. 包名 `com.xiaoman.xiaoman` 装上之后别再改

## 五、还没做的

1. 账单导入：其他记账 App 迁移、支付宝 CSV、微信 CSV
2. 应用内检测更新
3. 账户余额、转账、分类管理、统计图表
