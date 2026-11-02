/// 版本信息。改了 pubspec 里的 version，这里也要同步改。
const String kAppName = '小满';
const String kAppVersion = '1.0.1';
const int kAppBuild = 11;

/// 更新清单地址，按顺序尝试，第一个成功的就用。
/// 国内 raw.githubusercontent.com 基本连不上，所以前面放镜像。
const List<String> kUpdateManifestUrls = <String>[
  'https://yanyuan-cn.github.io/xiaoman/version.json',
  'https://ghproxy.net/https://raw.githubusercontent.com/yanyuan-cn/xiaoman/main/version.json',
  'https://cdn.jsdelivr.net/gh/yanyuan-cn/xiaoman@main/version.json',
  'https://raw.githubusercontent.com/yanyuan-cn/xiaoman/main/version.json',
];

/// APK 下载地址的镜像前缀，配置里的地址会依次套用
const List<String> kApkMirrorPrefixes = <String>[
  '',
  'https://ghproxy.net/',
];

/// 发布页地址（检查更新里「去下载」的落点）
const String kReleasePageUrl =
    'https://github.com/yanyuan-cn/xiaoman/releases';

const String kRepoUrl = 'https://github.com/yanyuan-cn/xiaoman';

const String kChangelog = '''
1.0.1
· 更新源改用 GitHub Pages 优先，镜像兜底
· 请求带时间戳，避免 CDN 缓存导致看不到新版
· 新增「更新源」设置，可手动指定地址

1.0.0
· 资产：账户详情页，可改名、改类型、改余额、设为定期/活期
· 资产：新增账户，支持「是否计入总资产」
· 负债：负债分区、贷款项目、净资产 = 资产 − 负债
· 存储：启动清理更新残留、存储占用可视化与一键清理
· 流畅度：启动申请最高刷新率

0.7.1
· 应用内更新联调版本（功能与 0.7.0 相同）

0.7.0
· 转账：账户之间转钱，资产自动同步
· 编辑已有流水：点开详情页右上角编辑
· 账单详情：分类、账户、精确时间、商户、订单号、备注、来源
· 分类管理：新建 / 重命名 / 隐藏一级与二级分类
· 自动识别编码：UTF-8 / GBK / UTF-16
· 支持支付宝账单、微信账单导入

0.6.1
· 更新检查多源回退，国内网络可用

0.6.0
· 应用内更新：下载 APK、校验、调起安装

0.5.0
· 底部导航、资产、统计、我的
''';
