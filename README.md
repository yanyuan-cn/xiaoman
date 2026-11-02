# 小满

本地优先的手机记账本。数据只存在手机里，不申请网络权限。

## 现状（v0.1）

- 手动记账：自绘数字键盘、一级分类必选、二级分类可选、账户与日期、备注
- 流水首页：按月切换、按日分组、月度支出/收入/结余、长按删除并 5 秒内撤销
- 本地 SQLite 存储，6 张表，含版本迁移框架
- 预置 5 个账户、9 个支出一级分类（含 40 个二级）、8 个收入分类

## 本地运行

```bash
# 1. 生成 android 平台目录（Windows 可用脚本）
powershell -ExecutionPolicy Bypass -File scripts\init_android.ps1

# 2. 拉依赖并运行
flutter pub get
flutter run
```

## 云端构建

推送到 `main` 后，GitHub Actions 自动构建，在 Actions 页面下载 `xiaoman-apk`。

## 计划

- 账单导入：其他记账 App 迁移、支付宝 CSV、微信 CSV
- 应用内检测更新（GitHub Release + latest.json）
- 账户余额、转账、分类管理、统计图表

详细步骤见 [SETUP.md](SETUP.md)。
