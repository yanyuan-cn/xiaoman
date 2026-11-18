import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../data/suggest_rules.dart';
import '../../ui/components.dart';
import '../../ui/unsaved_guard.dart';

/// 记账面板：从右下角的「记一笔」长出来。
///
/// 视觉稿的骨架是「分类横条 + 大金额 + 九宫格键盘」，其余字段（收支类型、
/// 账户、值不值、场景、备注）压在金额和键盘之间，可以滚。
class RecordPage extends StatefulWidget {
  const RecordPage({
    super.key,
    required this.repo,
    this.initialKind = 'expense',
    this.initialCategoryId,
    this.editing,
  });

  static const double heightFactor = 0.9;

  final Repo repo;
  final String initialKind;
  final int? initialCategoryId;
  final Txn? editing;

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  late String _kind = widget.editing?.kind ?? widget.initialKind;
  String _amount = '';
  int? _parentId;
  int? _childId;
  int? _accountId;
  int? _toAccountId;
  DateTime _date = DateTime.now();
  int _mood = 0;
  String? _scene;
  final TextEditingController _note = TextEditingController();
  Timer? _noteDebounce;

  List<Account> _accounts = const <Account>[];
  List<TxnCategory> _categories = const <TxnCategory>[];
  bool _ready = false;
  bool _saving = false;
  bool _saved = false;

  /// 这次预选是怎么来的：按习惯 / 按时间 / 按商家 / 沿用上次。空表示没预选。
  String _autoReason = '';

  /// 用户自己点过的开关。点过之后，对应的自动预选就不再覆盖他的选择。
  bool _catTouched = false;
  bool _accTouched = false;

  /// 打开面板那一刻的场景，用来判断这次到底改没改
  String? _initScene;

  late bool _inBudget = widget.editing?.inBudget ?? true;

  bool get _isEditing => widget.editing != null;
  bool get _isTransfer => _kind == 'transfer';
  bool get _canSave => (parseYuanToCents(_amount) ?? 0) > 0;

  /// 有没有未保存的改动（新记账也算，输入了金额就要拦）
  bool get _dirty {
    if (_saved) return false;
    final Txn? e = widget.editing;
    if (e == null) {
      return _amount.isNotEmpty ||
          _note.text.trim().isNotEmpty ||
          _mood != 0 ||
          _scene != _initScene ||
          _toAccountId != null;
    }
    return _amount != formatCentsPlain(e.amount) ||
        _note.text.trim() != (e.note ?? '') ||
        _mood != e.mood ||
        _scene != e.workState ||
        _accountId != e.accountId ||
        _toAccountId != e.toAccountId ||
        _inBudget != e.inBudget ||
        _kind != e.kind;
  }

  @override
  void initState() {
    super.initState();
    final Txn? e = widget.editing;
    if (e != null) {
      _amount = formatCentsPlain(e.amount);
      _date = e.occurredAt;
      _accountId = e.accountId;
      _toAccountId = e.toAccountId;
      _mood = e.mood;
      _scene = e.workState;
      _note.text = e.note ?? '';
    }
    _load();
  }

  @override
  void dispose() {
    _noteDebounce?.cancel();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final List<Account> accounts = await widget.repo.accounts();
    final List<TxnCategory> categories = await widget.repo.categories();
    final DateTime now = DateTime.now();
    final bool isNew = widget.editing == null;

    // 上一次记账留下的选择（所有推测都落空时的兜底）
    RecordMemory memory = const RecordMemory();
    List<int> byHour = const <int>[];
    String? sceneHint;
    if (isNew) {
      try {
        memory = await widget.repo.lastRecord();
        byHour = await widget.repo.rankedCategoriesAtHour(now);
        sceneHint = await widget.repo.topSceneAtHour(now);
      } catch (_) {}
    }

    int? parent;
    int? child;
    String reason = '';

    // 1) 明确指定的分类（编辑既有账单 / 从别处带着分类进来）
    final int? seed = widget.editing?.categoryId ?? widget.initialCategoryId;
    if (seed != null) {
      for (final TxnCategory c in categories) {
        if (c.id != seed) continue;
        if (c.parentId == null) {
          parent = c.id;
        } else {
          parent = c.parentId;
          child = c.id;
        }
        break;
      }
    } else if (isNew) {
      // 2) 这个点平时记什么
      for (final int id in byHour) {
        final int? top = _topOf(id, categories);
        if (top != null) {
          parent = top;
          reason = '按习惯';
          break;
        }
      }
      // 3) 都猜不到就沿用上次
      if (parent == null && memory.categoryId != null) {
        final int? top = _topOf(memory.categoryId!, categories);
        if (top != null) {
          parent = top;
          reason = '沿用上次';
          child = memory.categoryId == top ? null : memory.categoryId;
        }
      }
    }

    // 4) 有二级分类的（食品餐饮 → 早餐/午餐/晚餐…）按时间挑一个
    if (isNew && parent != null && child == null) {
      final List<TxnCategory> kids = _kidsOf(parent, categories);
      if (kids.isNotEmpty) {
        List<int> learned = const <int>[];
        try {
          learned = await widget.repo.rankedChildrenAtHour(
            now,
            <int>[for (final TxnCategory c in kids) c.id],
          );
        } catch (_) {}
        if (learned.isNotEmpty) {
          child = learned.first;
          if (reason.isEmpty || reason == '沿用上次') reason = '按时间';
        } else {
          final int? meal = mealChildForHour(
            <(int, String)>[for (final TxnCategory c in kids) (c.id, c.name)],
            now.hour,
          );
          if (meal != null) {
            child = meal;
            if (reason.isEmpty || reason == '沿用上次') reason = '按时间';
          }
        }
      }
    }

    // 5) 账户：先看这个分类平时用哪个，再看这个点用哪个，最后才用上次的
    int? accountId = widget.editing?.accountId;
    if (isNew) {
      List<int> accs = const <int>[];
      try {
        if (parent != null) {
          accs = await widget.repo.rankedAccountsForCategories(<int>[
            parent,
            for (final TxnCategory c in _kidsOf(parent, categories)) c.id,
          ]);
        }
        if (accs.isEmpty) accs = await widget.repo.rankedAccountsAtHour(now);
      } catch (_) {}
      for (final int id in accs) {
        if (accounts.any((Account a) => a.id == id)) {
          accountId = id;
          if (reason.isEmpty) reason = '按习惯';
          break;
        }
      }
      if (accountId == null &&
          memory.accountId != null &&
          accounts.any((Account a) => a.id == memory.accountId)) {
        accountId = memory.accountId;
        if (reason.isEmpty) reason = '沿用上次';
      }
    }
    accountId ??= accounts.isEmpty ? null : accounts.first.id;

    // 6) 当时在干嘛：这个点最常标的那个，没把握就用上次的
    String? scene = widget.editing?.workState;
    if (isNew) {
      scene = sceneHint ?? memory.scene;
      if (scene != null && !XmWorkState.presets.contains(scene)) scene = null;
    }

    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _categories = categories;
      _accountId = accountId;
      _parentId = parent;
      _childId = child;
      _scene = scene;
      _initScene = scene;
      _autoReason = isNew ? reason : '';
      _ready = true;
    });
  }

  TxnCategory? _catById(int id) {
    for (final TxnCategory c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 往上找到一级分类；id 本身就是一级就返回自己，收支类型对不上返回 null。
  int? _topOf(int id, List<TxnCategory> cats) {
    for (final TxnCategory c in cats) {
      if (c.id != id) continue;
      if (c.kind != _kind) return null;
      return c.parentId ?? c.id;
    }
    return null;
  }

  List<TxnCategory> _kidsOf(int parentId, List<TxnCategory> cats) =>
      <TxnCategory>[
        for (final TxnCategory c in cats)
          if (c.parentId == parentId) c,
      ];

  List<TxnCategory> get _topCategories => _categories
      .where((TxnCategory c) => c.kind == _kind && c.parentId == null)
      .toList(growable: false);

  List<TxnCategory> get _childCategories => _parentId == null
      ? const <TxnCategory>[]
      : _categories
          .where((TxnCategory c) => c.parentId == _parentId)
          .toList(growable: false);

  void _switchKind(String kind) {
    if (kind == _kind) return;
    setState(() {
      _kind = kind;
      _catTouched = false;
      if (kind == 'transfer' ||
          _parentId == null ||
          !_topCategories.any((TxnCategory c) => c.id == _parentId)) {
        _parentId = null;
        _childId = null;
      }
    });
  }

  /// 换了一级分类之后：按时间挑二级分类，再把账户跟着分类换成常用的那个。
  ///
  /// [pickChild] 为 false 时不碰二级分类（备注只匹配到一级分类时，
  /// 别再按时间塞一个子类进去，那等于瞎猜）。
  Future<void> _afterCategoryChanged({bool pickChild = true}) async {
    final int? pid = _parentId;
    if (pid == null || _isEditing) return;
    final DateTime now = DateTime.now();
    final List<TxnCategory> kids = _kidsOf(pid, _categories);

    int? child;
    String reason = '';
    if (pickChild && kids.isNotEmpty) {
      List<int> learned = const <int>[];
      try {
        learned = await widget.repo.rankedChildrenAtHour(
          now,
          <int>[for (final TxnCategory c in kids) c.id],
        );
      } catch (_) {}
      if (learned.isNotEmpty) {
        child = learned.first;
        reason = '按时间';
      } else {
        child = mealChildForHour(
          <(int, String)>[for (final TxnCategory c in kids) (c.id, c.name)],
          now.hour,
        );
        if (child != null) reason = '按时间';
      }
    }

    List<int> accs = const <int>[];
    if (!_accTouched) {
      try {
        accs = await widget.repo.rankedAccountsForCategories(<int>[
          pid,
          for (final TxnCategory c in kids) c.id,
        ]);
      } catch (_) {}
    }

    if (!mounted || _parentId != pid) return;
    setState(() {
      if (_childId == null && child != null) _childId = child;
      if (reason.isNotEmpty && _autoReason.isEmpty) _autoReason = reason;
      if (!_accTouched) {
        for (final int id in accs) {
          if (_accounts.any((Account a) => a.id == id)) {
            _accountId = id;
            break;
          }
        }
      }
    });
  }

  /// 备注写着商家名时，跟着历史上同一家店的分类走（写了「罗森」就记零食）。
  void _onNoteChanged(String text) {
    _noteDebounce?.cancel();
    if (_isEditing || _catTouched) return;
    final String t = text.trim();
    if (t.length < 2) return;
    _noteDebounce = Timer(const Duration(milliseconds: 500), () async {
      List<int> ids = const <int>[];
      try {
        ids = await widget.repo.rankedCategoriesForNote(t, kind: _kind);
      } catch (_) {}
      if (!mounted || _catTouched || _isEditing) return;
      for (final int id in ids) {
        final TxnCategory? c = _catById(id);
        if (c == null || c.kind != _kind) continue;
        final int top = c.parentId ?? c.id;
        if (!_topCategories.any((TxnCategory x) => x.id == top)) continue;
        setState(() {
          _parentId = top;
          _childId = c.parentId == null ? null : c.id;
          _autoReason = '按商家';
        });
        await _afterCategoryChanged(pickChild: c.parentId != null);
        return;
      }
    });
  }

  void _tapKey(String key) {
    setState(() {
      if (key == '<') {
        if (_amount.isNotEmpty) {
          _amount = _amount.substring(0, _amount.length - 1);
        }
        return;
      }
      if (key == '.') {
        if (_amount.contains('.')) return;
        _amount = _amount.isEmpty ? '0.' : '$_amount.';
        return;
      }
      if (_amount.contains('.')) {
        if (_amount.split('.')[1].length >= 2) return;
      } else if (_amount.replaceAll('.', '').length >= 9) {
        return;
      }
      if (_amount == '0') {
        _amount = key;
        return;
      }
      _amount += key;
    });
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() => _date = DateTime(picked.year, picked.month, picked.day, 12));
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _save() async {
    final int? cents = parseYuanToCents(_amount);
    if (cents == null || cents <= 0) {
      _toast('请输入金额');
      return;
    }
    final int? accountId = _accountId;
    if (accountId == null) {
      _toast('请选择账户');
      return;
    }
    if (!_isTransfer && _parentId == null) {
      _toast('请选择分类');
      return;
    }
    if (_isTransfer) {
      final int? to = _toAccountId;
      if (to == null) {
        _toast('请选择转入账户');
        return;
      }
      if (to == accountId) {
        _toast('转出和转入不能是同一个账户');
        return;
      }
    }

    setState(() => _saving = true);
    final String note = _note.text.trim();
    final int? categoryId = _isTransfer ? null : (_childId ?? _parentId);
    final int mood = _isTransfer ? 0 : _mood;
    final String? scene = _isTransfer ? null : _scene;

    if (_isEditing) {
      await widget.repo.updateTxn(
        id: widget.editing!.id,
        kind: _kind,
        amount: cents,
        occurredAt: _date,
        accountId: accountId,
        toAccountId: _isTransfer ? _toAccountId : null,
        categoryId: categoryId,
        note: note.isEmpty ? null : note,
        inBudget: _inBudget,
        mood: mood,
        workState: scene,
      );
    } else if (_isTransfer) {
      await widget.repo.addTransfer(
        amount: cents,
        occurredAt: _date,
        fromAccountId: accountId,
        toAccountId: _toAccountId!,
        note: note.isEmpty ? null : note,
      );
    } else {
      await widget.repo.addTxn(
        kind: _kind,
        amount: cents,
        occurredAt: _date,
        accountId: accountId,
        categoryId: categoryId,
        note: note.isEmpty ? null : note,
        inBudget: _inBudget,
        mood: mood,
        workState: scene,
      );
    }

    // 记下这次的选择，下次猜不出来时用它兜底
    try {
      await widget.repo.rememberRecord(
        categoryId: categoryId,
        accountId: accountId,
        scene: scene,
      );
    } catch (_) {}

    if (!mounted) return;
    _saved = true;
    Navigator.of(context).pop(true);
  }

  /// 关闭前如果有改动，先问一句
  Future<void> _close() async {
    if (_dirty) {
      final bool discard = await confirmDiscard(
        context,
        title: _isEditing ? '放弃这次修改？' : '不记这一笔了？',
        content: '刚填的内容还没保存。',
        discardLabel: _isEditing ? '不保存' : '丢弃',
      );
      if (!discard) return;
    }
    _popPage(_saved);
  }

  /// 统一从这里关面板：build 里的 context 参数会遮住 State.context，
  /// 直接写 Navigator.of(context) 会被分析器判成「跨 await 用 context」。
  void _popPage(bool result) {
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final double h = MediaQuery.sizeOf(context).height * RecordPage.heightFactor;
    return PopScope<Object?>(
      canPop: !_dirty,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        final bool discard = await confirmDiscard(
          context,
          title: _isEditing ? '放弃这次修改？' : '不记这一笔了？',
          content: '刚填的内容还没保存。',
          discardLabel: _isEditing ? '不保存' : '丢弃',
        );
        if (!discard) return;
        _popPage(false);
      },
      child: Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: h,
        width: double.infinity,
        child: Container(
          decoration: BoxDecoration(
            color: Xm.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: <Widget>[
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 12),
                decoration: BoxDecoration(
                  color: Xm.isDark ? const Color(0xFF33443B) : const Color(0xFFDDE3DC),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
                child: Row(
                  children: <Widget>[
                    Text(_isEditing ? '编辑账单' : '记一笔',
                        style: Xm.text(15, FontWeight.w600, spacing: -0.1)),
                    if (_autoReason.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Xm.brandLL,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(_autoReason,
                              style: Xm.text(10, FontWeight.w600,
                                  color: Xm.brand)),
                        ),
                      ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _pickDate,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        child: Text(
                          '${fmtMonthDay(_date)} ${_dateLabel()}',
                          style: Xm.text(12, FontWeight.w400,
                              color: Xm.ink3, tabular: true),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    XmIconButton(
                      icon: Icons.close_rounded,
                      tooltip: '关闭',
                      size: 32,
                      onTap: _close,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              _amountRow(),
              Expanded(
                child: _ready
                    ? _form()
                    : const Center(child: CircularProgressIndicator()),
              ),
              _keypad(),
            ],
          ),
        ),
      ),
      ),
    );
  }

  String _dateLabel() {
    final DateTime now = DateTime.now();
    if (_date.year == now.year &&
        _date.month == now.month &&
        _date.day == now.day) {
      return '今天';
    }
    final DateTime y = now.subtract(const Duration(days: 1));
    if (_date.year == y.year && _date.month == y.month && _date.day == y.day) {
      return '昨天';
    }
    return fmtWeekday(_date);
  }

  Widget _amountRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Text('¥',
              style: Xm.text(20, FontWeight.w500, color: Xm.ink3)),
          const SizedBox(width: 2),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _amount.isEmpty ? '0' : _amount,
                style: Xm.text(
                  40,
                  FontWeight.w700,
                  spacing: -1.5,
                  height: 1,
                  tabular: true,
                  color: _amount.isEmpty ? const Color(0xFFD2DAD3) : Xm.ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _form() {
    if (_isTransfer) return _transferForm();

    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
          child: _catRow(),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: XmSegmented<String>(
            values: const <String>['expense', 'income', 'transfer'],
            labels: const <String>['支出', '收入', '转账'],
            value: _kind,
            onChanged: _switchKind,
          ),
        ),
        if (_childCategories.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final TxnCategory c in _childCategories)
                  XmChoice(
                    label: c.name,
                    dense: true,
                    selected: _childId == c.id,
                    onTap: () => setState(() {
                      _childId = _childId == c.id ? null : c.id;
                      _catTouched = true;
                      _autoReason = '';
                    }),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Text('账户', style: _labelStyle),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final Account a in _accounts)
                XmChoice(
                  // 带上备注，同一个银行的两张卡才分得清
                  label: a.displayName,
                  dense: true,
                  selected: _accountId == a.id,
                  onTap: () => setState(() {
                    _accountId = a.id;
                    _accTouched = true;
                  }),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
          child: Text('这笔值不值？', style: _labelStyle),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: XmWorthPicker(
            value: _mood,
            onChanged: (int v) => setState(() => _mood = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
          child: Text('当时在干嘛', style: _labelStyle),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: XmSceneChips(
            options: XmWorkState.presets,
            value: _scene,
            onChanged: (String? v) => setState(() => _scene = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: XmField(
            controller: _note,
            hint: '备注（可选，写商家名能自动归类）',
            maxLength: 40,
            onChanged: _onNoteChanged,
            textInputAction: TextInputAction.done,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: <Widget>[
              Text('计入预算', style: Xm.text(13.5, FontWeight.w500)),
              const Spacer(),
              Switch(
                value: _inBudget,
                onChanged: (bool v) => setState(() => _inBudget = v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  TextStyle get _labelStyle =>
      Xm.text(12, FontWeight.w500, spacing: 0.4, color: Xm.ink3);

  /// 分类：横向滚动的一排（视觉稿里的 .catsrow）。
  Widget _catRow() {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _topCategories.length,
        separatorBuilder: (BuildContext _, int __) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int i) {
          final TxnCategory c = _topCategories[i];
          final bool on = _parentId == c.id;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              final bool on = _parentId == c.id;
              setState(() {
                _parentId = on ? null : c.id;
                _childId = null;
                _catTouched = true;
                _autoReason = '';
              });
              if (!on) _afterCategoryChanged();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 190),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(
                color: on ? Xm.brand : (Xm.isDark ? Xm.surface2 : const Color(0xFFF4F6F2)),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                c.name,
                style: Xm.text(
                  12.5,
                  on ? FontWeight.w600 : FontWeight.w500,
                  color: on
                      ? (Xm.isDark ? const Color(0xFF08120D) : Colors.white)
                      : Xm.ink2,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _transferForm() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      children: <Widget>[
        Text('从哪个账户转出', style: _labelStyle),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final Account a in _accounts)
              XmChoice(
                label: a.displayName,
                dense: true,
                selected: _accountId == a.id,
                onTap: () => setState(() => _accountId = a.id),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text('转到哪个账户', style: _labelStyle),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final Account a in _accounts)
              XmChoice(
                label: a.displayName,
                dense: true,
                selected: _toAccountId == a.id,
                onTap: () => setState(() {
                  _toAccountId = a.id;
                }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        XmField(
          controller: _note,
          hint: '备注（可选）',
          maxLength: 40,
          textInputAction: TextInputAction.done,
        ),
      ],
    );
  }

  Widget _keypad() {
    const List<List<String>> rows = <List<String>>[
      <String>['1', '2', '3'],
      <String>['4', '5', '6'],
      <String>['7', '8', '9'],
      <String>['.', '0', '<'],
    ];
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Xm.line, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final List<String> row in rows)
            Row(
              children: <Widget>[
                for (final String k in row) Expanded(child: _key(k)),
              ],
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              10,
              2,
              10,
              8 + MediaQuery.paddingOf(context).bottom,
            ),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: _canSave ? Xm.buttonGradient : null,
                  color: _canSave ? null : (Xm.isDark ? Xm.surface2 : Xm.line),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _saving ? null : _save,
                    child: Center(
                      child: Text(
                        _saving ? '保存中…' : (_isEditing ? '保存修改' : '完成'),
                        style: Xm.text(
                          15,
                          FontWeight.w600,
                          spacing: 1,
                          color: _canSave ? Colors.white : Xm.ink3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _key(String k) {
    return SizedBox(
      height: 50,
      child: Material(
        color: Xm.surface,
        child: InkWell(
          onTap: () => _tapKey(k),
          child: Center(
            child: k == '<'
                ? Icon(Icons.backspace_outlined, size: 20, color: Xm.ink2)
                : Text(
                    k,
                    style: Xm.text(21, FontWeight.w500, height: 1),
                  ),
          ),
        ),
      ),
    );
  }
}
