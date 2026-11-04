# 问题清单

> 更新时间：2026-11-05 · 对应版本 **1.5.0+18**
>
> 旧版本文档里 I-1 ~ I-7 已全部关闭，历史记录见文末「已关闭」。

按优先级排列。**【仓库】** 表示只改仓库文件，**【代码】** 需要改 Dart。

---

## 当前未解决

### O-1 【代码】预算按分类名硬匹配（中）

**现状**：`lib/state/ledger.dart` 用 `'食品餐饮'` / `'购物消费'` 两个分类名去匹配 id。
**影响**：用户在分类管理里改名，餐饮/购物两档预算就失联（总预算不受影响）。
**怎么改**：首次绑定时把匹配到的分类 id 存进 settings（`budget_cat_food` / `budget_cat_shop`），之后只认 id；分类被删时提示重绑。
**验收**：改分类名后预算仍然对得上。

### O-2 【代码】`flutter analyze` 还有 10 条 info（低）

`dangling_library_doc_comments`、`prefer_const_constructors` 之类，不影响构建。
**怎么改**：`dart fix --apply` 后人工过一遍，或逐条加 `const`。
**验收**：`No issues found!`

### O-3 【代码】没有测试覆盖（低）

只有 `test/money_test.dart`（金额工具）+ `test/decode_test.dart`（编码）。备份恢复、导入去重、定期扣款这些核心逻辑零测试。
**建议**：至少给 `Repo.importBackup`、`dedupHashFor`、`runDueRecurringRules` 补上。

### O-4 【仓库】README 容易过期（低）

README 里的「现状（v0.1）」是最早的文案，改版时容易忘。发版时顺手看一眼表数量、分类数量这些硬数字。

---

## 已知取舍（不是 bug，别"优化"掉）

1. **金额一律存「分」的 int**，禁止 double —— 浮点误差会让人对不上账。
2. **时间存 UTC 毫秒**，只在显示时转本地。
3. **转账是 txns 的单条记录**（`kind='transfer'` + `to_account_id`），不是两条。
4. **软删除**（`deleted_at`），删除后 5 秒内可撤销。
5. **导入去重用指纹** `FNV-1a(kind|amount|分钟|note)`。
6. **sqflite 手写 SQL，不用 drift** —— 没有 build_runner 环境。
7. **不用 provider/riverpod/bloc**，只有 `DataBus`（ChangeNotifier 单例）。
8. **更新机制不走 GitHub API**，用仓库里的 `version.json` 比 versionCode，四级镜像回退。
9. **继续用 debug keystore 签名** —— 换签名会让已装用户无法覆盖安装。
10. **`android/` 被 gitignore**，由 `scripts/init_android.ps1` 生成；图标、权限、图标切换的
    activity-alias 都由这个脚本注入，**改完脚本要重跑**。
11. **版本号三处同步**：`pubspec.yaml`、`lib/core/version.dart`、`version.json`。
12. **应用图标切换靠 activity-alias**，Kotlin 模板在 `scripts/android/MainActivity.kt`，
    `android/` 重新生成时由脚本复制回去。

---

## 发版相关的坑

1. **必须先跑 `init_android.ps1` 再 build**，否则图标是默认的、权限也缺。
2. **release 包缺 INTERNET 权限**会导致应用内检查更新永远失败（模板只把它写进 debug 清单）。
3. **Release 附件没上传也能 Publish** —— 发完一定点开看有没有 `app-release.apk`。
4. **`version.json` 的 sha256 必须 64 位**，取自 `Get-FileHash app-release.apk -Algorithm SHA256`。
5. **先发 Release 再改 `version.json`**，顺序反了用户会点到 404。
6. **代理不稳定**：`uploads.github.com` 直连比走代理快且稳；git push 遇到
   `schannel failed to receive handshake` 时加 `-c http.proxy=` 走直连。
7. **GitHub Pages 有缓存**，请求已带 `?t=时间戳`，但 Pages 本身可能滞后 1~2 分钟。

---

## 已关闭

| 编号 | 内容 | 关闭版本 | 怎么解决的 |
|---|---|---|---|
| I-1 | CI 缺 INTERNET 注入（且缩进错位导致整段失效） | 1.1.2 | 用 `reference/android.yml.fixed` 覆盖并修缩进 |
| I-2 | `tools/gen_icon.py` 不在仓库 | — | 图标改为设计交付包直接提供 PNG，不再需要生成脚本 |
| I-3 | `analysis_options.yaml` 两边不一致 | 1.1.2 | 采用带 `analyzer.exclude` 的版本 |
| I-4 | 本地 `version.json` 是旧的 1.0.2/12 | 1.1.2 | 换成线上正确的 13/1.1.0，之后由发版脚本维护 |
| I-5 | CI 只出 debug 包 | — | **保持现状**（有意）：release 继续本机构建，避免签名风险 |
| I-6 | analyze 有 15 条 info | 部分 | 现在 10 条，均为 info |
| I-7 | 备份只能导出不能恢复 | 1.2.0 | 全量导出 + 事务恢复 + 恢复前自动备份 |
| I-8 | 没有搜索筛选 | 1.5.0 | 首页搜索入口，支持关键字/类型/分类/账户/日期 |
| I-9 | 导入只按 UTF-8 处理 | 1.5.0 | `decodeText` 支持 UTF-8/UTF-8 BOM/UTF-16LE/BE/GBK/GB18030 回退 |
