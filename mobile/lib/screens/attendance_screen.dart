import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../models/models.dart';
import '../widgets/ui.dart';

/// الحضور والانصراف — سجل الحضور الحقيقي كما في صفحة الويب:
/// موظف، فرع، دخول، خروج، مدة، وحالة (حاضر الآن / مكتمل).
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
        _error = AppI18n.instance.t('employees', 'attendanceLoadErrorFallback');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('employees', 'attendanceTitle'))),
      body: _loading
          ? const LoadingBox()
          : _error != null
              ? ErrorRetry(_error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _rows.isEmpty
                      ? ListView(children: <Widget>[EmptyState(i18n.t('employees', 'attendanceEmpty'), icon: Icons.event_available_outlined)])
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (BuildContext ctx, int i) {
                            final AttendanceRow r = _rows[i];
                            final active = r.clockOut == null || r.clockOut!.isEmpty;
                            return AppCard(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Expanded(child: Text(r.employeeName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                                      AppBadge(active ? i18n.t('employees', 'nowActive') : i18n.t('employees', 'completed'),
                                          tone: active ? BadgeTone.success : BadgeTone.muted),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: <Widget>[
                                      _TimeCell(label: i18n.t('employees', 'thClockIn'), value: Fmt.time(r.clockIn)),
                                      const SizedBox(width: 16),
                                      _TimeCell(label: i18n.t('employees', 'thClockOut'), value: active ? '—' : Fmt.time(r.clockOut)),
                                      const SizedBox(width: 16),
                                      _TimeCell(label: i18n.t('employees', 'thDuration').isEmpty ? 'المدة' : 'المدة', value: Fmt.duration(r.totalMinutes)),
                                    ],
                                  ),
                                  if (r.branchName.isNotEmpty) ...<Widget>[
                                    const SizedBox(height: 6),
                                    Text('${i18n.t('employees', 'thBranch')}: ${r.branchName}',
                                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}

class _TimeCell extends StatelessWidget {
  final String label;
  final String value;
  const _TimeCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      ],
    );
  }
}
