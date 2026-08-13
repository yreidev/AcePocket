import 'more_page.dart';

/// 一条搜索结果：入口 + 所属分组标题。
class MoreSearchResult {
  const MoreSearchResult({required this.entry, required this.groupTitle});

  /// 命中的功能入口。
  final MoreEntry entry;

  /// 入口所属分组的标题（如「安全」）。
  final String groupTitle;
}

/// 各入口 label 的拼音检索串（全拼一条 + 首字母一条，均小写、无空格）。
///
/// 零依赖的静态映射：label 中的拉丁字母 / 数字原样保留在对应位置
/// （如 'SSL 证书' → ['sslzhengshu', 'sslzs']）；纯拉丁 label 只有一条。
/// 多音字按本语境读音（如「行」在「通行密钥」中读 xíng）。
/// 必须覆盖 [kMoreGroups] 的全部入口，测试中有覆盖度断言。
const Map<String, List<String>> kMoreEntryPinyin = <String, List<String>>{
  // 网站与证书
  '网站': ['wangzhan', 'wz'],
  '网站默认设置': ['wangzhanmorenshezhi', 'wzmrsz'],
  'SSL 证书': ['sslzhengshu', 'sslzs'],
  'DNS 账号': ['dnszhanghao', 'dnszh'],
  'CA 账户': ['cazhanghu', 'cazh'],
  // 数据与存储
  '数据库': ['shujuku', 'sjk'],
  '文件管理': ['wenjianguanli', 'wjgl'],
  '备份管理': ['beifenguanli', 'bfgl'],
  '备份存储': ['beifencunchu', 'bfcc'],
  '磁盘管理': ['cipanguanli', 'cpgl'],
  '磁盘健康': ['cipanjiankang', 'cpjk'],
  'RAID 阵列': ['raidzhenlie', 'raidzl'],
  // 运行环境
  '容器': ['rongqi', 'rq'],
  '镜像': ['jingxiang', 'jx'],
  '应用商店': ['yingyongshangdian', 'yysd'],
  '运行环境': ['yunxinghuanjing', 'yxhj'],
  '项目': ['xiangmu', 'xm'],
  '应用模板': ['yingyongmuban', 'yymb'],
  '系统服务': ['xitongfuwu', 'xtfw'],
  '进程管理': ['jinchengguanli', 'jcgl'],
  // 终端与远程
  '终端': ['zhongduan', 'zd'],
  'SSH 主机': ['sshzhuji', 'sshzj'],
  '主机文件': ['zhujiwenjian', 'zjwj'],
  // 运维与监控
  '计划任务': ['jihuarenwu', 'jhrw'],
  '任务中心': ['renwuzhongxin', 'rwzx'],
  '历史监控': ['lishijiankong', 'lsjk'],
  '告警': ['gaojing', 'gj'],
  '通知渠道': ['tongzhiqudao', 'tzqd'],
  'WebHook': ['webhook'],
  '面板日志': ['mianbanrizhi', 'mbrz'],
  // 工具箱
  '系统工具': ['xitonggongju', 'xtgj'],
  '日志清理': ['rizhiqingli', 'rzql'],
  '网络信息': ['wangluoxinxi', 'wlxx'],
  '服务器跑分': ['fuwuqipaofen', 'fwqpf'],
  '面板迁移': ['mianbanqianyi', 'mbqy'],
  // 安全
  '防火墙': ['fanghuoqiang', 'fhq'],
  '面板安全': ['mianbananquan', 'mbaq'],
  'SSH 服务': ['sshfuwu', 'sshfw'],
  '防篡改': ['fangcuangai', 'fcg'],
  // 系统
  '面板设置': ['mianbanshezhi', 'mbsz'],
  '面板用户': ['mianbanyonghu', 'mbyh'],
  // 「钥」在「密钥」中口语常读 yào、词典读 yuè，两条全拼都收。
  '通行密钥': ['tongxingmiyao', 'tongxingmiyue', 'txmy'],
  'API 令牌': ['apilingpai', 'apilp'],
  '面板证书': ['mianbanzhengshu', 'mbzs'],
  '面板升级': ['mianbanshengji', 'mbsj'],
  '运行时诊断': ['yunxingshizhenduan', 'yxszd'],
  // 应用
  '应用设置': ['yingyongshezhi', 'yysz'],
  '服务器管理': ['fuwuqiguanli', 'fwqgl'],
  '关于': ['guanyu', 'gy'],
};

/// 按标题过滤全部入口。
///
/// [query] 先 trim，为空返回空列表。匹配规则（大小写不敏感）：
/// - label 子串匹配（覆盖中文与 'ssl' → 'SSL 证书' 之类拉丁子串）；
/// - [kMoreEntryPinyin] 中任一检索串包含 query（全拼 / 首字母）。
/// 结果保持 [groups] 的原始遍历顺序，不做相关性排序。
List<MoreSearchResult> filterMoreEntries(List<MoreGroup> groups, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const <MoreSearchResult>[];

  final results = <MoreSearchResult>[];
  for (final group in groups) {
    for (final entry in group.entries) {
      final matched =
          entry.label.toLowerCase().contains(q) ||
          (kMoreEntryPinyin[entry.label]?.any(
                (candidate) => candidate.contains(q),
              ) ??
              false);
      if (matched) {
        results.add(MoreSearchResult(entry: entry, groupTitle: group.title));
      }
    }
  }
  return results;
}
