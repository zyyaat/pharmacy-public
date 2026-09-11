import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../print/receipt_printer.dart';
import '../print/receipt_template.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';

/// الفواتير والطباعة — مطابق لصفحة الويب (settings/receipts/page.tsx):
/// بادئة الاسم برقائق سريعة، مقاس الورق، وضع الطباعة ببطاقتَي وصف، محتوى
/// الإيصال بعدّادات أحرف، ومعاينة حية بالقالب الحراري الحقيقي تتحدث لحظيًا —
/// مع حفظ مقيّد بالتعديل (dirty) وزر طباعة اختبارية وزر تراجع عن التعديلات.
class ReceiptsSettingsScreen extends StatefulWidget {
  const ReceiptsSettingsScreen({super.key});
  @override
  State<ReceiptsSettingsScreen> createState() => _ReceiptsSettingsScreenState();
}

class _ReceiptsSettingsScreenState extends State<ReceiptsSettingsScreen> {
  /// آخر إعدادات محمّلة من الخادم — مرجع كشف التعديل (كـ settings بالويب)
  ReceiptSettings? _saved;

  /// المسودة الحالية (كـ draft بالويب) — حقول البنية فقط، والنصوص في المتحكمات
  ReceiptSettings? _s;
  late TextEditingController _prefix;
  late TextEditingController _thankYou;
  late TextEditingController _returnPolicy;

  /// RepaintBoundary المعاينة الحية — يُلتقط للطباعة الاختبارية
  final GlobalKey _previewKey = GlobalKey();

  bool _loading = true;
  bool _saving = false;
  bool _printing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _s = null;
    _saved = null;
    _prefix = TextEditingController();
    _thankYou = TextEditingController();
    _returnPolicy = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _prefix.dispose();
    _thankYou.dispose();
    _returnPolicy.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final i18n = AppI18n.instance;
    try {
      final s = await ApiClient.instance.getSettings();
      if (!mounted) return;
      setState(() {
        _saved = s;
        _s = s;
        _prefix.text = s.namePrefix;
        _thankYou.text = s.thankYouText;
        _returnPolicy.text = s.returnPolicyText;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('settings', 'saveErrorFallback'));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = i18n.t('settings', 'saveErrorFallback');
        _loading = false;
      });
    }
  }

  // ------------------------------------------------------------ حالة التعديل

  /// dirty — كالويب: المسودة تختلف عن الإعدادات المحفوظة (النصوص تُقارن
  /// بعد التقليم لأن الحفظ يقلمها فيصير المقارنة هي «ما سيّتغير فعلًا»)
  bool get _isDirty {
    final ReceiptSettings? saved = _saved;
    final ReceiptSettings? s = _s;
    if (saved == null || s == null) return false;
    return saved.paperWidthMm != s.paperWidthMm ||
        saved.printMode != s.printMode ||
        saved.copies != s.copies ||
        _prefix.text.trim() != saved.namePrefix.trim() ||
        _thankYou.text.trim() != saved.thankYouText.trim() ||
        _returnPolicy.text.trim() != saved.returnPolicyText.trim() ||
        saved.showPhone != s.showPhone ||
        saved.showAddress != s.showAddress ||
        saved.showCashier != s.showCashier ||
        saved.showThankYou != s.showThankYou ||
        saved.showReturnPolicy != s.showReturnPolicy;
  }

  /// الإعدادات الفعلية للمسودة (بنية + نصوص المتحكمات) — تُغذّي المعاينة
  /// الحية والطباعة الاختبارية قبل الحفظ
  ReceiptSettings get _effective {
    final ReceiptSettings s = _s!;
    return ReceiptSettings(
      paperWidthMm: s.paperWidthMm,
      printMode: s.printMode,
      copies: s.copies,
      namePrefix: _prefix.text,
      thankYouText: _thankYou.text,
      returnPolicyText: _returnPolicy.text,
      showPhone: s.showPhone,
      showAddress: s.showAddress,
      showCashier: s.showCashier,
      showThankYou: s.showThankYou,
      showReturnPolicy: s.showReturnPolicy,
    );
  }

  ReceiptSettings _clone(ReceiptSettings s) => ReceiptSettings(
        paperWidthMm: s.paperWidthMm,
        printMode: s.printMode,
        copies: s.copies,
        namePrefix: s.namePrefix,
        thankYouText: s.thankYouText,
        returnPolicyText: s.returnPolicyText,
        showPhone: s.showPhone,
        showAddress: s.showAddress,
        showCashier: s.showCashier,
        showThankYou: s.showThankYou,
        showReturnPolicy: s.showReturnPolicy,
      );

  ReceiptSettings _copy(
    ReceiptSettings s, {
    int? paperWidthMm,
    String? printMode,
    int? copies,
    bool? showPhone,
    bool? showAddress,
    bool? showCashier,
    bool? showThankYou,
    bool? showReturnPolicy,
  }) =>
      ReceiptSettings(
        paperWidthMm: paperWidthMm ?? s.paperWidthMm,
        printMode: printMode ?? s.printMode,
        copies: copies ?? s.copies,
        namePrefix: s.namePrefix,
        thankYouText: s.thankYouText,
        returnPolicyText: s.returnPolicyText,
        showPhone: showPhone ?? s.showPhone,
        showAddress: showAddress ?? s.showAddress,
        showCashier: showCashier ?? s.showCashier,
        showThankYou: showThankYou ?? s.showThankYou,
        showReturnPolicy: showReturnPolicy ?? s.showReturnPolicy,
      );

  // ---------------------------------------------------------------- الأفعال

  Future<void> _save() async {
    final i18n = AppI18n.instance;
    final ReceiptSettings? s = _s;
    if (s == null || _saving || !_isDirty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await ApiClient.instance.updateSettings(<String, dynamic>{
        'paper_width_mm': s.paperWidthMm,
        'print_mode': s.printMode,
        'copies': s.copies,
        'name_prefix': _prefix.text.trim(),
        'show_phone': s.showPhone,
        'show_address': s.showAddress,
        'show_cashier': s.showCashier,
        'show_thank_you': s.showThankYou,
        'thank_you_text': _thankYou.text.trim(),
        'show_return_policy': s.showReturnPolicy,
        'return_policy_text': _returnPolicy.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        _saved = updated;
        _s = updated;
        // كالويب setDraft(null): الحقول تعود لقيم المحفوظ (الخادم يقلّم)
        _prefix.text = updated.namePrefix;
        _thankYou.text = updated.thankYouText;
        _returnPolicy.text = updated.returnPolicyText;
        _saving = false;
      });
      await appSnackbar(context, i18n.t('settings', 'savedFlash'));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('settings', 'saveErrorFallback'));
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = i18n.t('settings', 'saveErrorFallback');
        _saving = false;
      });
    }
  }

  /// تراجع عن التعديلات — استعادة لقطة المحفوظ (كالويب setDraft(null))
  void _discard() {
    final ReceiptSettings? saved = _saved;
    if (saved == null || !_isDirty) return;
    setState(() {
      _s = _clone(saved);
      _prefix.text = saved.namePrefix;
      _thankYou.text = saved.thankYouText;
      _returnPolicy.text = saved.returnPolicyText;
      _error = null;
    });
  }

  /// طباعة اختبارية — تلتقط معاينة العينة الحية (بمسودة الإعدادات الحالية)
  /// وتمررها لمنتقي الطباعة في أندرويد، كزر «طباعة اختبار» بالويب
  Future<void> _testPrint() async {
    final i18n = AppI18n.instance;
    if (_printing || _saving || _s == null) return;
    setState(() => _printing = true);
    try {
      // انتظار نضوج إطار المعاينة بعد آخر تعديل قبل الالتقاط (كشاشة الإيصال)
      await WidgetsBinding.instance.endOfFrame;
      final ReceiptPrintResult result = await printReceiptBoundaries(
        boundaryKeys: <GlobalKey>[_previewKey],
        paperWidthMm: _s!.paperWidthMm.toDouble(),
        jobName: 'receipt-test',
      );
      if (!mounted) return;
      if (!result.ok) {
        await appSnackbar(context, i18n.t('pos', 'printPrepareFailed'), error: true);
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  // --------------------------------------------------------- مساعدات القيم

  /// قص النص بعدد نقاط الترميز (نظير [...value].length بالويب)
  static String _clampRunes(String v, int max) {
    if (v.runes.length <= max) return v;
    return String.fromCharCodes(v.runes.take(max));
  }

  void _onFieldChanged(TextEditingController c, String v, int max) {
    final String clamped = _clampRunes(v, max);
    if (clamped != v) {
      c.value = TextEditingValue(
          text: clamped, selection: TextSelection.collapsed(offset: clamped.length));
    }
    setState(() {}); // المعاينة الحية + كشف التعديل + العدّاد
  }

  static String _nonEmpty(String? v) => (v ?? '').trim();

  /// pharmacy — usePharmacyContext بالويب مع بدائل العينة عند غياب السياق
  ReceiptPharmacy _samplePharmacy(AppState state, AppI18n i18n) => ReceiptPharmacy(
        name: _nonEmpty(state.context?.pharmacyName).isNotEmpty
            ? _nonEmpty(state.context?.pharmacyName)
            : i18n.t('settings', 'defaultPharmacyName'),
        city: _nonEmpty(state.context?.city).isNotEmpty
            ? _nonEmpty(state.context?.city)
            : i18n.t('settings', 'defaultCity'),
        address: _nonEmpty(state.context?.address).isNotEmpty
            ? _nonEmpty(state.context?.address)
            : i18n.t('settings', 'defaultAddress'),
        phone: _nonEmpty(state.context?.phone).isNotEmpty
            ? _nonEmpty(state.context?.phone)
            : '01000000000',
      );

  /// cashierName — page.tsx:310: display_name أو الأول+الأخير أو الافتراضي
  String _cashierName(AppState state, AppI18n i18n) {
    final User? user = state.context?.user ?? state.user;
    if (user != null) {
      final String display = user.displayName.trim();
      if (display.isNotEmpty) return display;
      final String joined = <String>[user.firstName.trim(), user.lastName.trim()]
          .where((String part) => part.isNotEmpty)
          .join(' ');
      if (joined.isNotEmpty) return joined;
    }
    return i18n.t('settings', 'defaultCashierName');
  }

  // بيانات فاتورة تجريبية — sampleReceipt بالويب (بانادول علبة، كاربيمازول شريط،
  // كونجستال علبة) مع مثال خصم وفاتورة آجل بعميل ليُظهر القالب كل فروعه
  SaleSummary get _sampleSale => SaleSummary(
        id: 'sample',
        invoiceNumber: 1024,
        status: 'completed',
        totalAmountPiastres: 14050, // الصافي بعد الخصم (كالويب: الإجمالي هو الصافي دائمًا)
        discountAmountPiastres: 500,
        paymentType: 'credit',
        customerName: 'محمد سعيد', // بيانات عينة فقط — ليست ترجمة
        createdAt: '2026-09-09T14:30:00Z',
        productsCount: 3,
        totalQuantityBase: 91,
        returnedAmountPiastres: 0,
        returns: const <SaleReturnSummary>[],
      );

  List<SaleItemRow> get _sampleItems {
    final AppI18n i18n = AppI18n.instance;
    return <SaleItemRow>[
      SaleItemRow(
        saleItemId: '',
        productId: '',
        productName: i18n.t('settings', 'sampleProductPanadol'),
        genericName: '',
        strength: '500mg',
        barcode: '',
        packagingType: 'WHOLE_ONLY',
        saleUnit: 'box',
        batchNumber: '',
        unitsPerBox: 24,
        quantityBase: 48, // ← تُعرض «علبتان» بمعادلة العلبة الصحيحة
        unitPricePiastres: 3600,
        amountPiastres: 7200,
        returnedQuantityBase: 0,
        returnableQuantityBase: 0,
        returnedAmountPiastres: 0,
      ),
      SaleItemRow(
        saleItemId: '',
        productId: '',
        productName: i18n.t('settings', 'sampleProductCarbimazole'),
        genericName: '',
        strength: '',
        barcode: '',
        packagingType: 'WHOLE_ONLY',
        saleUnit: 'strip',
        batchNumber: '',
        unitsPerBox: 10,
        quantityBase: 3,
        unitPricePiastres: 750,
        amountPiastres: 2250,
        returnedQuantityBase: 0,
        returnableQuantityBase: 0,
        returnedAmountPiastres: 0,
      ),
      SaleItemRow(
        saleItemId: '',
        productId: '',
        productName: i18n.t('settings', 'sampleProductCongestal'),
        genericName: '',
        strength: '500mg',
        barcode: '',
        packagingType: 'WHOLE_ONLY',
        saleUnit: 'box',
        batchNumber: '',
        unitsPerBox: 20,
        quantityBase: 40,
        unitPricePiastres: 2550,
        amountPiastres: 5100,
        returnedQuantityBase: 0,
        returnableQuantityBase: 0,
        returnedAmountPiastres: 0,
      ),
    ];
  }

  // ----------------------------------------------------------------- البناء

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final ReceiptSettings? s = _s;
    final AppState state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('settings', 'receiptsTitle'))),
      body: _loading
          ? const LoadingBox()
          : _error != null && _s == null
              ? ErrorRetry(_error!, onRetry: _load)
              : s == null
                  ? const SizedBox.shrink()
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: <Widget>[
                        Text(i18n.t('settings', 'receiptsSubtitle'),
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                        const SizedBox(height: 14),

                        // اسم الصيدلية — رقائق البادئة السريعة + حقل مخصص + العرض
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              CardTitle(i18n.t('settings', 'pharmacyNameTitle'), subtitle: i18n.t('settings', 'pharmacyNameDesc')),
                              const SizedBox(height: 10),
                              _buildPrefixChips(i18n),
                              const SizedBox(height: 8),
                              _CountedField(
                                controller: _prefix,
                                hint: i18n.t('settings', 'customPrefixPlaceholder'),
                                maxLength: 40,
                                onChanged: (String v) => _onFieldChanged(_prefix, v, 40),
                              ),
                              const SizedBox(height: 8),
                              _buildShowsOnReceipt(theme, state, i18n),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // مقاس الورقة
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              CardTitle(i18n.t('settings', 'paperSizeTitle'), subtitle: i18n.t('settings', 'paperSizeDesc')),
                              const SizedBox(height: 10),
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: _PaperChoice(
                                      title: i18n.t('settings', 'mmSuffix', {'width': '80'}),
                                      desc: i18n.t('settings', 'paper80Desc'),
                                      selected: s.paperWidthMm == 80,
                                      onTap: () => setState(() => _s = _copy(s, paperWidthMm: 80)),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _PaperChoice(
                                      title: i18n.t('settings', 'mmSuffix', {'width': '58'}),
                                      desc: i18n.t('settings', 'paper58Desc'),
                                      selected: s.paperWidthMm == 58,
                                      onTap: () => setState(() => _s = _copy(s, paperWidthMm: 58)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // وضع الطباعة — بطاقتا وصف بدل القائمة المنسدلة (كالويب)
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              CardTitle(i18n.t('settings', 'printModeTitle'), subtitle: i18n.t('settings', 'printModeDesc')),
                              const SizedBox(height: 10),
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: _PaperChoice(
                                      title: i18n.t('settings', 'printModeAuto'),
                                      desc: i18n.t('settings', 'printModeAutoDesc'),
                                      selected: s.printMode == 'auto',
                                      onTap: () => setState(() => _s = _copy(s, printMode: 'auto')),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _PaperChoice(
                                      title: i18n.t('settings', 'printModeManual'),
                                      desc: i18n.t('settings', 'printModeManualDesc'),
                                      selected: s.printMode == 'manual',
                                      onTap: () => setState(() => _s = _copy(s, printMode: 'manual')),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // محتوى الإيصال — بعدّادات أحرف على الحقول النصية
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              CardTitle(i18n.t('settings', 'contentTitle'), subtitle: i18n.t('settings', 'contentDesc')),
                              const SizedBox(height: 8),
                              AppSwitchTile(
                                title: i18n.t('settings', 'copiesLabel'),
                                subtitle: i18n.t('settings', 'copiesDesc'),
                                value: s.copies == 2,
                                onChanged: (bool v) => setState(() => _s = _copy(s, copies: v ? 2 : 1)),
                              ),
                              AppSwitchTile(title: i18n.t('settings', 'showPhone'), value: s.showPhone, onChanged: (bool v) => setState(() => _s = _copy(s, showPhone: v))),
                              AppSwitchTile(title: i18n.t('settings', 'showAddress'), value: s.showAddress, onChanged: (bool v) => setState(() => _s = _copy(s, showAddress: v))),
                              AppSwitchTile(title: i18n.t('settings', 'showCashier'), value: s.showCashier, onChanged: (bool v) => setState(() => _s = _copy(s, showCashier: v))),
                              AppSwitchTile(title: i18n.t('settings', 'showThankYou'), value: s.showThankYou, onChanged: (bool v) => setState(() => _s = _copy(s, showThankYou: v))),
                              if (s.showThankYou)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: _CountedField(
                                    controller: _thankYou,
                                    hint: i18n.t('settings', 'thankYouPlaceholder'),
                                    maxLength: 120,
                                    onChanged: (String v) => _onFieldChanged(_thankYou, v, 120),
                                  ),
                                ),
                              AppSwitchTile(title: i18n.t('settings', 'showReturnPolicy'), value: s.showReturnPolicy, onChanged: (bool v) => setState(() => _s = _copy(s, showReturnPolicy: v))),
                              if (s.showReturnPolicy)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: _CountedField(
                                    controller: _returnPolicy,
                                    hint: i18n.t('settings', 'returnPolicyPlaceholder'),
                                    maxLength: 160,
                                    onChanged: (String v) => _onFieldChanged(_returnPolicy, v, 160),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // المعاينة الحية — القالب الحراري الحقيقي بمسودة الإعدادات
                        _buildPreviewCard(theme, state, i18n),
                        const SizedBox(height: 16),

                        // الأفعال — حفظ مقيّد بالتعديل + طباعة اختبارية + تراجع
                        PrimaryButton(
                          i18n.t('settings', 'saveSettings'),
                          loading: _saving,
                          onPressed: _isDirty ? _save : null,
                        ),
                        const SizedBox(height: 8),
                        SecondaryButton(
                          i18n.t('settings', 'testPrint'),
                          icon: Icons.print,
                          onPressed: _printing || _saving ? null : _testPrint,
                        ),
                        if (_isDirty) ...<Widget>[
                          const SizedBox(height: 8),
                          GhostButton(
                            i18n.t('settings', 'discardChanges'),
                            icon: Icons.restart_alt,
                            onPressed: _discard,
                          ),
                        ],
                        if (_error != null) ...<Widget>[
                          const SizedBox(height: 10),
                          Text(_error!, style: TextStyle(fontSize: 12, color: theme.colorScheme.error), textAlign: TextAlign.center),
                        ],
                        if (!_isDirty) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(
                            i18n.t('settings', 'livePreviewHint'),
                            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.45)),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
    );
  }

  // --------------------------------------------------------- رقائق البادئة

  /// رقائق البادئات الجاهزة — namePrefixValues بالويب ('' = بدون بادئة)
  Widget _buildPrefixChips(AppI18n i18n) {
    final List<String> values = <String>[
      '',
      i18n.t('settings', 'prefixPharmacy'),
      i18n.t('settings', 'prefixDrAbbrev'),
      i18n.t('settings', 'prefixDoctor'),
      i18n.t('settings', 'prefixPharmacies'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final String value in values)
          _PrefixChip(
            label: value.isEmpty ? i18n.t('settings', 'noPrefix') : value,
            active: _prefix.text == value,
            onTap: () => setState(() => _prefix.text = value),
          ),
      ],
    );
  }

  /// «يظهر على الفاتورة: {الاسم المركب}» — composePharmacyDisplayName بالويب
  Widget _buildShowsOnReceipt(ThemeData theme, AppState state, AppI18n i18n) {
    final String pharmacyName = _samplePharmacy(state, i18n).name;
    final String composed = composePharmacyDisplayName(_prefix.text, pharmacyName);
    final String display = composed.isNotEmpty
        ? composed
        : (pharmacyName.isNotEmpty ? pharmacyName : i18n.t('settings', 'fallbackPharmacyWord'));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withOpacity(0.04),
        borderRadius: AppRadius.br,
      ),
      child: Text.rich(
        TextSpan(
          text: '${i18n.t('settings', 'showsOnReceipt')} ',
          children: <InlineSpan>[
            TextSpan(text: display, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.75)),
      ),
    );
  }

  // ------------------------------------------------------- المعاينة الحية

  Widget _buildPreviewCard(ThemeData theme, AppState state, AppI18n i18n) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CardTitle(
            i18n.t('settings', 'previewTitle'),
            subtitle: i18n.t('settings', 'previewDesc', {'width': _s!.paperWidthMm}),
            icon: Icons.receipt_long,
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withOpacity(0.05),
              borderRadius: AppRadius.br,
            ),
            child: Center(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.25)),
                  boxShadow: WebShadow.sm,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  // الحد داخل الإطار الزخرفي: الالتقاط = إيصال صافٍ بلا حدود الشاشة
                  // (نفس تركيب شاشة الإيصال) — FittedBox يصغّر العرض على الشاشات
                  // الضيقة للعرض فقط ولا يؤثر في الالتقاط (طبقة الحد مستقلة)
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: RepaintBoundary(
                      key: _previewKey,
                      child: ReceiptTemplate(
                        sale: _sampleSale,
                        items: _sampleItems,
                        pharmacy: _samplePharmacy(state, i18n),
                        cashierName: _cashierName(state, i18n),
                        settings: _effective,
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
}

// ------------------------------------------------------------- عناصر محلية

/// رقاقة بادئة واحدة — rounded-full بالويب: حدّ بلون الهوية عند التفعيل
class _PrefixChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _PrefixChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? theme.colorScheme.primary.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? theme.colorScheme.primary : theme.dividerColor,
            width: active ? 1.4 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      ),
    );
  }
}

/// بطاقة اختيار (مقاس الورق / وضع الطباعة) — وصف + مؤشر صح على البطاقة النشطة
class _PaperChoice extends StatelessWidget {
  final String title;
  final String desc;
  final bool selected;
  final VoidCallback onTap;
  const _PaperChoice({required this.title, required this.desc, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: AppRadius.br,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary.withOpacity(0.08) : Colors.transparent,
          borderRadius: AppRadius.br,
          border: Border.all(color: selected ? theme.colorScheme.primary : theme.dividerColor, width: selected ? 1.4 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: selected ? theme.colorScheme.primary : null)),
                ),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: selected ? 1 : 0,
                  child: Icon(Icons.check_circle, size: 16, color: theme.colorScheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(desc, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.55))),
          ],
        ),
      ),
    );
  }
}

/// حقل نصي بعدّاد أحرف — كحقل الويب: حدّ الإدخال بالنقاط + «n/max» أسفله LTR
class _CountedField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLength;
  final ValueChanged<String> onChanged;
  const _CountedField({
    required this.controller,
    required this.hint,
    required this.maxLength,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AppInput(controller: controller, hint: hint, onChanged: onChanged),
        const SizedBox(height: 4),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${controller.text.runes.length}/$maxLength',
              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.45)),
            ),
          ),
        ),
      ],
    );
  }
}
