/// 版本信息。改了 pubspec 里的 version，这里也要同步改。
const String kAppName = '小满';
const String kAppVersion = '0.6.0';
const int kAppBuild = 6;

/// 更新清单地址（放在仓库根目录的 version.json）
const String kUpdateManifestUrl =
    'https://raw.githubusercontent.com/yanyuan-cn/xiaoman/main/version.json';

/// 发布页地址（检查更新里「去下载」的落点）
const String kReleasePageUrl =
    'https://github.com/yanyuan-cn/xiaoman/releases';

const String kRepoUrl = 'https://github.com/yanyuan-cn/xiaoman';

const String kChangelog = '''
0.6.0
· 应用内更新：下载 APK、校验 SHA-256、调起系统安装
· 更新失败自动回退到网页下载

0.5.0
· 底部导航：首页 / 资产 / 统计 / 我的
· 资产页：每个账户的本期余额与总资产
· 统计页：月度分类占比、近 6 个月趋势
· 我的：导入导出、检查更新、更新日志

0.4.0
· 账单导入：从其他记账 App 的 CSV 迁移
· 按批次记录，可整批撤销
· 三级去重（订单号 / 指纹 / 疑似重复）

0.2.0
· 手动记账、流水列表、月度汇总
· 长按删除并撤销
''';
