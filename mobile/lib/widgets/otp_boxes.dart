import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';

/// رمز تحقق عصري: 6 مربعات منفصلة جنب بعض — نظير مكوّن otp-input.tsx
/// في تطبيقات الويب (verify-email/page.tsx). الشكل مطابق لستايل AuthInput:
/// حاوية rounded-xl بحد dividerColor وخلفية bg-background، وعند التركيز
/// حد primary مع ring-4 (ظل انتشار 4 بنسبة 10%)، وعند الخطأ حد destructive.
///
/// السلوك: تقدم تلقائي للخانة التالية عند الكتابة، مسح للخلف في خانة فاضية
/// يعود للخانة السابقة ويمسحها (كيبورد فعلي)، لصق الرمز كاملًا في أي خانة
/// أو التعبئة التلقائية one-time-code يوزع الأرقام من البداية، والتنقل
/// بالأسهم يمين/يسار على الويب/سطح المكتب.
///
/// المستدعي يمرر [controller] رئيسيًا ويقرأ منه الرمز الكامل كما هو
/// (نص رقمي متصل بلا فواصل) فلا يتغير منطق الشاشات القائمة إطلاقًا.
class OtpBoxes extends StatefulWidget {
  const OtpBoxes({
    super.key,
    required this.controller,
    this.length = 6,
    this.enabled = true,
    this.hasError = false,
  });

  final TextEditingController controller;
  final int length;
  final bool enabled;
  final bool hasError;

  @override
  State<OtpBoxes> createState() => _OtpBoxesState();
}

class _OtpBoxesState extends State<OtpBoxes> {
  late final List<TextEditingController> _cells;
  late final List<FocusNode> _nodes;

  @override
  void initState() {
    super.initState();
    _cells = List<TextEditingController>.generate(
      widget.length,
      (_) => TextEditingController(),
    );
    _nodes = List<FocusNode>.generate(widget.length, (_) => FocusNode());
    for (final node in _nodes) {
      node.addListener(_handleFocusChanged);
    }
    widget.controller.addListener(_syncFromMaster);
    _syncFromMaster();
  }

  @override
  void dispose() {
    for (final node in _nodes) {
      node.removeListener(_handleFocusChanged);
      node.dispose();
    }
    widget.controller.removeListener(_syncFromMaster);
    for (final cell in _cells) {
      cell.dispose();
    }
    super.dispose();
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  // مزامنة التغييرات الخارجية فقط: تصفير كامل ('') أو رمز كامل مكتمل —
  // حتى لا ينهار ترتيب الخانات أثناء الكتابة الجزئية من داخل المكوّن.
  void _syncFromMaster() {
    final master = widget.controller.text.replaceAll(RegExp(r'\D'), '');
    final joined = _cells.map((cell) => cell.text).join();
    if (master == joined) return;
    if (master.isEmpty || master.length == widget.length) {
      for (var i = 0; i < widget.length; i++) {
        final next = i < master.length ? master[i] : '';
        if (_cells[i].text != next) _cells[i].text = next;
      }
      if (mounted) setState(() {});
    }
  }

  void _commitToMaster() {
    final joined = _cells.map((cell) => cell.text).join();
    if (widget.controller.text != joined) {
      widget.controller.text = joined;
    }
  }

  void _focusCell(int index) {
    if (index < 0 || index >= widget.length) return;
    _nodes[index].requestFocus();
    final cell = _cells[index];
    cell.selection = TextSelection(
      baseOffset: 0,
      extentOffset: cell.text.length,
    );
  }

  void _onCellChanged(int index, String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final previous = _cells[index].text;
    if (digits.length > previous.length + 1) {
      // لصق أو تعبئة تلقائية لرمز كامل: وزّع الأرقام من الخانة الأولى
      for (var i = 0; i < widget.length; i++) {
        final next = i < digits.length ? digits[i] : '';
        if (_cells[i].text != next) _cells[i].text = next;
      }
      _commitToMaster();
      _focusCell(
        digits.length >= widget.length ? widget.length - 1 : digits.length,
      );
    } else if (digits.isEmpty) {
      if (previous.isNotEmpty) {
        _cells[index].text = '';
        _commitToMaster();
      }
    } else {
      // محرف واحد (أو كتابة فوق رقم موجود): خذ آخر محرف وتقدم للخانة التالية
      final last = digits.substring(digits.length - 1);
      if (previous != last) {
        _cells[index].text = last;
        _commitToMaster();
      }
      if (last.isNotEmpty && index < widget.length - 1) {
        _focusCell(index + 1);
      }
    }
    if (mounted) setState(() {});
  }

  KeyEventResult _onCellKeyEvent(FocusNode node, KeyEvent event, int index) {
    // Backspace في خانة فاضية: امسح الخانة السابقة وارجع إليها.
    // الخانة المملوءة يستهلكها TextField نفسه (حذف المحرف) فلا نصل هنا.
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _cells[index].text.isEmpty &&
        index > 0) {
      _cells[index - 1].text = '';
      _commitToMaster();
      _focusCell(index - 1);
      if (mounted) setState(() {});
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _cell(BuildContext context, int index) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final focused = _nodes[index].hasFocus;
    final filled = _cells[index].text.isNotEmpty;
    final Color border;
    if (widget.hasError) {
      border = theme.colorScheme.error;
    } else if (focused) {
      border = primary;
    } else if (filled) {
      border = primary.withOpacity(0.45);
    } else {
      border = theme.dividerColor;
    }
    return Focus(
      onKeyEvent: (node, event) => _onCellKeyEvent(node, event, index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor, // bg-background
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: border),
          boxShadow: focused
              ? <BoxShadow>[
                  // ring-4 ring-primary/10
                  BoxShadow(
                    color: primary.withOpacity(0.10),
                    blurRadius: 0,
                    spreadRadius: 4,
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: TextField(
          controller: _cells[index],
          focusNode: _nodes[index],
          enabled: widget.enabled,
          keyboardType: TextInputType.number,
          textInputAction: index == widget.length - 1
              ? TextInputAction.done
              : TextInputAction.next,
          textAlign: TextAlign.center,
          textAlignVertical: TextAlignVertical.center,
          textDirection: TextDirection.ltr,
          autofillHints: index == 0
              ? const <String>[AutofillHints.oneTimeCode]
              : null,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          onChanged: (value) => _onCellChanged(index, value),
          onTap: () {
            final cell = _cells[index];
            cell.selection = TextSelection(
              baseOffset: 0,
              extentOffset: cell.text.length,
            );
          },
          decoration: const InputDecoration(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      // الرمز رقمي: الترتيب يسار → يمين دائمًا حتى في الواجهة العربية
      textDirection: TextDirection.ltr,
      children: <Widget>[
        for (var i = 0; i < widget.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _cell(context, i)),
        ],
      ],
    );
  }
}
