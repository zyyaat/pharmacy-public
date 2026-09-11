import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/ui.dart';
import 'home_screen.dart';

/// ترحيل المنتجات — خطوات صفحة الويب الثلاث: رفع الملف (+ نموذج جاهز
/// للتنزيل) ← المعاينة والربط (اقتراح تلقائي قابل للتعديل) ← التقرير.
/// خيارات الترحيل (التكرار، وحدة الكمية، ترحيل المخزون) كما هي تمامًا.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});
  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  PlatformFile? _file;
  ImportPreview? _preview;
  Map<String, int> _mapping = <String, int>{};
  bool _duplicateUpdate = false;
  bool _qtyStrip = false;
  bool _importStock = true;
  bool _busy = false;
  bool _downloading = false;
  String? _error;
  ImportReport? _report;

  /// الحقول المرتبطة — المفاتيح هي عقد الباكند حرفيًا (product_import_handler.go:
  /// ifMinStock = min_stock_level ، ifExpiry = expiry_date ، ifBatch =
  /// batch_number) كما في صفحة الويب، وإلا تُهمل هذه الحقول بصمت عند التنفيذ.
  /// التسميات من نطاق settings
  static const List<(String, String)> _fields = <(String, String)>[
    ('name', 'fieldName'),
    ('generic_name', 'fieldGenericName'),
    ('barcode', 'fieldBarcode'),
    ('strength', 'fieldStrength'),
    ('dosage_form', 'fieldDosageForm'),
    ('units_per_box', 'fieldUnitsPerBox'),
    ('selling_price', 'fieldSellingPrice'),
    ('cost_price', 'fieldCostPrice'),
    ('partial_price', 'fieldPartialPrice'),
    ('quantity', 'fieldQuantity'),
    ('min_stock_level', 'fieldMinStock'),
    ('expiry_date', 'fieldExpiry'),
    ('batch_number', 'fieldBatch'),
  ];

  Future<void> _pickFile() async {
    final i18n = AppI18n.instance;
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['xlsx', 'csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        setState(() => _busy = false);
        return;
      }
      final file = result.files.first;
      final preview = await _previewUpload(file);
      if (!mounted) return;
      setState(() {
        _file = file;
        _preview = preview;
        _mapping = preview.mapping;
        _report = null;
        _busy = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('settings', 'parseErrorFallback'));
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = i18n.t('settings', 'parseErrorFallback');
        _busy = false;
      });
    }
  }

  Future<ImportPreview> _previewUpload(PlatformFile file) async {
    final api = ApiClient.instance;
    final form = FormData.fromMap(<String, dynamic>{
      'file': MultipartFile.fromBytes(file.bytes!, filename: file.name),
    });
    final res = await api.dio.post<Map<String, dynamic>>('/pharmacy/imports/products/preview', data: form);
    final data = res.data?['data'];
    return ImportPreview.fromJson(data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{});
  }

  Future<void> _reestimate() async {
    if (_file == null) return;
    final form = FormData.fromMap(<String, dynamic>{
      'file': MultipartFile.fromBytes(_file!.bytes!, filename: _file!.name),
      'mapping': MultipartFile.fromString(jsonEncode(_mapping)),
    });
    try {
      final res = await ApiClient.instance.dio.post<Map<String, dynamic>>(
        '/pharmacy/imports/products/preview',
        data: form,
      );
      final data = res.data?['data'];
      if (data is Map && mounted) {
        setState(() => _preview = ImportPreview.fromJson(Map<String, dynamic>.from(data)));
      }
    } catch (_) {
      // إعادة التقدير اختيارية — فشلها لا يوقف الترحيل
    }
  }

  Future<void> _execute() async {
    final i18n = AppI18n.instance;
    if (_file == null || _busy) return;
    if ((_mapping['name'] ?? -1) < 0) {
      setState(() => _error = i18n.t('settings', 'nameColumnRequired'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final form = FormData.fromMap(<String, dynamic>{
        'file': MultipartFile.fromBytes(_file!.bytes!, filename: _file!.name),
        'mapping': MultipartFile.fromString(jsonEncode(_mapping)),
        'options': MultipartFile.fromString(jsonEncode(<String, dynamic>{
          'duplicate_strategy': _duplicateUpdate ? 'update' : 'skip',
          'quantity_unit': _qtyStrip ? 'strip' : 'box',
          'import_stock': _importStock,
        })),
      });
      final res = await ApiClient.instance.dio.post<Map<String, dynamic>>(
        '/pharmacy/imports/products/execute',
        data: form,
      );
      final data = res.data?['data'];
      if (!mounted) return;
      setState(() {
        _report = ImportReport.fromJson(data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{});
        _busy = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('settings', 'executeErrorFallback'));
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = i18n.t('settings', 'executeErrorFallback');
        _busy = false;
      });
    }
  }

  /// تنزيل نموذج الترحيل — GET /pharmacy/imports/products/template كما في
  /// صفحة الويب (page.tsx:255-259). الجلسة عبر عميل dio نفسه: الـinterceptor
  /// في api_client يرفق كوكي الاعتماد تلقائيًا (GET بلا حاجة لـCSRF). نختار
  /// وجهة الحفظ عبر file_picker (أندرويد/iOS يكتبان البايتات مباشرة)،
  /// وعلى سطح المكتب الذي يعيد المسار دون كتابة نكتب البايتات عبر dart:io.
  Future<void> _downloadTemplate() async {
    if (_downloading) return;
    final i18n = AppI18n.instance;
    setState(() => _downloading = true);
    try {
      final Response<List<int>> res = await ApiClient.instance.dio.get<List<int>>(
        '/pharmacy/imports/products/template',
        options: Options(responseType: ResponseType.bytes),
      );
      final Uint8List bytes = Uint8List.fromList(res.data ?? <int>[]);
      if (!mounted) return;
      final String? path = await FilePicker.platform.saveFile(
        fileName: i18n.t('settings', 'templateFileName'),
        bytes: bytes,
      );
      if (path == null) return; // المستخدم ألغى حوار الحفظ — لا خطأ
      try {
        final File f = File(path);
        if (!await f.exists() || await f.length() == 0) {
          await f.writeAsBytes(bytes, flush: true); // سطح المكتب فقط
        }
      } catch (_) {
        // على الجوّال كُتب المحتوى سلفًا من file_picker عبر URI المحتوى —
        // فشل إعادة الكتابة لا يعني فشل التنزيل
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(i18n.t('settings', 'templateErrorFallback')),
      ));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  /// «فتح المخزون» بعد التقرير — مثل window.location.assign('/inventory')
  /// في الويب: نُنشّط صفحة المخزون في الشل إن وصل إليها السياق (الجسر نفسه
  /// الذي تستخدمه HomeNav)، وإلا نبقي السلوك الحالي بالرجوع. عمليًا الشاشة
  /// مدفوعة فوق جذر التنقّل فالشل ليس سلفًا للسياق — يبقى الرجوع هو المسار،
  /// والكود جاهز إن صارت الشاشة جزءًا من الشل لاحقًا.
  void _openInventory() {
    final HomeShellState? shell = context.findAncestorStateOfType<HomeShellState>();
    if (shell != null) shell.goTo('inventory');
    Navigator.of(context).pop();
  }

  Future<void> _reset() async {
    setState(() {
      _file = null;
      _preview = null;
      _report = null;
      _error = null;
      _mapping = <String, int>{};
    });
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    // خطوة الويب الحالية: التقرير = 3، المعاينة والربط = 2، غير ذلك الرفع = 1
    final int step = _report != null ? 3 : (_preview != null ? 2 : 1);
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('settings', 'importTitle'))),
      body: _busy
          ? const LoadingBox()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Text(i18n.t('settings', 'importSubtitle'),
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                const SizedBox(height: 14),
                _buildSteps(i18n, theme, step),
                const SizedBox(height: 16),
                if (_report != null) ..._buildReport(i18n, theme)
                else if (_preview != null) ..._buildMappingStep(i18n, theme)
                else ..._buildUploadStep(i18n, theme),
              ],
            ),
    );
  }

  // -------------------------------------------------------------- الخطوة 1

  List<Widget> _buildUploadStep(AppI18n i18n, ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    return <Widget>[
      AppCard(
        child: Column(
          children: <Widget>[
            Icon(Icons.upload_file_outlined, size: 40, color: theme.colorScheme.primary.withOpacity(0.6)),
            const SizedBox(height: 10),
            Text(i18n.t('settings', 'uploadTitle'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(i18n.t('settings', 'uploadDesc', {'rows': Fmt.number(5000)}), style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55)), textAlign: TextAlign.center),
            const SizedBox(height: 14),
            PrimaryButton(i18n.t('settings', 'dropHere'), icon: Icons.folder_open_outlined, onPressed: _pickFile),
            const SizedBox(height: 6),
            Text(i18n.t('settings', 'firstRowHint'), style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.5))),
            const SizedBox(height: 14),
            // صندوق النموذج الجاهز — مثل صفحة الويب (page.tsx:244-265):
            // rounded-xl border bg-muted/20 مع أيقونة معلومات وزر تنزيل
            SizedBox(
              width: double.infinity,
              child: CardBox(
                padding: const EdgeInsets.all(12),
                color: dark ? AppColors.darkMuted : AppColors.lightMuted,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(Icons.info_outline, size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            i18n.t('settings', 'templateHint'),
                            style: TextStyle(fontSize: 12, height: 1.5, color: theme.colorScheme.onSurface.withOpacity(0.75)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SecondaryButton(
                      i18n.t('settings', 'downloadTemplate'),
                      icon: Icons.download_outlined,
                      onPressed: _downloading ? null : _downloadTemplate,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      if (_error != null) ...<Widget>[
        const SizedBox(height: 12),
        Text(_error!, style: TextStyle(fontSize: 12, color: theme.colorScheme.error), textAlign: TextAlign.center),
      ],
    ];
  }

  // -------------------------------------------------------------- الخطوة 2

  List<Widget> _buildMappingStep(AppI18n i18n, ThemeData theme) {
    final preview = _preview!;
    return <Widget>[
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: CardTitle(i18n.t('settings', 'mappingTitle'))),
                // شارة نوع الملف كما في الويب: preview.file_type.toUpperCase()
                if (preview.fileType.isNotEmpty) ...<Widget>[
                  AppBadge(preview.fileType.toUpperCase(), tone: BadgeTone.muted),
                  const SizedBox(width: 6),
                ],
                AppBadge(i18n.t('settings', 'rowsBadge', {'rows': Fmt.number(preview.totalRows)}), tone: BadgeTone.primary),
                const SizedBox(width: 6),
                AppBadge(i18n.t('settings', 'validBadge', {'rows': Fmt.number(preview.validEstimate)}), tone: BadgeTone.success),
                const SizedBox(width: 6),
                AppBadge(i18n.t('settings', 'invalidBadge', {'rows': Fmt.number(preview.invalidEstimate)}), tone: BadgeTone.warning),
              ],
            ),
            const SizedBox(height: 6),
            Text(i18n.t('settings', 'mappingDesc'), style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.55))),
            const SizedBox(height: 12),
            for (final (String field, String labelKey) in _fields)
              if (!(field == 'partial_price' && !_mapping.containsKey('partial_price') && preview.mapping['partial_price'] == null) || _mapping.containsKey(field))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _MappingRow(
                    label: _fieldLabel(i18n, labelKey),
                    isRequired: field == 'name',
                    value: _mapping[field] ?? -1,
                    headers: preview.headers,
                    onChanged: (int? v) {
                      setState(() => _mapping[field] = v ?? -1);
                      _reestimate();
                    },
                  ),
                ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CardTitle(i18n.t('settings', 'optionsTitle')),
            const SizedBox(height: 8),
            AppDropdown<String>(
              value: _duplicateUpdate ? 'update' : 'skip',
              items: <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(value: 'skip', child: Text(i18n.t('settings', 'duplicateSkip'), style: const TextStyle(fontSize: 13))),
                DropdownMenuItem<String>(value: 'update', child: Text(i18n.t('settings', 'duplicateUpdate'), style: const TextStyle(fontSize: 13))),
              ],
              onChanged: (String? v) => setState(() => _duplicateUpdate = v == 'update'),
            ),
            Text(i18n.t('settings', 'duplicateNote'), style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.5))),
            const SizedBox(height: 10),
            AppDropdown<String>(
              value: _qtyStrip ? 'strip' : 'box',
              items: <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(value: 'box', child: Text(i18n.t('settings', 'quantityBox'), style: const TextStyle(fontSize: 13))),
                DropdownMenuItem<String>(value: 'strip', child: Text(i18n.t('settings', 'quantityStrip'), style: const TextStyle(fontSize: 13))),
              ],
              onChanged: (String? v) => setState(() => _qtyStrip = v == 'strip'),
            ),
            AppSwitchTile(title: i18n.t('settings', 'importStockLabel'), value: _importStock, onChanged: (bool v) => setState(() => _importStock = v)),
          ],
        ),
      ),
      const SizedBox(height: 12),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CardTitle(i18n.t('settings', 'sampleTitle', {'rows': Fmt.number(preview.rows.length > 5 ? 5 : preview.rows.length)})),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                dataTextStyle: const TextStyle(fontSize: 11),
                columnSpacing: 18,
                columns: <DataColumn>[
                  for (final String h in preview.headers.take(6)) DataColumn(label: Text(h, overflow: TextOverflow.ellipsis)),
                ],
                rows: <DataRow>[
                  for (final List<String> row in preview.rows.take(5))
                    DataRow(cells: <DataCell>[
                      for (final String cell in row.take(6)) DataCell(SizedBox(width: 80, child: Text(cell, overflow: TextOverflow.ellipsis))),
                    ]),
                ],
              ),
            ),
          ],
        ),
      ),
      if (_error != null) ...<Widget>[
        const SizedBox(height: 12),
        Text(_error!, style: TextStyle(fontSize: 12, color: theme.colorScheme.error), textAlign: TextAlign.center),
      ],
      const SizedBox(height: 14),
      PrimaryButton(
        i18n.t('settings', 'executeBtn', {'rows': Fmt.number(preview.validEstimate)}),
        icon: Icons.upload,
        onPressed: _execute,
      ),
      const SizedBox(height: 8),
      SecondaryButton(i18n.t('settings', 'anotherFile'), icon: Icons.refresh, onPressed: _reset),
    ];
  }

  /// تسميات حقول الربط من القاموس. تنبيه: مفتاح fieldName غير موجود في
  /// كتالوج الموبايل ولا حتى في كتالوجات الويب (الويب يعرض المسار الخام
  /// 'settings.fieldName' برجوعه المرئي) — نستبدل الـsentinel بتسمية thProduct
  /// الموجودة والمترجمة حتى يُضاف المفتاح إلى الكتالوج.
  String _fieldLabel(AppI18n i18n, String labelKey) {
    final resolved = i18n.t('settings', labelKey);
    if (labelKey == 'fieldName' && resolved == 'settings.fieldName') {
      return i18n.t('settings', 'thProduct');
    }
    return resolved;
  }

  // -------------------------------------------------------------- الخطوة 3

  List<Widget> _buildReport(AppI18n i18n, ThemeData theme) {
    final r = _report!;
    return <Widget>[
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CardTitle(i18n.t('settings', 'doneTitle'), subtitle: i18n.t('settings', 'doneDesc')),
            const SizedBox(height: 12),
            KVRow(i18n.t('settings', 'reportCreated'), Fmt.number(r.created)),
            KVRow(i18n.t('settings', 'reportUpdated'), Fmt.number(r.updated)),
            KVRow(i18n.t('settings', 'reportSkipped'), Fmt.number(r.skipped)),
            KVRow(i18n.t('settings', 'reportFailed'), Fmt.number(r.failed)),
            if (r.stockLines > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(i18n.t('settings', 'stockLinesNote', {'rows': Fmt.number(r.stockLines)}),
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.55))),
              ),
          ],
        ),
      ),
      if (r.errors.isNotEmpty) ...<Widget>[
        const SizedBox(height: 14),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CardTitle(i18n.t('settings', 'rejectedTitle', {'count': Fmt.number(r.errors.length)}), subtitle: i18n.t('settings', 'rejectedDesc')),
              const SizedBox(height: 8),
              // كل الصفوف المرفوضة (بلا سقف الـ20) بجدول الويب نفسه:
              // الصف / الصنف / السبب — قائمة قابلة للتمرير عموديًا
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: WebTable(
                    minWidth: 520,
                    headers: <String>[
                      i18n.t('settings', 'thRow'),
                      i18n.t('settings', 'thProduct'),
                      i18n.t('settings', 'thReason'),
                    ],
                    rows: <List<Widget>>[
                      for (final err in r.errors)
                        <Widget>[
                          Text(Fmt.number(err.row),
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: theme.colorScheme.error)),
                          Text(err.name.isEmpty ? '—' : err.name, style: const TextStyle(fontSize: 12)),
                          Text(err.reason, style: TextStyle(fontSize: 12, color: theme.colorScheme.error)),
                        ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 14),
      PrimaryButton(i18n.t('settings', 'importAnotherFile'), icon: Icons.upload_file, onPressed: _reset),
      const SizedBox(height: 8),
      SecondaryButton(i18n.t('settings', 'openInventory'), icon: Icons.medication_outlined, onPressed: _openInventory),
    ];
  }

  /// مؤشر الخطوات الثلاث — ol الحبوب في الويب (page.tsx:174-193):
  /// الحالية bg-primary text-primary-foreground، المنتهية bg-primary/10
  /// text-primary، والقادمة bg-muted text-muted-foreground، وبينها سهم
  /// يتبع اتجاه القراءة (نظير rtl-flip بالويب).
  Widget _buildSteps(AppI18n i18n, ThemeData theme, int step) {
    final dark = theme.brightness == Brightness.dark;
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    final List<String> labels = <String>[
      i18n.t('settings', 'stepUpload'),
      i18n.t('settings', 'stepPreview'),
      i18n.t('settings', 'stepReport'),
    ];
    Widget pill(int n) {
      final bool current = step == n;
      final bool done = step > n;
      final Color bg = current
          ? theme.colorScheme.primary
          : done
              ? theme.colorScheme.primary.withOpacity(0.10)
              : (dark ? AppColors.darkMuted : AppColors.lightMuted);
      final Color fg = current
          ? theme.colorScheme.onPrimary
          : done
              ? theme.colorScheme.primary
              : (dark ? AppColors.darkMutedFg : AppColors.lightMutedFg);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('$n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
            const SizedBox(width: 6),
            Text(labels[n - 1],
                style: TextStyle(fontSize: 12, fontWeight: current ? FontWeight.w700 : FontWeight.w500, color: fg)),
          ],
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        pill(1),
        for (int n = 2; n <= 3; n++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(rtl ? '←' : '→', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.45))),
              const SizedBox(width: 8),
              pill(n),
            ],
          ),
      ],
    );
  }
}

class _MappingRow extends StatelessWidget {
  final String label;
  final bool isRequired;
  final int value;
  final List<String> headers;
  final ValueChanged<int?> onChanged;
  const _MappingRow({required this.label, this.isRequired = false, required this.value, required this.headers, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 120,
          child: Text.rich(
            // الحقل المطلوب بنجمة حمراء لاحقة مثل الويب (f.required → ' *')
            TextSpan(
              text: label,
              children: <InlineSpan>[
                if (isRequired)
                  TextSpan(text: ' *', style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700)),
              ],
            ),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: AppDropdown<int>(
            value: value,
            items: <DropdownMenuItem<int>>[
              DropdownMenuItem<int>(value: -1, child: Text(AppI18n.instance.t('settings', 'unlinkedOption'), style: const TextStyle(fontSize: 12))),
              for (var i = 0; i < headers.length; i++)
                DropdownMenuItem<int>(value: i, child: Text(headers[i], style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
            ],
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
