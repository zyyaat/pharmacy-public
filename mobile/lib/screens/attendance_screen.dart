import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../models/models.dart';
import '../widgets/ui.dart';

/// Task 62/68 — الحضور بنسخة الويب حرفيًا: رأس صفحة + بطاقة واحدة بعنوان
/// بأيقونة التقويم، وجدول: الموظف/الفرع/الدخول/الخروج/الحالة.
/// الحالة تُقرأ من item.status المُحلَّل (active → حاضر الآن، completed →
/// مكتمل، وإلا النص الخام كما بالويب) وتُعرض كشارة.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  List<AttendanceRow> _rows = <AttendanceRow>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final i18n = AppI18n.instance;
    try {
      final page = await ApiClient.instance.attendance();
      if (!mounted) return;
      setState(() {
        _rows = page.rows;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('employees', 'attendanceLoadErrorFallback'));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = i18n.t('employees', 'attendanceLoadErrorFallback');
        _loading = false;
      });
    }
  }

  /// حالة السجل كما بالويب (page.tsx:34): active → حاضر الآن،
  /// completed → مكتمل، وإلا النص الخام من الخادم.
  Widget _statusCell(AttendanceRow r) {
    final i18n = AppI18n.instance;
    switch (r.status) {
      case 'active':
        return AppBadge(i18n.t('employees', 'nowActive'), tone: BadgeTone.success);
      case 'completed':
        return AppBadge(i18n.t('employees', 'completed'), tone: BadgeTone.muted);
      default:
        return AppBadge(r.status.isNotEmpty ? r.status : '—', tone: BadgeTone.muted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final muted = TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5));
    // الويب يُبقي هيكل الصفحة (رأس + بطاقة) ويصير التحميل/الخطأ داخل
    // محتوى البطاقة (page.tsx:31-32) — لا يستبدل الصفحة كاملة.
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          PageHeader(
            i18n.t('employees', 'attendanceTitle'),
            subtitle: i18n.t('employees', 'attendanceSubtitle'),
          ),
          const SizedBox(height: 24),
          AppCard(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: CardTitle(i18n.t('employees', 'attendanceListTitle'),
                      icon: Icons.event_available_outlined),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: _loading
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: Text(i18n.t('common', 'loading'), style: muted)),
                        )
                      : _error != null
                          ? ErrorRetry(_error!, onRetry: _load)
                          : _rows.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 40),
                                  child: Text(i18n.t('employees', 'attendanceEmpty'), style: muted),
                                )
                              : WebTable(
                                  minWidth: 720, // min-w-[720px] كما بالويب
                                  headers: <String>[
                                    i18n.t('employees', 'thEmployee'),
                                    i18n.t('employees', 'thBranch'),
                                    i18n.t('employees', 'thClockIn'),
                                    i18n.t('employees', 'thClockOut'),
                                    i18n.t('employees', 'thStatus'),
                                  ],
                                  rows: <List<Widget>>[
                                    for (final AttendanceRow r in _rows)
                                      <Widget>[
                                        Text(r.employeeName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                        Text(r.branchName.isEmpty ? '—' : r.branchName),
                                        Text(Fmt.dateTime(r.clockIn, locale: i18n.locale)),
                                        Text((r.clockOut == null || r.clockOut!.isEmpty) ? '—' : Fmt.dateTime(r.clockOut, locale: i18n.locale)),
                                        _statusCell(r),
                                      ],
                                  ],
                                ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
