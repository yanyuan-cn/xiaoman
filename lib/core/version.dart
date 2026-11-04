/// 版本信息。改了 pubspec 里的 version，这里也要同步改。
const String kAppName = '小满';
const String kAppVersion = '1.4.0';
const int kAppBuild = 17;

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
1.4.0
· 新增「应用图标」：可在深色墨绿 / 浅色方孔钱两套图标之间切换
· 删除改为左滑露出删除按钮，5 秒内可撤销
· 资产和贷款账户也能删除，同样可撤销
· 记账改成底部面板，不再整页跳走
· 统计的环形图会扫入、柱状图会长出来
· 底部导航滑块位置修正

1.3.0
· 全新视觉：墨绿 + 米白 + 哑光金，整套皮肤按设计规范重做
· 新图标「墨绿满未满」：开口朝上的环 + 液面线 + 一滴
· 首页概览卡：支出 / 收入 / 结余三栏，预算进度条与分类余额
· 底部导航换成滑动指示块，切页带 22% 位移过渡
· 流水逐条入场，分类用首字方块，金额全部等宽数字
· 资产页、我的页改为卡片分组，层次更清楚

1.2.0
· 新增：从备份恢复，换手机、误删、重装之后能把账找回来
· 备份升级为全量：账户、分类、流水、预算、定期扣款、设置都在里面
· 恢复时整库覆盖在一个事务里完成，中途出错不会写坏数据
· 恢复前会自动先导出一份当前数据，选错文件也有退路

1.1.1
· 维护版本：功能与 1.1.0 相同，用于验证发版与应用内更新链路

1.1.0
· 预算：可设总额、餐饮、购物，自选每月几号或每周重置
· 首页收支卡片里直接显示预算、已用、剩余，超支标红
· 每一笔账单都能单独设置是否计入预算
· 定期扣款：按每月固定日期自动生成账单，还款按转账处理
· 统计：新增分类饼图与年度统计
· 新图标

1.0.2
· 修复 release 包缺少联网权限导致检查更新失败

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
