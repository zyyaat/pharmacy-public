import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/strings.dart';
import '../models/models.dart';
import '../print/receipt_printer.dart';
import '../print/receipt_template.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';

/// شاشة الإيصال — نظير تدفق الطباعة في نقطة البيع بالويب (page.tsx:287-318 +
/// receipt-printer.tsx): معاينة القالب الحراري الحرفي وطباعة حقيقية عبر نظام
/// الطباعة في أندرويد (نظير window.print). كل نسخة معاينة داخل RepaintBoundary
/// بمفتاح مستقل فتصير صفحة مستقلة في PDF الورق (58/80مم من الإعدادات).
///
/// الطباعة التلقائية: نقطة البيع تمرر autoPrint = (printMode == 'auto') فتشتعل
/// الطباعة مرة واحدة بعد أول إطار — بحارس يمنع الإطلاق المزدوج عند إعادة البناء
/// (نظير printedJob.current === job.jobId في الويب).
class ReceiptScreen extends StatefulWidget {
  final String saleId;

  /// طباعة تلقائية مرة واحدة بعد جاهزية البيانات (وضع «طباعة تلقائية» بالإعدادات)
  final bool autoPrint;

  const ReceiptScreen({super.key, required this.saleId, this.autoPrint = false});

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  SaleDetail? _detail;
  ReceiptSettings? _settings;
  bool _loading = true;
  bool _printing = false;
  bool _autoPrintFired = false;
  String? _error;

  /// مفتاح لكل نسخة إيصال — يُملأ حسب settings.copies لحظة البناء
  final List<GlobalKey> _boundaryKeys = <GlobalKey>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ReceiptScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoPrint && !oldWidget.autoPrint) _maybeAutoPrint();
  }

  Future<void> _load() async {
    final i18n = AppI18n.instance;
    try {
      final detail = await ApiClient.instance.getSale(widget.saleId);
      // نفس افتراضيات الواجهة بالويب (useReceiptSettings.ts defaultReceiptSettings):
      // 80مم، طباعة تلقائية، نسخة واحدة، كل المفاتيح مفعّلة والنصان الافتراضيان
      // من كتالوج pos — تُستخدم فقط إذا فشل جلب الإعدادات.
      ReceiptSettings settings = ReceiptSettings(
        paperWidthMm: 80,
        printMode: 'auto',
        copies: 1,
        namePrefix: '',
        thankYouText: i18n.t('pos', 'defaultThankYou'),
        returnPolicyText: i18n.t('pos', 'defaultReturnPolicy'),
        showPhone: true,
        showAddress: true,
        showCashier: true,
        showThankYou: true,
        showReturnPolicy: true,
      );
      try {
        settings = await ApiClient.instance.getSettings();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _settings = settings;
        _loading = false;
      });
      _maybeAutoPrint();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('sales', 'detailLoadError'));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.t('sales', 'detailLoadError');
        _loading = false;
      });
    }
  }

  int get _copies {
    final ReceiptSettings? s = _settings;
    if (s == null) return 1;
    return s.copies == 2 ? 2 : 1;
  }

  /// الطباعة التلقائية: مرة واحدة فقط بعد اكتمال البيانات وأول إطار مرسوم
  void _maybeAutoPrint() {
    if (!widget.autoPrint || _autoPrintFired) return;
    if (_loading || _detail == null || _settings == null) return;
    _autoPrintFired = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _print();
    });
  }

  /// تجهيز الإيصال وفتح منتقي الطباعة — نفس دور prepareReceiptPrint + window.print
  Future<void> _print() async {
    final i18n = AppI18n.instance;
    final SaleDetail? detail = _detail;
    final ReceiptSettings? settings = _settings;
    if (_printing || _loading || detail == null || settings == null) return;
    setState(() => _printing = true);
    try {
      // انتظار طلاء الإطار الحالي قبل الالتقاط حتى تكون الحدود ناضجة (كالويب: setTimeout 80ms)
      await WidgetsBinding.instance.endOfFrame;
      final ReceiptPrintResult result = await printReceiptBoundaries(
        boundaryKeys: List<GlobalKey>.of(_boundaryKeys),
        paperWidthMm: settings.paperWidthMm.toDouble(),
        jobName: 'receipt-INV-${detail.sale.invoiceNumber.toString().padLeft(6, '0')}',
      );
      if (!mounted) return;
      if (!result.ok) {
        await appSnackbar(context, i18n.t('pos', 'printPrepareFailed'), error: true);
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  /// cashierName — page.tsx:310: display_name أو «الاسم الأول + الأخير»
  String _cashierName(User? user) {
    if (user == null) return '';
    final String display = user.displayName.trim();
    if (display.isNotEmpty) return display;
    return <String>[user.firstName.trim(), user.lastName.trim()]
        .where((String part) => part.isNotEmpty)
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final AppState state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('pos', 'invoiceNo'))),
      body: _loading
          ? const LoadingBox()
          : _error != null
              ? ErrorRetry(_error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: _buildPreview(theme, state),
                ),
    );
  }

  List<Widget> _buildPreview(ThemeData theme, AppState state) {
    final i18n = AppI18n.instance;
    final SaleDetail detail = _detail!;
    final ReceiptSettings settings = _settings!;
    final int copies = _copies;

    // مفتاح RepaintBoundary لكل نسخة — ثابت عبر إعادة البناء ليعمل الالتقاط لاحقًا
    while (_boundaryKeys.length < copies) {
      _boundaryKeys.add(GlobalKey());
    }
    if (_boundaryKeys.length > copies) {
      _boundaryKeys.removeRange(copies, _boundaryKeys.length);
    }

    // بيانات رأس الإيصال من سياق الصيدلية المحمّل في AppState (كـ usePharmacyContext بالويب)
    final ReceiptPharmacy pharmacy = ReceiptPharmacy(
      name: state.context?.pharmacyName ?? '',
      city: state.context?.city ?? '',
      address: state.context?.address ?? '',
      phone: state.context?.phone ?? '',
    );
    final String cashierName = _cashierName(state.user);

    Widget copy(int index, {required bool showCopyLabel, String? copyLabel}) {
      return Center(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.25)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            // الحد داخل الإطار الزخرفي: الالتقاط = الإيصال الصافي بلا حدود الشاشة
            child: RepaintBoundary(
              key: _boundaryKeys[index],
              child: ReceiptTemplate(
                sale: detail.sale,
                items: detail.items,
                pharmacy: pharmacy,
                cashierName: cashierName,
                settings: settings,
                showCopyLabel: showCopyLabel,
                copyLabel: copyLabel,
              ),
            ),
          ),
        ),
      );
    }

    return <Widget>[
      copy(0, showCopyLabel: false),
      if (copies == 2) ...<Widget>[
        const SizedBox(height: 10),
        const ReceiptCutSeparator(),
        const SizedBox(height: 10),
        copy(1, showCopyLabel: true, copyLabel: i18n.t('pos', 'copyPharmacy')),
      ],
      const SizedBox(height: 16),
      PrimaryButton(
        i18n.t('pos', 'printInvoice'),
        icon: Icons.print,
        loading: _printing,
        onPressed: _print,
      ),
      const SizedBox(height: 8),
      SecondaryButton(
        i18n.t('common', 'back'),
        icon: Icons.arrow_back,
        onPressed: () => Navigator.of(context).pop(),
      ),
    ];
  }
}
