/// 记账预选里「纯规则」的那部分：不碰数据库、不碰 UI，方便单测。
///
/// 数据库里那些「学了点什么」的部分在 [Repo] 里，这里只放兜底规则。
library;

/// 一天里按时间推断的用餐段
enum MealSlot {
  breakfast('早餐'),
  lunch('午餐'),
  supper('晚餐'),
  snack('零食');

  const MealSlot(this.label);

  final String label;
}

/// 几点算哪一顿。兜底用：还没攒够数据时也能猜个大概。
MealSlot mealSlotForHour(int hour) {
  final int h = hour % 24;
  if (h >= 5 && h <= 9) return MealSlot.breakfast;
  if (h >= 10 && h <= 14) return MealSlot.lunch;
  if (h >= 15 && h <= 16) return MealSlot.snack;
  if (h >= 17 && h <= 20) return MealSlot.supper;
  return MealSlot.snack;
}

/// 每个用餐段可能对应的子分类名字，按优先级排。
const Map<MealSlot, List<String>> _slotNames = <MealSlot, List<String>>{
  MealSlot.breakfast: <String>['早餐', '早饭'],
  MealSlot.lunch: <String>['午餐', '午饭'],
  MealSlot.supper: <String>['晚餐', '晚饭'],
  MealSlot.snack: <String>['休闲零食', '零食', '饮料酒水'],
};

/// 在一组子分类里挑出「这个点该吃的」那一个。
///
/// 只认名字（早餐/午饭/零食…），名字对不上就返回 null，让调用方别乱选。
int? mealChildForHour(
  Iterable<(int, String)> children,
  int hour,
) {
  final List<String> wanted = _slotNames[mealSlotForHour(hour)] ?? const <String>[];
  for (final String name in wanted) {
    for (final (int id, String childName) in children) {
      if (childName == name) return id;
    }
  }
  return null;
}

/// 一条时间线索「够不够硬」：至少出现过 [minCount] 次，并且明显比第二名多。
///
/// 用排名列表上的计数判断，避免只记过一两笔就把之后的预选定死。
bool isConfident(int top, int second, {int minCount = 2}) {
  if (top < minCount) return false;
  return top > second;
}

/// 时段窗口：当前小时前后各一小时（跨零点自动绕回）。
List<int> hourWindow(int hour) {
  final int h = hour % 24;
  return <int>[(h - 1 + 24) % 24, h, (h + 1) % 24];
}

/// 转义 LIKE 里的特殊字符，用户备注里带 % 或 _ 时不会串味。
String escapeLikePattern(String s) => s
    .replaceAll(r'\', r'\\')
    .replaceAll('%', r'\%')
    .replaceAll('_', r'\_');
