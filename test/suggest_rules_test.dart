import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoman/data/suggest_rules.dart';

void main() {
  group('mealSlotForHour', () {
    test('按钟点分到四个用餐段', () {
      for (final int h in <int>[5, 6, 7, 8, 9]) {
        expect(mealSlotForHour(h), MealSlot.breakfast, reason: '$h 点');
      }
      for (final int h in <int>[10, 11, 12, 13, 14]) {
        expect(mealSlotForHour(h), MealSlot.lunch, reason: '$h 点');
      }
      for (final int h in <int>[15, 16]) {
        expect(mealSlotForHour(h), MealSlot.snack, reason: '$h 点');
      }
      for (final int h in <int>[17, 18, 19, 20]) {
        expect(mealSlotForHour(h), MealSlot.supper, reason: '$h 点');
      }
      for (final int h in <int>[21, 22, 23, 0, 1, 2, 3, 4]) {
        expect(mealSlotForHour(h), MealSlot.snack, reason: '$h 点');
      }
    });
  });

  group('mealChildForHour', () {
    // 库里真实的「食品餐饮」子分类
    const List<(int, String)> food = <(int, String)>[
      (11, '早餐'),
      (12, '午餐'),
      (13, '晚餐'),
      (14, '生鲜食品'),
      (15, '休闲零食'),
      (16, '饮料酒水'),
      (17, '聚餐'),
      (18, '请客吃饭'),
    ];

    test('早上挑早餐、中午挑午餐、晚上挑晚餐', () {
      expect(mealChildForHour(food, 8), 11);
      expect(mealChildForHour(food, 12), 12);
      expect(mealChildForHour(food, 19), 13);
    });

    test('夜宵和下午茶落到休闲零食', () {
      expect(mealChildForHour(food, 22), 15);
      expect(mealChildForHour(food, 2), 15);
      expect(mealChildForHour(food, 15), 15);
    });

    test('名字对不上就不猜', () {
      const List<(int, String)> shopping = <(int, String)>[
        (21, '日常家居'),
        (22, '服饰运动'),
      ];
      expect(mealChildForHour(shopping, 12), isNull);
      expect(mealChildForHour(const <(int, String)>[], 8), isNull);
    });

    test('没有对应名字时退到同义写法', () {
      const List<(int, String)> alt = <(int, String)>[
        (31, '早饭'),
        (32, '午饭'),
        (33, '晚饭'),
      ];
      expect(mealChildForHour(alt, 7), 31);
      expect(mealChildForHour(alt, 12), 32);
      expect(mealChildForHour(alt, 18), 33);
    });
  });

  group('isConfident', () {
    test('至少要两次，并且明显领先', () {
      expect(isConfident(0, 0), isFalse);
      expect(isConfident(1, 0), isFalse);
      expect(isConfident(2, 0), isTrue);
      expect(isConfident(2, 1), isTrue);
      expect(isConfident(2, 2), isFalse);
      expect(isConfident(3, 2), isTrue);
    });
  });

  group('hourWindow', () {
    test('前后各一小时，跨零点绕回', () {
      expect(hourWindow(12), <int>[11, 12, 13]);
      expect(hourWindow(0), <int>[23, 0, 1]);
      expect(hourWindow(23), <int>[22, 23, 0]);
    });
  });

  group('escapeLikePattern', () {
    test('转义 LIKE 通配符', () {
      expect(escapeLikePattern('50%'), r'50\%');
      expect(escapeLikePattern('a_b'), r'a\_b');
      expect(escapeLikePattern(r'a\b'), r'a\\b');
      expect(escapeLikePattern('罗森'), '罗森');
    });
  });
}
