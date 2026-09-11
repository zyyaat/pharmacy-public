import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/strings.dart';
import '../core/theme.dart';

/// Task 61 — مكتبة واجهات الموبايل: نسخة Flutter من مكوّنات shadcn/ui
/// المستخدمة في الويب (card/button/badge/input/modal/select/table/loading)
/// بنفس الألوان والحواف والتباعد.

// ---------------------------------------------------------------- بطاقات

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? theme.colorScheme.surface,
        borderRadius: AppRadius.br,
        border: Border.all(color: theme.dividerColor),
      ),
      child: child,
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: AppRadius.br, onTap: onTap, child: body),
    );
  }
}

class CardTitle extends StatelessWidget {
  final String text;
  final String? subtitle;
  final Widget? trailing;
  const CardTitle(this.text, {super.key, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(subtitle!, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;
  const SectionHeader(this.title, {super.key, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          if (action != null) action!,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- أزرار

class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  const PrimaryButton(this.text, {super.key, this.onPressed, this.loading = false, this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(icon, size: 18),
        label: Text(text),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  const SecondaryButton(this.text, {super.key, this.onPressed, this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(text),
        style: OutlinedButton.styleFrom(
          backgroundColor: theme.brightness == Brightness.dark
              ? AppColors.darkSecondary
              : AppColors.lightSecondary,
          foregroundColor: theme.brightness == Brightness.dark
              ? AppColors.darkForeground
              : AppColors.lightSecondaryFg,
        ),
      ),
    );
  }
}

class GhostButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  const GhostButton(this.text, {super.key, this.onPressed, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(text),
      style: TextButton.styleFrom(foregroundColor: color ?? Theme.of(context).colorScheme.primary),
    );
  }
}

// ---------------------------------------------------------------- شارات

enum BadgeTone { primary, success, warning, destructive, muted, info }

class AppBadge extends StatelessWidget {
  final String text;
  final BadgeTone tone;
  const AppBadge(this.text, {super.key, this.tone = BadgeTone.muted});

  static BadgeTone saleStatus(String status) {
    switch (status) {
      case 'completed':
        return BadgeTone.success;
      case 'partially_returned':
        return BadgeTone.warning;
      case 'returned':
        return BadgeTone.destructive;
      default:
        return BadgeTone.muted;
    }
  }

  static BadgeTone stockStatus(String status) {
    switch (status) {
      case 'out_of_stock':
      case 'OUT_OF_STOCK':
        return BadgeTone.destructive;
      case 'low_stock':
      case 'LOW_STOCK':
        return BadgeTone.warning;
      case 'expiring':
      case 'EXPIRING':
        return BadgeTone.warning;
      case 'expired':
      case 'EXPIRED':
        return BadgeTone.destructive;
      default:
        return BadgeTone.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final Color fg;
    final Color bg;
    switch (tone) {
      case BadgeTone.primary:
        fg = dark ? AppColors.darkPrimary : AppColors.lightPrimary;
        bg = fg.withOpacity(0.12);
      case BadgeTone.success:
        fg = AppColors.successFg;
        bg = AppColors.successBg;
      case BadgeTone.warning:
        fg = AppColors.warningFg;
        bg = AppColors.warningBg;
      case BadgeTone.destructive:
        fg = dark ? AppColors.darkDestructive : AppColors.lightDestructive;
        bg = fg.withOpacity(0.12);
      case BadgeTone.info:
        fg = AppColors.infoFg;
        bg = AppColors.infoBg;
      case BadgeTone.muted:
        fg = dark ? AppColors.darkMutedFg : AppColors.lightMutedFg;
        bg = fg.withOpacity(0.14);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg, height: 1.3),
      ),
    );
  }
}

/// شارة حالة صلاحية التشغيلة بأيام متبقية (كصفحة المخزون في الويب)
class ExpiryBadge extends StatelessWidget {
  final int? days;
  const ExpiryBadge(this.days, {super.key});

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    if (days == null) return const SizedBox.shrink();
    final d = days!;
    if (d < 0) return AppBadge(i18n.t('inventory', 'expired'), tone: BadgeTone.destructive);
    if (d <= 30) return AppBadge(i18n.t('inventory', 'expires_30', {'days': '$d'}), tone: BadgeTone.destructive);
    if (d <= 60) return AppBadge(i18n.t('inventory', 'expires_60', {'days': '$d'}), tone: BadgeTone.warning);
    if (d <= 90) return AppBadge(i18n.t('inventory', 'expires_90', {'days': '$d'}), tone: BadgeTone.info);
    return const SizedBox.shrink();
  }
}

// ---------------------------------------------------------------- إحصائيات

enum StatTone { primary, warning, success, info }

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final StatTone tone;
  const StatCard({super.key, required this.label, required this.value, required this.icon, required this.tone});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    late final Color fg;
    late final Color bg;
    switch (tone) {
      case StatTone.warning:
        fg = AppColors.warningFg;
        bg = AppColors.warningBg;
      case StatTone.success:
        fg = AppColors.successFg;
        bg = AppColors.successBg;
      case StatTone.info:
        fg = AppColors.infoFg;
        bg = AppColors.infoBg;
      case StatTone.primary:
        fg = dark ? AppColors.darkPrimary : AppColors.lightPrimary;
        bg = fg.withOpacity(0.10);
    }
    return AppCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 20, color: fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.6))),
                const SizedBox(height: 2),
                FittedBox(child: Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- حقول

class AppField extends StatelessWidget {
  final String label;
  final Widget child;
  final String? hint;
  const AppField({super.key, required this.label, required this.child, this.hint});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        if (hint != null) ...<Widget>[
          const SizedBox(height: 2),
          Text(hint!, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.5))),
        ],
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class AppInput extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboard;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final int maxLines;
  final FocusNode? focusNode;
  const AppInput({super.key, required this.controller, this.hint, this.obscure = false,
      this.keyboard, this.validator, this.onChanged, this.enabled = true, this.maxLines = 1, this.focusNode});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      validator: validator,
      onChanged: onChanged,
      enabled: enabled,
      maxLines: maxLines,
      focusNode: focusNode,
      decoration: InputDecoration(hintText: hint),
      style: const TextStyle(fontSize: 14),
    );
  }
}

class AppDropdown<T> extends StatelessWidget {
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? hint;
  const AppDropdown({super.key, required this.value, required this.items, required this.onChanged, this.hint});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      hint: hint == null ? null : Text(hint!, style: const TextStyle(fontSize: 14)),
      isExpanded: true,
      decoration: const InputDecoration(),
      style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
    );
  }
}

class AppSwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const AppSwitchTile({super.key, required this.title, this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              if (subtitle != null)
                Text(subtitle!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55))),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged, activeColor: Theme.of(context).colorScheme.primary),
      ],
    );
  }
}

// ---------------------------------------------------------------- حالات

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? actionText;
  final VoidCallback? onAction;
  const EmptyState(this.text, {super.key, this.icon = Icons.inbox_outlined, this.actionText, this.onAction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: Column(
          children: [
            Icon(icon, size: 44, color: theme.colorScheme.onSurface.withOpacity(0.25)),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.55)),
            ),
            if (actionText != null && onAction != null) ...<Widget>[
              const SizedBox(height: 12),
              GhostButton(actionText!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorRetry(this.message, {super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: Theme.of(context).colorScheme.error.withOpacity(0.06),
      child: Column(
        children: [
          Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          GhostButton(AppI18n.instance.t('common', 'retry'), onPressed: onRetry, icon: Icons.refresh),
        ],
      ),
    );
  }
}

class LoadingBox extends StatelessWidget {
  const LoadingBox({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
    );
  }
}

// ---------------------------------------------------------------- حوارات

Future<bool?> confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  String? confirmText,
  bool destructive = false,
}) {
  final i18n = AppI18n.instance;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body, style: const TextStyle(fontSize: 14)),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(i18n.t('common', 'cancel'))),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error)
              : null,
          child: Text(confirmText ?? i18n.t('common', 'confirm')),
        ),
      ],
    ),
  );
}

Future<void> appSnackbar(BuildContext context, String message, {bool error = false}) {
  return ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? Theme.of(context).colorScheme.error : null,
  )).closed;
}

/// ورقة سفلية بعنوان — نسخة الموبايل من Modal في الويب
Future<T?> appBottomSheet<T>(BuildContext context, {required String title, required Widget child}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------- صفوف وعرض

class KVRow extends StatelessWidget {
  final String label;
  final String value;
  final bool money;
  const KVRow(this.label, this.value, {super.key, this.money = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.55)))),
          Expanded(
            flex: 3,
            child: Text(
              money ? AppI18n.instance.locale == 'ar' ? value : value : value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// صف مبلغ بقالة فاصلة خفيفة (سطور الفاتورة والتقارير)
class AmountRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final int amountPiastres;
  final bool credit; // آجل
  final Widget? leading;
  final VoidCallback? onTap;
  const AmountRow({super.key, required this.title, this.subtitle, required this.amountPiastres,
      this.credit = false, this.leading, this.onTap});

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final amount = Fmt.money(amountPiastres, locale: i18n.locale);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: onTap,
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[leading!, const SizedBox(width: 10)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                if (subtitle != null)
                  Text(subtitle!, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.5))),
              ],
            ),
          ),
          Text(amount, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: credit ? AppColors.warningFg : null)),
        ],
      ),
    );
  }
}

class SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  const SearchField({super.key, required this.controller, required this.hint, this.onChanged, this.onClear});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onClear),
        isDense: true,
      ),
      style: const TextStyle(fontSize: 14),
    );
  }
}

class PaginationRow extends StatelessWidget {
  final int total;
  final int limit;
  final int offset;
  final ValueChanged<int> onOffset;
  const PaginationRow({super.key, required this.total, required this.limit, required this.offset, required this.onOffset});

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final canPrev = offset > 0;
    final canNext = offset + limit < total;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        OutlinedButton(
          onPressed: canPrev ? () => onOffset(offset - limit) : null,
          child: Text(i18n.t('common', 'previous')),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(i18n.t('common', 'page_of', {'total': Fmt.number(total)}),
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.6))),
        ),
        OutlinedButton(
          onPressed: canNext ? () => onOffset(offset + limit) : null,
          child: Text(i18n.t('common', 'next')),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- الرسم البياني

/// رسم أعمدة مبسّط (CustomPainter بلا حزم خارجية) لمنحنى المبيعات اليومي
/// في تقرير المبيعات — نفس فكرة BarChart في الويب.
class MiniBarChart extends StatelessWidget {
  final List<({String label, int value})> points;
  final String tooltipSuffix;
  final Color? barColor;
  const MiniBarChart({super.key, required this.points, this.tooltipSuffix = '', this.barColor});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final color = barColor ?? (theme.brightness == Brightness.dark ? AppColors.darkPrimary : AppColors.lightPrimary);
    final maxV = points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
    if (maxV <= 0) return const SizedBox.shrink();
    return SizedBox(
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (final p in points)
            Expanded(
              child: Tooltip(
                message: '${p.label}: ${Fmt.money(p.value, locale: AppI18n.instance.locale)}$tooltipSuffix',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: LayoutBuilder(builder: (BuildContext ctx, BoxConstraints c) {
                    final h = (p.value / maxV) * (c.maxHeight - 18);
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        Container(
                          height: h < 2 ? 2 : h,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.85),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          p.label.length > 5 ? p.label.substring(p.label.length - 5) : p.label,
                          style: TextStyle(fontSize: 8, color: theme.colorScheme.onSurface.withOpacity(0.45)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
        ],
      ),
    );
  }
}


/// اختيار بين خيارين (نقدي/آجل، إضافة/خصم) — مستخدم في نقطة البيع والتسوية
class PayChoice extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const PayChoice({super.key, required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: AppRadius.br,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary.withOpacity(0.10) : Colors.transparent,
          borderRadius: AppRadius.br,
          border: Border.all(color: selected ? theme.colorScheme.primary : theme.dividerColor, width: selected ? 1.4 : 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 18, color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.6)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.7))),
          ],
        ),
      ),
    );
  }
}
