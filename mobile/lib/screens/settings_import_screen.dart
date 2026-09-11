import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../models/models.dart';
import '../widgets/ui.dart';

/// ترحيل المنتجات — خطوات صفحة الويب الثلاث: رفع الملف ← المعاينة
/// والربط (اقتراح تلقائي قابل للتعديل) ← التقرير. خيارات الترحيل
/// (التكرار، وحدة الكمية، ترحيل المخزون) كما هي تمامًا.
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
  String? _error;
  ImportReport? _report;

  /// الحقول المرتبطة (نفس خريطة الويب) — التسميات من نطاق settings
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
    ('min_stock', 'fieldMinStock'),
    ('expiry', 'fieldExpiry'),
    ('batch', 'fieldBatch'),
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
                if (_report != null) ..._buildReport(i18n, theme)
                else if (_preview != null) ..._buildMappingStep(i18n, theme)
                else ..._buildUploadStep(i18n, theme),
              ],
            ),
    );
  }

  // -------------------------------------------------------------- الخطوة 1

  List<Widget> _buildUploadStep(AppI18n i18n, ThemeData theme) {
    return <Widget>[
      AppCard(
        child: Column(
          children: <Widget>[
            Icon(Icons.upload_file_outlined, size: 40, color: theme.colorScheme.primary.withOpacity(0.6)),
            const SizedBox(height: 10),
            Text(i18n.t('settings', 'uploadTitle'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(i18n.t('settings', 'uploadDesc'), style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55)), textAlign: TextAlign.center),
            const SizedBox(height: 14),
            PrimaryButton(i18n.t('settings', 'dropHere'), icon: Icons.folder_open_outlined, onPressed: _pickFile),
            const SizedBox(height: 6),
            Text(i18n.t('settings', 'firstRowHint'), style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.5))),
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
                    label: labelKey == 'fieldName' ? 'اسم الصنف *' : i18n.t('settings', labelKey),
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
              for (final err in r.errors.take(20))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('#${Fmt.number(err.row)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: theme.colorScheme.error)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('${err.name} — ${err.reason}', style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 14),
      PrimaryButton(i18n.t('settings', 'importAnotherFile'), icon: Icons.upload_file, onPressed: _reset),
      const SizedBox(height: 8),
      SecondaryButton(i18n.t('settings', 'openInventory'), icon: Icons.medication_outlined,
          onPressed: () => Navigator.of(context).pop()),
    ];
  }
}

class _MappingRow extends StatelessWidget {
  final String label;
  final int value;
  final List<String> headers;
  final ValueChanged<int?> onChanged;
  const _MappingRow({required this.label, required this.value, required this.headers, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(width: 120, child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
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
