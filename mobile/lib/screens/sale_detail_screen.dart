import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';

/// Task 68-c — تفاصيل الفاتورة + الاسترجاع مطابقة لصفحة sales/[id] بالويب:
/// رأس INV-000012 أحادي LTR + وقت 12 ساعة ص/م، زر الاسترجاع مقيّد بصلاحية
/// sales.returns (كما Can perm في الويب)، ثلاث بطاقات الإجمالي/المسترجع/
/// الصافي دائمًا، جدول الأصناف بأعمدة الدفعة والمسترجع والمتاح مع
/// formatSoldQuantity (علبة/شريط حسب وحدة البيع) وتركييز التركيز بذكاء،
/// فواتير استرجاع RET-000012، ونافذة استرجاع بمفتاح idempotency ثابت
/// لجلسة الاسترجاع كلها (لا يُولَّد من جديد مع كل محاولة — تعثر الشبكة
/// لا يُنشئ إشعارًا دائنًا ثانيًا)، مع تقييد الكميات ورسالة return_exceeds.
class SaleDetailScreen extends StatefulWidget {
  final String saleId;
  const SaleDetailScreen({super.key, required this.saleId});

  @override
  State<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<SaleDetailScreen> {
  SaleDetail? _detail;
  bool _loading = true;
  String? _error;

  /// مفتاح idempotency واحد لسلسلة محاولات الاسترجاع: يُنشأ عند فتح
  /// النافذة، وتُعاد المحاولات بنفس المفتاح، ويُصفَّر بعد النجاح أو إلغاء
  /// الورقة فقط — نسخة موبايل من useRef(idempotencyKey) في الويب.
  String? _returnIdempotencyKey;

  static final RegExp _doseInName = RegExp(
      r'\d\s*(?:mg|µg|mcg|g|ml|iu|ملجم|ملغ|مل|جرام|وحدة)',
      caseSensitive: false);

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
      final d = await ApiClient.instance.getSale(widget.saleId);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.status == 404 ? i18n.t('sales', 'notFound') : AppI18n.instance.error(e.code, i18n.t('sales', 'detailLoadError'));
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

  // --------------------------------------------------------- مساعدات الويب

  String _pad6(int n) => n.toString().padLeft(6, '0');

  /// وقت 12 ساعة ص/م — مطابق لformatSaleTime (hour numeric, minute 2-digit)
  String _time12h(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '—';
    final ar = AppI18n.instance.locale == 'ar';
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final mm = d.minute.toString().padLeft(2, '0');
    final period = ar ? (d.hour < 12 ? 'ص' : 'م') : (d.hour < 12 ? 'am' : 'pm');
    return '$h:$mm $period';
  }

  /// نسخة extraStrengthLabel من lib/product.ts: لا يُلحق التركيز إن كان
  /// الاسم يحتويه أصلًا أو يحمل جرعة — منع «كاربيمازول 200mg 500mg».
  String _extraStrength(String name, String strength) {
    final clean = strength.trim();
    if (clean.isEmpty) return '';
    if (name.toLowerCase().contains(clean.toLowerCase())) return '';
    if (_doseInName.hasMatch(name)) return '';
    return clean;
  }

  /// baseUnitLabel — تسمية الوحدة الأساسية: شريط لBOX_STRIP وإلا وحدة
  String _baseUnitLabel(String packagingType) {
    final i18n = AppI18n.instance;
    return i18n.t('sales', packagingType == 'BOX_STRIP' ? 'unitStrip' : 'unitUnit');
  }

  /// formatBaseQuantity — عدد بالوحدة الأساسية بصيغة الجمع العربية
  String _baseQuantity(String packagingType, int quantity) {
    final i18n = AppI18n.instance;
    final isStrip = packagingType == 'BOX_STRIP';
    if (quantity == 1) return i18n.t('sales', isStrip ? 'oneStrip' : 'oneUnit');
    if (quantity == 2) return i18n.t('sales', isStrip ? 'twoStrips' : 'twoUnits');
    return i18n.t('sales', isStrip ? 'manyStrips' : 'manyUnits', {'count': Fmt.number(quantity)});
  }

  /// formatSoldQuantity — سطر البيع: سطور العلبة تُعرض بعدد العلب، وسطور
  /// الشريط بعدد الشرائط (لا «وحدة» إجمالية دائمًا كما كان سابقًا).
  String _soldQuantity(String saleUnit, String packagingType, int unitsPerBox, int quantityBase) {
    final i18n = AppI18n.instance;
    if (saleUnit == 'box') {
      if (quantityBase == 1) return i18n.t('sales', 'oneBox');
      if (quantityBase == 2) return i18n.t('sales', 'twoBoxes');
      return i18n.t('sales', 'manyBoxes', {'count': Fmt.number(quantityBase)});
    }
    return _baseQuantity(packagingType, quantityBase);
  }

  /// boxConversionHint — «العلبة = N شريط» لحقول الاسترجاع
  String? _boxHint(String packagingType, int unitsPerBox) {
    if (packagingType != 'BOX_STRIP' || unitsPerBox < 2) return null;
    return AppI18n.instance.t('sales', 'boxHint',
        {'count': Fmt.number(unitsPerBox), 'unit': _baseUnitLabel(packagingType)});
  }

  String _newIdempotencyKey() {
    final r = math.Random();
    String hex(int n) => List<String>.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-a${hex(3)}-${hex(12)}';
  }

  // ------------------------------------------------------------- الاسترجاع

  Future<void> _openReturn() async {
    final i18n = AppI18n.instance;
    final detail = _detail;
    if (detail == null) return;
    final rows = <SaleItemRow>[
      for (final SaleItemRow it in detail.items)
        if (it.returnableQuantityBase > 0) it,
    ];
    if (rows.isEmpty) return;

    // جلسة استرجاع: مفتاح واحد يُعاد استخدامه عبر كل محاولات هذه الورقة
    _returnIdempotencyKey ??= _newIdempotencyKey();

    final controllers = <String, TextEditingController>{
      for (final SaleItemRow it in rows) it.saleItemId: TextEditingController(text: ''),
    };
    final reasonCtrl = TextEditingController();
    var submitting = false;
    String? submitError;
    var retNumber = 0;
    var retAmount = 0;

    bool hasSelection() =>
        controllers.values.any((c) => (int.tryParse(c.text.trim()) ?? 0) > 0);

    void setQty(SaleItemRow it, String raw, void Function(void Function()) setSheet) {
      // تقييد عميلي 0..returnableQuantityBase كما في setQuantity بالويب
      final n = int.tryParse(raw.trim()) ?? 0;
      final clamped = n < 0 ? 0 : (n > it.returnableQuantityBase ? it.returnableQuantityBase : n);
      final canonical = clamped == 0 ? '' : '$clamped';
      final c = controllers[it.saleItemId]!;
      if (c.text != canonical) c.text = canonical;
      setSheet(() {});
    }

    Future<void> submit(void Function(void Function()) setSheet, BuildContext sheetCtx) async {
      if (submitting || !hasSelection()) return;
      final items = <Map<String, dynamic>>[
        for (final entry in controllers.entries)
          if ((int.tryParse(entry.value.text.trim()) ?? 0) > 0)
            <String, dynamic>{
              'sale_item_id': entry.key,
              'quantity': int.tryParse(entry.value.text.trim()) ?? 0,
            },
      ];
      if (items.isEmpty) return;
      setSheet(() {
        submitting = true;
        submitError = null;
      });
      try {
        final result = await ApiClient.instance.createSaleReturn(
          widget.saleId,
          items,
          reasonCtrl.text.trim(),
          _returnIdempotencyKey ?? _newIdempotencyKey(),
        );
        retNumber = result.returnNumber;
        retAmount = result.totalAmount;
        _returnIdempotencyKey = null; // النجاح ينهي الجلسة — لا مفتاح ثانٍ
        if (!mounted) return;
        Navigator.of(sheetCtx).pop(true);
      } on ApiException catch (e) {
        if (e.code == 'return_exceeds_sold') {
          // كالويب: رسالة returnExceeds + إعادة تحميل الفاتورة لتحديث المتاح
          setSheet(() {
            submitting = false;
            submitError = i18n.t('sales', 'returnExceeds');
          });
          await _load();
        } else {
          setSheet(() {
            submitting = false;
            submitError = AppI18n.instance.error(e.code, i18n.t('sales', 'returnSubmitError'));
          });
        }
      } catch (_) {
        setSheet(() {
          submitting = false;
          submitError = i18n.t('sales', 'returnSubmitError');
        });
      }
    }

    final saved = await appBottomSheet<bool>(
      context,
      title: i18n.t('sales', 'returnModalTitle'),
      child: StatefulBuilder(
        builder: (BuildContext sheetCtx, void Function(void Function()) setSheet) {
          final sheetTheme = Theme.of(sheetCtx);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(i18n.t('sales', 'returnModalHint'),
                  style: TextStyle(fontSize: 12, color: sheetTheme.colorScheme.onSurface.withOpacity(0.6))),
              const SizedBox(height: 12),
              // «تعبئة الكل» فقط عند أكثر من صنف قابل للاسترجاع (كالويب)
              if (rows.length > 1)
                WButton(i18n.t('sales', 'fillAllQuantities'),
                    variant: WButtonVariant.secondary,
                    size: WButtonSize.sm,
                    icon: Icons.done_all, onPressed: () {
                  for (final SaleItemRow it in rows) {
                    final c = controllers[it.saleItemId]!;
                    final v = '${it.returnableQuantityBase}';
                    if (c.text != v) c.text = v;
                  }
                  setSheet(() {});
                }),
              const SizedBox(height: 8),
              for (final SaleItemRow it in rows)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: sheetTheme.dividerColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: <Widget>[
                                    Flexible(
                                      child: Text(it.productName,
                                          maxLines: 2, overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                    ),
                                    if (_extraStrength(it.productName, it.strength).isNotEmpty) ...<Widget>[
                                      const SizedBox(width: 4),
                                      Text(_extraStrength(it.productName, it.strength),
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: sheetTheme.colorScheme.onSurface.withOpacity(0.55))),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${i18n.t('sales', 'sold', {'quantity': _soldQuantity(it.saleUnit, it.packagingType, it.unitsPerBox, it.quantityBase)})}'
                                  '${_boxHint(it.packagingType, it.unitsPerBox) != null ? ' · ${_boxHint(it.packagingType, it.unitsPerBox)}' : ''}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: sheetTheme.colorScheme.onSurface.withOpacity(0.55)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 72,
                            child: AppInput(
                              controller: controllers[it.saleItemId]!,
                              keyboard: TextInputType.number,
                              centered: true,
                              hint: '0',
                              onChanged: (v) => setQty(it, v, setSheet),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(_baseUnitLabel(it.packagingType),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: sheetTheme.colorScheme.onSurface.withOpacity(0.55))),
                          const SizedBox(width: 4),
                          WButton(i18n.t('sales', 'all'),
                              variant: WButtonVariant.ghost,
                              size: WButtonSize.sm, onPressed: () {
                            setQty(it, '${it.returnableQuantityBase}', setSheet);
                          }),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                          i18n.t('sales', 'availableLine', {
                            'quantity': Fmt.number(it.returnableQuantityBase),
                            'amount': Fmt.money(it.amountPiastres, locale: i18n.locale),
                          }),
                          style: TextStyle(
                              fontSize: 11,
                              color: sheetTheme.colorScheme.onSurface.withOpacity(0.5))),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Text(i18n.t('sales', 'returnReasonLabel'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              AppInput(
                controller: reasonCtrl,
                hint: i18n.t('sales', 'returnReasonPlaceholder'),
                maxLines: 2,
                maxLength: 500,
              ),
              if (submitError != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(submitError!,
                    style: TextStyle(fontSize: 13, color: sheetTheme.colorScheme.error)),
              ],
              const SizedBox(height: 12),
              PrimaryButton(
                i18n.t('sales', 'confirmReturn'),
                loading: submitting,
                onPressed: hasSelection() && !submitting ? () => submit(setSheet, sheetCtx) : null,
              ),
              const SizedBox(height: 6),
              SecondaryButton(i18n.t('sales', 'cancel'),
                  onPressed: submitting ? null : () => Navigator.of(sheetCtx).pop(false)),
            ],
          );
        },
      ),
    );

    for (final c in controllers.values) {
      c.dispose();
    }
    reasonCtrl.dispose();

    if (saved == true) {
      if (!mounted) return;
      await appSnackbar(context, i18n.t('sales', 'returnSuccess', {
        'number': _pad6(retNumber),
        'amount': Fmt.money(retAmount, locale: i18n.locale),
      }));
      _load();
    } else {
      // إلغاء الورقة (زر أو لمس الخارج) يُصفّر مفتاح الجلسة
      _returnIdempotencyKey = null;
    }
  }

  // ----------------------------------------------------------------- العرض

  Widget _statCard(String label, String value, {bool destructive = false}) {
    final theme = Theme.of(context);
    return Expanded(
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: destructive ? theme.colorScheme.error : null),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final d = _detail;
    final canReturn = context.read<AppState>().can('sales.returns'); // Can perm="sales.returns"
    final returnableCount = d == null
        ? 0
        : d.items.where((SaleItemRow it) => it.returnableQuantityBase > 0).length;
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('sales', 'title'))),
      body: _loading
          ? const LoadingBox()
          : _error != null || d == null
              ? ErrorRetry(_error ?? i18n.t('sales', 'notFound'), onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    // الرأس: INV-000012 + التاريخ · الوقت + الشارة + زر الاسترجاع المقيد
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text('INV-${_pad6(d.sale.invoiceNumber)}',
                                        textDirection: TextDirection.ltr,
                                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                                  ),
                                  AppBadge(
                                    d.sale.status == 'completed'
                                        ? i18n.t('sales', 'statusCompleted')
                                        : d.sale.status == 'partially_returned'
                                            ? i18n.t('sales', 'statusPartiallyReturned')
                                            : i18n.t('sales', 'statusReturned'),
                                    tone: AppBadge.saleStatus(d.sale.status),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                  '${Fmt.date(d.sale.createdAt, locale: i18n.locale)} · ${_time12h(d.sale.createdAt)}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurface.withOpacity(0.55))),
                              if (d.sale.customerName.isNotEmpty) ...<Widget>[
                                const SizedBox(height: 4),
                                Text(i18n.t('sales', 'creditBadgeWithCustomer', {'customer': d.sale.customerName}),
                                    style: const TextStyle(
                                        fontSize: 12, color: AppColors.warningFg, fontWeight: FontWeight.w600)),
                              ],
                            ],
                          ),
                        ),
                        if (canReturn && returnableCount > 0) ...<Widget>[
                          const SizedBox(width: 12),
                          PrimaryButton(i18n.t('sales', 'returnItems'),
                              icon: Icons.replay, onPressed: _openReturn),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    // بطاقات الإحصائيات الثلاث — دائمًا ظاهرة حتى عند الصفر (كالويب)
                    Row(
                      children: <Widget>[
                        _statCard(i18n.t('sales', 'totalInvoice'),
                            Fmt.money(d.sale.totalAmountPiastres, locale: i18n.locale)),
                        const SizedBox(width: 12),
                        _statCard(i18n.t('sales', 'totalReturned'),
                            Fmt.money(d.sale.returnedAmountPiastres, locale: i18n.locale),
                            destructive: d.sale.returnedAmountPiastres > 0),
                        const SizedBox(width: 12),
                        _statCard(
                            i18n.t('sales', 'netAfterReturn'),
                            Fmt.money(
                                d.sale.totalAmountPiastres - d.sale.returnedAmountPiastres,
                                locale: i18n.locale)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SectionHeader(i18n.t('sales', 'invoiceItems')),
                    AppCard(
                      padding: const EdgeInsets.all(12),
                      child: WebTable(
                        minWidth: 860,
                        headers: <String>[
                          i18n.t('sales', 'colProduct'),
                          i18n.t('sales', 'colBatch'),
                          i18n.t('sales', 'colQuantitySold'),
                          i18n.t('sales', 'colUnitPrice'),
                          i18n.t('sales', 'colTotal'),
                          i18n.t('sales', 'colReturned'),
                          i18n.t('sales', 'colReturnable'),
                        ],
                        rows: <List<Widget>>[
                          for (final SaleItemRow it in d.items)
                            <Widget>[
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: <Widget>[
                                      Flexible(
                                        child: Text(it.productName,
                                            maxLines: 2, overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                      ),
                                      if (_extraStrength(it.productName, it.strength).isNotEmpty) ...<Widget>[
                                        const SizedBox(width: 4),
                                        Text(_extraStrength(it.productName, it.strength),
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: theme.colorScheme.onSurface.withOpacity(0.55))),
                                      ],
                                    ],
                                  ),
                                  if (it.genericName.isNotEmpty)
                                    Text(it.genericName,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: theme.colorScheme.onSurface.withOpacity(0.55))),
                                ],
                              ),
                              Text(it.batchNumber.isEmpty ? '—' : it.batchNumber,
                                  textDirection: it.batchNumber.isEmpty ? null : TextDirection.ltr,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurface.withOpacity(0.7))),
                              Text(
                                  _soldQuantity(it.saleUnit, it.packagingType, it.unitsPerBox, it.quantityBase),
                                  style: const TextStyle(fontSize: 13)),
                              Text(Fmt.money(it.unitPricePiastres, locale: i18n.locale),
                                  style: const TextStyle(fontSize: 13)),
                              Text(Fmt.money(it.amountPiastres, locale: i18n.locale),
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              Text(
                                it.returnedQuantityBase > 0
                                    ? _soldQuantity(it.saleUnit, it.packagingType, it.unitsPerBox,
                                        it.returnedQuantityBase)
                                    : '—',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight:
                                        it.returnedQuantityBase > 0 ? FontWeight.w500 : FontWeight.w400,
                                    color: it.returnedQuantityBase > 0
                                        ? theme.colorScheme.error
                                        : theme.colorScheme.onSurface.withOpacity(0.5)),
                              ),
                              Text(
                                it.returnableQuantityBase > 0
                                    ? _soldQuantity(it.saleUnit, it.packagingType, it.unitsPerBox,
                                        it.returnableQuantityBase)
                                    : i18n.t('sales', 'none'),
                                style: TextStyle(
                                    fontSize: it.returnableQuantityBase > 0 ? 13 : 12,
                                    color: it.returnableQuantityBase > 0
                                        ? null
                                        : theme.colorScheme.onSurface.withOpacity(0.5)),
                              ),
                            ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (d.sale.returns.isNotEmpty) ...<Widget>[
                      SectionHeader(i18n.t('sales', 'returnsTitle', {'count': Fmt.number(d.sale.returns.length)})),
                      for (final SaleReturnSummary r in d.sale.returns)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: theme.colorScheme.error.withOpacity(0.30)),
                            color: theme.colorScheme.error.withOpacity(0.05),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Icon(Icons.replay, size: 16, color: theme.colorScheme.error),
                                  const SizedBox(width: 8),
                                  Text('RET-${_pad6(r.returnNumber)}',
                                      textDirection: TextDirection.ltr,
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: theme.colorScheme.error)),
                                  const Spacer(),
                                  Text('-${Fmt.money(r.totalAmountPiastres, locale: i18n.locale)}',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: theme.colorScheme.error)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${Fmt.date(r.createdAt, locale: i18n.locale)} · ${_time12h(r.createdAt)}'
                                '${r.quantityBase > 0 ? ' · ${i18n.t('sales', 'returnedUnits', {'count': Fmt.number(r.quantityBase)})}' : ''}',
                                style: TextStyle(
                                    fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55)),
                              ),
                              if (r.reason.isNotEmpty) ...<Widget>[
                                const SizedBox(height: 2),
                                Text(i18n.t('sales', 'reason', {'reason': r.reason}),
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.onSurface.withOpacity(0.55))),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
    );
  }
}
