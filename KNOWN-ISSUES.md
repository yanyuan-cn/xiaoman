# 需要修的问题清单

按优先级排列。每条都给了「现状 / 为什么会这样 / 怎么改 / 验收方法」。
标注 **【仓库】** 的只涉及改仓库文件，不需要动 Dart 代码。

---

## I-1 【仓库】CI 工作流缺 INTERNET 权限注入（高）

**现状**
远端 `.github/workflows/android.yml` = 1,787 字符，只有 `REQUEST_INSTALL_PACKAGES` 那段，没有 `INTERNET`。
包内 `reference/android.yml.fixed` = 2,119 字符，是**已修好**的版本（两段注入 + 图标复制都在）。

**为什么重要**
CI 现在只出 debug 包（debug 清单自带 INTERNET），所以没暴露。一旦有人用 CI 出 release 包，就会重演「检查更新永远连接失败」。

**怎么改**
用 `reference/android.yml.fixed` 整体覆盖仓库的 `.github/workflows/android.yml` 并提交。

如果你手改，插入位置是 `if 'REQUEST_INSTALL_PACKAGES' not in s:` 之前：

```python
          s = p.read_text()
          if 'android.permission.INTERNET' not in s:
              s = re.sub(r'(<manifest[^>]*>)',
                         r'\1\n    <uses-permission android:name="android.permission.INTERNET" />',
                         s, count=1)
              p.write_text(s)
```

**注意**：heredoc 的结束符 `PY` 必须与 `import` 那几行**同缩进（10 个空格）**。多一个空格 YAML 会把它当作 python 代码，整段静默失效。

**验收**
- 文件里能搜到 `android.permission.INTERNET`
- 提交后 Actions 跑绿
- 本地跑 `init_android.ps1` 后，`android/app/src/main/AndroidManifest.xml` 里能看到 INTERNET 权限

---

## I-2 【仓库】`tools/gen_icon.py` 不在仓库里

**现状**：本地有、远端没有。它只在重新生成图标时需要，不影响构建。

**怎么改**：提交该文件。
**注意**：`:15` 的 `FONT_PATH = "/usr/share/fonts/truetype/arphic/uming.ttc"` 是 Linux 路径，Windows 上要改成 `C:\Windows\Fonts\simsun.ttc`。**不要在 Windows 上随手重跑**——重跑会覆盖已验收的 PNG。

**验收**：仓库里能看到 `tools/gen_icon.py`；不重跑图标。

---

## I-3 【仓库】`analysis_options.yaml` 两边不一致

**现状**：本地 44 字节（只有 `include: package:flutter_lints/flutter.yaml`）；远端多一段 `analyzer.exclude`（排除 `build/**`、`android/**`），是更好的版本。

**怎么改**：以远端为准，把远端内容拉回本地覆盖。
**原因**：不排除的话，`flutter analyze` 会去分析 `android/` 生成的 Java/Kotlin 和 `build/` 产物，噪音大、还可能误报。

**验收**：本地文件包含 `analyzer:` 与 `exclude:`；`flutter analyze` 不再扫 `build/`。

---

## I-4 【仓库】本地 `version.json` 是旧的，且为空字段（**高危**）

**现状**：仓库外那份是
```json
{ "versionCode": 12, "versionName": "1.0.2", "apkUrl": "", "sha256": "", ... }
```
线上正确的是 13 / 1.1.0（见 `reference/version.json.online`）。

**为什么高危**：如果被误提交，应用会认为自己比线上新（12 < 13 只是版本回退），更糟的是 `apkUrl` 为空会让下载路径失效；而且和 Release 对不上。

**怎么改**：**不要提交本地这份**。本包已经把它排除在 `xiaoman/` 之外，只保留 `reference/version.json.online` 作为正确内容参考。发新版时按 `HANDOFF.md` §3 的流程改仓库里那份。

**验收**：仓库 `version.json` 仍是 13 / 1.1.0，`apkUrl` 指向真实 Release。

---

## I-5 【仓库/工程】CI 只出 debug APK

**现状**：`.github/workflows/android.yml` 跑的是 `flutter build apk --debug`，只适合验证能不能编译。

**怎么改（可选）**：要 CI 出 release，需要签名配置——把 keystore 以 base64 存进 Actions Secrets，构建时还原并传 `-PkeyStore...` 参数。
**警告**：**换签名 = 老用户无法覆盖安装**，必须先做备份恢复功能，否则等于让大家丢数据。短期建议继续本机构建。

---

## I-6 【代码】`flutter analyze` 还剩约 15 条 info 未清理

**现状**：v1.1.0 构建前的 18 条里，1 个 error（`repo.dart:612` 的 `Object?`）和 2 个未使用 import 已修；剩下是 `prefer_const_constructors`、`dangling_library_doc_comments` 等 info。

**怎么改**：`dart fix --apply` 后人工 review，或逐条手动加 `const`。
**验收**：`flutter analyze` 输出 `No issues found!`（或只剩不影响构建的提示）。

---

## I-7 【功能】备份只能导出，不能恢复（数据风险最高）

**现状**：`我的 → 备份为 JSON` 只写文件；没有导入入口。
**影响**：换手机、误删、迁移，全都恢复不了。
**怎么改**：在 `lib/features/profile/profile_page.dart` 加「从备份恢复」：`FilePicker.pickFiles` → 解析 JSON → 事务内清空并写入（或按 id upsert）→ 成功后 `DataBus.bump()`。
**注意**：导入前必须让用户二次确认（会覆盖现有数据），并先自动导出一份当前数据。
**验收**：导出 → 清库 → 恢复 → 流水/账户/分类/预算/定期规则 数量与金额一致。

---

## I-8 【功能】没有搜索与筛选

**现状**：流水一多就没法用，只能按月翻。
**怎么改**：首页搜索图标 → 关键字（备注/商户）、分类、账户、金额区间、日期范围。
**验收**：组合条件能查到预期记录，清空条件恢复原列表。

---

## I-9 【功能】导入只支持 CSV

**现状**：`.xls`（老式 BIFF）和 `.xlsx` 都不支持；编码只按 UTF-8 处理。
**怎么改**：先做编码探测（GBK/UTF-8 BOM），再考虑 xlsx（`excel` 包只支持 xlsx，`syncfusion_flutter_xlsio` 可写不可读老 xls）。
**验收**：GBK 编码的 CSV 能正常导入，中文不乱码。

---

## I-10 【代码】预算的分类硬匹配

**现状**：`lib/state/ledger.dart` 用分类名 `食品餐饮`、`购物消费` 去匹配 id。
**影响**：用户在分类管理里改名，预算的「餐饮/购物」两档就失联（总预算不受影响）。
**怎么改**：首次绑定时把匹配到的分类 id 存进 settings（如 `budget_cat_food`），之后只认 id。

---

## I-11 【行为】定期扣款的边界

- 补跑上限 24 个月（`repo.dart` 的 `runDueRecurringRules` 里 `for (int guard = 0; guard < 24; guard++)`），规则更早的月份不会追。
- 自动生成的流水时间固定为到期日 **12:00 本地时间**，不是 0 点。
- 生成时若同月已存在 `external_id = 'rule:<id>:YYYY-MM'` 则跳过（幂等），但改了规则金额不会回改历史记录。

---

## 已修复、但容易被回退的点（别改回去）

1. `lib/data/repo.dart` 里 `whereArgs: <Object?>[...]`——写成 `<Object>` 会编译失败。
2. `lib/features/import/import_page.dart`、`lib/features/profile/profile_page.dart` 里**不能**再加 `import '../../core/money.dart';`（未使用会告警）。
3. `lib/features/recurring/recurring_page.dart` 用自定义 `_dropdown<T>`，不是 `DropdownButtonFormField`。
4. `scripts/init_android.ps1` 与 CI 里的两段权限注入**都**要保留（脚本给本机，CI 给云端）。
5. `.github/workflows/android.yml` 里 `PY` 的缩进（10 空格）。
