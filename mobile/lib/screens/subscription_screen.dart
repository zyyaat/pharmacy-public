import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/strings.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';

/// Task 90 — شاشة الاشتراك: الخطة الحالية + عدادات الاستهلاك + الخطط
/// المتاحة. الدفع الذاتي يُضاف مع Paymob؛ الآن الإرشادات تظهر هنا والإسناد
/// اليدوي من لوحة المشرف. النقاط المصدرية ضمن allow-list فتعمل مع انتهاء
/// التجربة أيضًا.
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  List<PublicPlanInfo>? _plans;

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    final state = context.read<AppState>();
    try {
      final plans = await state.api.subscriptionPlans();
      if (mounted) setState(() => _plans = plans);
    } catch (_) {
      if (mounted) setState(() => _plans = const <PublicPlanInfo>[]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final sub = state.subscription;

    return Scaffold(
      appBar: AppBar(
        title: Text(i18n.t('subscription', 'title')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          PageHeader(i18n.t('subscription', 'title'),
              subtitle: i18n.t('subscription', 'subtitle')),
          const SizedBox(height: 24),
          _planCard(context, i18n, theme, sub),
          const SizedBox(height: 24),
          if (sub != null) ...<Widget>[
            Text(i18n.t('subscription', 'usage_title'),
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _usageCard(context, i18n, sub),
            const SizedBox(height: 24),
          ],
          Text(i18n.t('subscription', 'plans_title'),
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(i18n.t('subscription', 'plans_subtitle'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          ...(_plans ?? const <PublicPlanInfo>[])
              .map((plan) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _planTile(context, i18n, plan),
                  )),
          const SizedBox(height: 16),
          Text(i18n.t('subscription', 'contact_owner'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _planCard(BuildContext context, AppI18n i18n, ThemeData theme,
      SubscriptionState? sub) {
    if (sub == null) {
      return const AppCard(
        child: SizedBox(height: 60),
      );
    }
    final statusKey = 'status_${sub.status}';
    final deadline = sub.status == 'trial' ? sub.trialEndsAt : sub.periodEnd;
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(i18n.t('subscription', 'plan_label'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            Text(sub.planNameAr.isNotEmpty ? sub.planNameAr : sub.planName,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: sub.isGranted
                    ? theme.colorScheme.primary.withOpacity(0.10)
                    : theme.colorScheme.error.withOpacity(0.10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                i18n.t('subscription', statusKey),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: sub.isGranted
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
              ),
            ),
            if (deadline != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                sub.status == 'trial'
                    ? i18n.t('subscription', 'trial_ends',
                        <String, Object?>{'date': Fmt.date(deadline)})
                    : i18n.t('subscription', 'renews_on',
                        <String, Object?>{'date': Fmt.date(deadline)}),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (sub.isTrialEnding) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                sub.daysLeft <= 0
                    ? i18n.t('subscription', 'trial_banner_last')
                    : i18n.t('subscription', 'trial_banner',
                        <String, Object?>{'days': sub.daysLeft}),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _usageCard(
      BuildContext context, AppI18n i18n, SubscriptionState sub) {
    final theme = Theme.of(context);
    const labels = <String, String>{
      'branches': 'limit_branches',
      'users': 'limit_users',
      'employees': 'limit_employees',
      'products': 'limit_products',
    };
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            for (final entry in labels.entries)
              if (sub.limits.containsKey(entry.key))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(i18n.t('subscription', entry.value)),
                      ),
                      Text(
                        '${Fmt.number(sub.usage[entry.key] ?? 0)} / '
                        '${sub.limits[entry.key] == -1 ? i18n.t('subscription', 'unlimited') : Fmt.number(sub.limits[entry.key] ?? 0)}',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _planTile(BuildContext context, AppI18n i18n, PublicPlanInfo plan) {
    final theme = Theme.of(context);
    final state = context.watch<AppState>();
    final sub = state.subscription;
    final isCurrent = sub?.planSlug == plan.slug;
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(plan.nameAr.isNotEmpty ? plan.nameAr : plan.name,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                if (isCurrent)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(i18n.t('subscription', 'current_plan'),
                        style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.primary)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${Fmt.number(plan.monthlyPiastres / 100)} ${plan.currency} '
              '${i18n.t('subscription', 'per_month')}',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final entry in plan.limits.entries)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${entry.key}: ${entry.value == -1 ? i18n.t('subscription', 'unlimited') : Fmt.number(entry.value)}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
