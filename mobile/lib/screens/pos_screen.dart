import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../state/app_state.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/ui.dart';
import 'receipt_screen.dart';

/// Task 62 + 68-i — نقطة البيع بنسخة الويب حرفيًا: بطاقة إضافة الأصناف
/// (بحث ذكي مؤجّل 180ms بحارس تسلسل، باركود ≥6 أرقام بمسار الماسح وتصحيح
/// تلقائي 0.72، اقتراحات بشارة نوع المطابقة وبرز اسم علمي وتمييز الجزء
/// المطابق وبطاقة لا نتائج)، بطاقة السلة (شرائط فواتير معلّقة **مخزّنة** في
/// flutter_secure_storage بتسمية محسوبة وقت الإيقاف، وحدة بيع تحفظ عدد
/// الشرائط المختار، خصم افتراضي مبلغ لا نسبة)، ومفتاح idempotency واحد
/// لسلسلة محاولات الفاتورة كاملة (يُصكَّ عند أول محاولة ويُصفَّر بعد النجاح
/// أو الإيقاف أو الاستئناف أو التفريغ) — فتعذر الشبكة لا يمكن أن يبيع مرتين.
/// الأسعار المرجعية من الخادم دائمًا (409 price_changed يعرض رسالة الخادم).
class POSScreen extends StatefulWidget {
  const POSScreen({super.key});

  @override
  State<POSScreen> createState() => _POSScreenState();
}

class _CartLine {
  final Product product;
  bool isBox;

  /// عدد الشرائط في «وحدة البيع» عندما تكون الوحدة شرائط (web unitChoice):
  /// القائمة تعرض النص المختار، والكمية عدّادات من هذه الوحدة (H).
  int unitChoice;
  int qty = 1;
  _CartLine({required this.product, this.isBox = true, this.unitChoice = 1});

  int get unitPricePiastres => isBox
      ? product.sellingPricePiastres
      : Fmt.stripPrice(
          sellingPricePiastres: product.sellingPricePiastres,
          partialSellingPricePiastres: product.partialSellingPricePiastres,
          unitsPerBox: product.unitsPerBox,
        );

  /// إيراد السطر بالبياستر — مطابق lineTotalPiastres في الويب:
  /// علبة = سعر العلبة × العدد، شرائط = سعر الشريط × unitChoice × العدد.
  int get lineTotal =>
      unitPricePiastres * qty * (isBox ? 1 : (unitChoice > 0 ? unitChoice : 1));

  /// الكمية المطلوبة بالوحدات الأساسية للتحقق من تجاوز المخزون.
  int get requestedBase => isBox
      ? qty * (product.unitsPerBox > 0 ? product.unitsPerBox : 1)
      : qty * (unitChoice > 0 ? unitChoice : 1);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'product': <String, dynamic>{
          'id': product.id,
          'name': product.name,
          'generic_name': product.genericName,
          'strength': product.strength,
          'barcode': product.barcode,
          'packaging_type': product.packagingType,
          'units_per_box': product.unitsPerBox,
          'selling_price_piastres': product.sellingPricePiastres,
          'partial_selling_price_piastres': product.partialSellingPricePiastres,
          'stock': product.stock,
        },
        'is_box': isBox,
        'unit_choice': unitChoice,
        'qty': qty,
      };

  static _CartLine? fromJson(Map<String, dynamic> j) {
    final pj = j['product'];
    if (pj is! Map) return null;
    final product = Product.fromJson(Map<String, dynamic>.from(pj));
    if (product.id.isEmpty) return null;
    final line = _CartLine(
      product: product,
      isBox: j['is_box'] == true,
      unitChoice: j['unit_choice'] is int ? j['unit_choice'] as int : 1,
    )..qty = j['qty'] is int ? j['qty'] as int : 1;
    // تطبيع دفاعي: خيار الشرائط الصالح هو 1..unitsPerBox-1 فقط — ما خارجه
    // يُعاد إلى علبة (أو شريط واحد لعلبة ≥2) حتى لا يتعطل عنصر القائمة.
    if (!line.isBox && product.boxStrip) {
      final units = product.unitsPerBox;
      if (line.unitChoice < 1 || line.unitChoice >= (units > 0 ? units : 1)) {
        if (units >= 2) {
          line.unitChoice = 1;
        } else {
          line.isBox = true;
        }
      }
    }
    return line;
  }
}

/// فاتورة معلّقة (Task 39 رقم 7 نسخة الويب): تُحفظ محليًا وتُستأنف لاحقًا
/// بنفس الأصناف — التسمية تُحسب وقت الإيقاف (صنف واحد/أصناف) وتبقى ثابتة.
class _ParkedSale {
  final String id;
  final String label;
  final String savedAt;
  final List<_CartLine> lines;
  _ParkedSale({required this.id, required this.label, required this.savedAt, required this.lines});

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
        'saved_at': savedAt,
        'lines': <Map<String, dynamic>>[for (final _CartLine l in lines) l.toJson()],
      };

  static _ParkedSale? fromJson(Map<String, dynamic> j) {
    final rawLines = j['lines'];
    final lines = <_CartLine?>[
      if (rawLines is List)
        for (final row in rawLines)
          if (row is Map) _CartLine.fromJson(Map<String, dynamic>.from(row)),
    ].whereType<_CartLine>().toList();
    if (lines.isEmpty) return null;
    return _ParkedSale(
      id: (j['id'] ?? '').toString(),
      label: (j['label'] ?? '').toString(),
      savedAt: (j['saved_at'] ?? '').toString(),
      lines: lines,
    );
  }
}

/// نتيجة اقتراح بحث POS: المنتج + نوع المطابقة ودرجتها كما يعيدها الخادم
/// (match_type/score) لشارة الصف والإضافة الذكية من مسار الماسح.
class _Suggestion {
  final Product product;
  final String matchType;
  final double score;
  const _Suggestion(this.product, this.matchType, this.score);

  static _Suggestion? fromJson(Map<String, dynamic> j) {
    if ((j['id'] ?? '').toString().isEmpty) return null;
    return _Suggestion(
      Product.fromJson(j),
      (j['match_type'] ?? '').toString(),
      j['score'] is num ? (j['score'] as num).toDouble() : 0,
    );
  }
}

class _POSScreenState extends State<POSScreen> {
  static const int _searchDebounceMs = 180; // SEARCH_DEBOUNCE_MS
  static const int _minQueryRunes = 2; // MIN_QUERY_RUNES
  static const int _searchLimit = 8; // SEARCH_LIMIT
  static const int _scannerCodeMinDigits = 6; // SCANNER_CODE_MIN_DIGITS
  static const double _fuzzyAutoAddScore = 0.72; // FUZZY_AUTO_ADD_SCORE

  /// تخزين الفواتير المعلّقة — المشفر كما في session_store.dart، والمفتاح
  /// موحّد للنسخة الموبايل (نظير localStorage في الويب pos_parked_invoices_v1).
  static const FlutterSecureStorage _parkedStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const String _parkedKey = 'pharmacy_parked_carts';

  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _discountCtrl = TextEditingController();
  final List<_CartLine> _cart = <_CartLine>[];
  final List<_ParkedSale> _parked = <_ParkedSale>[];
  List<_Suggestion> _suggestions = <_Suggestion>[];
  bool _searching = false;
  bool _resolving = false;
  Timer? _debounce;
  int _searchSeq = 0;
  String _searchedFor = '';
  bool _discountIsPercent = false; // الويب: useState<'amount'|'percent'>('amount')
  bool _credit = false;
  Customer? _customer;
  bool _checkingOut = false;
  String? _message;
  String? _error;
  String? _lastSaleId;

  /// مفتاح idempotency لسلسلة محاولات الفاتورة الواحدة (web page.tsx:87,249):
  /// يُصكَّ مرة عند أول محاولة بيع ويعاد عبر كل المحاولات الفاشلة — يُصفَّر
  /// بعد نجاح البيع أو الإيقاف المؤقت أو الاستئناف أو تفريغ السلة فقط،
  /// فلا يمكن لعطل شبكة أن ينشئ فاتورة ثانية.
  String? _idempotencyKey;

  /// إعدادات طباعة الإيصال — تُقرأ مرة مثل useReceiptSettings لتقرير autoPrint
  /// لشاشة الإيصال (الافتراضي auto حتى يصل الرد كما في الويب).
  ReceiptSettings? _printSettings;

  @override
  void initState() {
    super.initState();
    unawaited(_loadParked());
    unawaited(_loadPrintSettings());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ البحث الذكي

  bool _isScannerCode(String value) =>
      RegExp('^[0-9]{$_scannerCodeMinDigits,}\$').hasMatch(value.trim());

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    final q = v.trim();
    // أكواد الماسح الرقمية: لا بحث أثناء الكتابة — Enter فقط (نمط الويب)
    if (q.runes.length < _minQueryRunes || _isScannerCode(q)) {
      _searchSeq++; // إبطال أي استجابة قيد الطيران
      setState(() {
        _suggestions = <_Suggestion>[];
        _searchedFor = '';
      });
      return;
    }
    setState(() {}); // زر المسح وبطاقة «لا نتائج» يتبعان النص الحالي
    _debounce = Timer(
      const Duration(milliseconds: _searchDebounceMs),
      () => _runSearch(q),
    );
  }

  /// بحث القائمة المنسدلة — محمي بتسلسل الطلبات: استجابة قديمة بطيئة لا
  /// تمحو نتائج أحدث أبدًا (web product-search.tsx runSearch).
  Future<void> _runSearch(String q) async {
    final seq = ++_searchSeq;
    if (mounted) setState(() => _searching = true);
    List<_Suggestion> results;
    try {
      results = await _searchSuggestions(q);
    } catch (_) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _suggestions = <_Suggestion>[];
        _searching = false;
        _searchedFor = q;
      });
      return;
    }
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _suggestions = results;
      _searching = false;
      _searchedFor = q;
    });
  }

  /// GET /pharmacy/pos/search — يعيد match_type/score لكل صف (يحتاجهما
  /// شارة نوع المطابقة والإضافة التلقائية)؛ يُستخدم dio العميل مباشرة
  /// لأن نموذج Product لا يحمل هذين الحقلين.
  Future<List<_Suggestion>> _searchSuggestions(String q) async {
    final res = await ApiClient.instance.dio.get<dynamic>(
      '/pharmacy/pos/search',
      queryParameters: <String, dynamic>{'q': q, 'limit': _searchLimit},
    );
    final body = res.data;
    final data = body is Map ? body['data'] : null;
    if (data is! List) return <_Suggestion>[];
    return <_Suggestion?>[
      for (final row in data)
        if (row is Map) _Suggestion.fromJson(Map<String, dynamic>.from(row)),
    ].whereType<_Suggestion>().toList();
  }

  /// Enter: القائمة المفتوحة تُضيف أعلى اقتراح مباشرة (سرعة الكاشير)،
  /// كود الماسح يمر بمسار resolveScannerCode، وما عدا ذلك يبحث.
  Future<void> _onSearchSubmitted(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) return;
    if (_suggestions.isNotEmpty) {
      _pick(_suggestions.first.product);
      return;
    }
    if (_isScannerCode(q)) {
      await _resolveScannerCode(q);
      return;
    }
    if (q.runes.length >= _minQueryRunes) {
      await _runSearch(q);
    }
  }

  /// مسار الماسح: باركود تام يُضاف فورًا، وإن فشل ⇒ تصحيح ذكي تلقائي:
  /// أعلى نتيجة من نوع باركود تقريبي/مصحح تُضاف مباشرة عندما تكون وحدها
  /// أو تتجاوز درجة الثقة 0.72 مع رسالة scannerCorrected (web 148-186).
  Future<void> _resolveScannerCode(String code) async {
    final i18n = AppI18n.instance;
    setState(() {
      _resolving = true;
      _message = null;
      _error = null;
    });
    try {
      final exact = await ApiClient.instance.lookupPOSProduct(code);
      if (!mounted) return;
      if (exact != null) {
        _pick(exact);
        return;
      }
      final results = await _searchSuggestions(code);
      if (!mounted) return;
      final _Suggestion? top = results.isNotEmpty ? results.first : null;
      final bool topIsBarcodeHit = top != null &&
          (top.matchType == 'barcode_prefix' || top.matchType == 'barcode_fuzzy');
      if (top != null &&
          topIsBarcodeHit &&
          (results.length == 1 || top.score >= _fuzzyAutoAddScore)) {
        _pick(top.product);
        setState(() => _message = i18n.t('pos', 'scannerCorrected', {'name': top.product.name}));
        return;
      }
      if (results.isNotEmpty) {
        setState(() {
          _suggestions = results;
          _searchedFor = code;
          _message = i18n.t('pos', 'barcodeNotExact');
        });
        return;
      }
      setState(() => _error = i18n.t('pos', 'barcodeNoProduct'));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = AppI18n.instance.error(e.code, e.message));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = i18n.t('pos', 'barcodeSearchFailed'));
    } finally {
      _resolving = false;
      if (mounted) setState(() {});
    }
  }

  /// إضافة من الاختيار (قائمة/باركود/تصحيح): يُمسح النص وتُغلق القائمة
  /// وتُمسح الرسائل مثل pick في الويب — ثم يُضاف للسلة.
  void _pick(Product p) {
    setState(() {
      _message = null;
      _error = null;
      _searchCtrl.clear();
      _suggestions = <_Suggestion>[];
      _searchedFor = '';
    });
    _addLine(p);
  }

  /// إضافة منتج للفاتورة — من القائمة أو الباركود: تُدمج مع سطر علبة قائم
  /// وإلا يُضاف سطر علبة واحد (web addProductToCart).
  void _addLine(Product p) {
    final existing = _cart.where((_CartLine l) => l.product.id == p.id && l.isBox).toList();
    if (existing.isNotEmpty) {
      setState(() => existing.first.qty += 1);
      return;
    }
    setState(() => _cart.add(_CartLine(product: p)));
  }

  bool get _showSuggestionsList => _suggestions.isNotEmpty && _searchCtrl.text.trim().isNotEmpty;

  bool get _showNoResults =>
      !_searching &&
      !_resolving &&
      _suggestions.isEmpty &&
      _searchedFor == _searchCtrl.text.trim() &&
      _searchedFor.runes.length >= _minQueryRunes &&
      !_isScannerCode(_searchedFor);

  // ------------------------------------------------------------ الحسابات

  int get _subtotal => _cart.fold<int>(0, (int sum, _CartLine l) => sum + l.lineTotal);

  int get _discountPiastres {
    final raw = _discountCtrl.text.trim();
    if (raw.isEmpty || _cart.isEmpty) return 0;
    if (_discountIsPercent) {
      final pct = double.tryParse(raw.replaceAll('%', ''));
      if (pct == null || pct <= 0 || pct > 100) return 0;
      return (_subtotal * pct / 100).round();
    }
    final egp = Fmt.parseEGPToPiastres(raw);
    if (egp == null || egp <= 0) return 0;
    return egp > _subtotal ? _subtotal : egp;
  }

  bool get _discountInvalid => _discountCtrl.text.trim().isNotEmpty && _discountPiastres == 0;

  int get _total {
    final t = _subtotal - _discountPiastres;
    return t < 0 ? 0 : t;
  }

  // ------------------------------------------------- إيقاف مؤقت / استئناف

  /// تخزين الفواتير المعلّقة محليًا — فشل التخزين لا يفشل الإيقاف (كالويب:
  /// وضع التصفح الخاص قد يمنع localStorage).
  Future<void> _persistParked() async {
    try {
      await _parkedStorage.write(
        key: _parkedKey,
        value: jsonEncode(<Map<String, dynamic>>[for (final _ParkedSale p in _parked) p.toJson()]),
      );
    } catch (_) {}
  }

  /// استعادة الفواتير المعلّقة عند فتح الشاشة — بيانات تالفة = لا شيء.
  Future<void> _loadParked() async {
    try {
      final raw = await _parkedStorage.read(key: _parkedKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final restored = <_ParkedSale?>[
        for (final row in decoded)
          if (row is Map) _ParkedSale.fromJson(Map<String, dynamic>.from(row)),
      ].whereType<_ParkedSale>().toList();
      if (!mounted || restored.isEmpty) return;
      setState(() => _parked.addAll(restored));
    } catch (_) {}
  }

  void _park() {
    if (_cart.isEmpty) return;
    final i18n = AppI18n.instance;
    final subtotal = _subtotal;
    final invoice = _ParkedSale(
      id: 'parked-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(0x7fffffff)}',
      label: _cart.length == 1
          ? i18n.t('pos', 'parkedLabelOne', {'count': Fmt.number(_cart.length), 'total': Fmt.money(subtotal, locale: i18n.locale)})
          : i18n.t('pos', 'parkedLabelMany', {'count': Fmt.number(_cart.length), 'total': Fmt.money(subtotal, locale: i18n.locale)}),
      savedAt: DateTime.now().toIso8601String(),
      lines: List<_CartLine>.from(_cart),
    );
    setState(() {
      _parked.add(invoice); // الويب يُلحق في النهاية [...parked, invoice]
      _cart.clear();
      _discountCtrl.clear();
      _credit = false;
      _customer = null;
      _idempotencyKey = null;
    });
    unawaited(_persistParked());
    appSnackbar(context, i18n.t('pos', 'parkedInvoices'));
  }

  void _resume(_ParkedSale p) {
    if (_cart.isNotEmpty) {
      final i18n = AppI18n.instance;
      confirmDialog(context, title: i18n.t('pos', 'resumeConfirm'), body: i18n.t('pos', 'resumeConfirm')).then((bool? ok) {
        if (ok == true) _applyResume(p);
      });
      return;
    }
    _applyResume(p);
  }

  void _applyResume(_ParkedSale p) {
    setState(() {
      _cart
        ..clear()
        ..addAll(List<_CartLine>.from(p.lines));
      _parked.remove(p);
      _idempotencyKey = null;
    });
    unawaited(_persistParked());
  }

  void _deleteParked(_ParkedSale p) {
    setState(() => _parked.remove(p));
    unawaited(_persistParked());
  }

  // ------------------------------------------------------------ الدفع

  Future<void> _pickCustomer() async {
    final picked = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CustomerPickerSheet(),
    );
    if (picked != null && mounted) setState(() => _customer = picked);
  }

  Future<void> _loadPrintSettings() async {
    try {
      final settings = await ApiClient.instance.getSettings();
      if (mounted) setState(() => _printSettings = settings);
    } catch (_) {
      // الافتراضي auto يبقى مطابقًا لافتراضيات الخادم (useReceiptSettings)
    }
  }

  bool get _autoPrint => (_printSettings?.printMode ?? 'auto') == 'auto';

  Future<void> _checkout() async {
    final i18n = AppI18n.instance;
    if (_cart.isEmpty || _checkingOut) return;
    if (_discountInvalid) {
      setState(() => _error = _discountIsPercent ? i18n.t('pos', 'discountPercentError') : i18n.t('pos', 'discountAmountError'));
      return;
    }
    if (_credit && _customer == null) {
      setState(() => _error = i18n.t('pos', 'creditRequiresCustomer'));
      return;
    }
    setState(() {
      _checkingOut = true;
      _error = null;
      _message = null;
    });
    // مفتاح واحد لسلسلة المحاولات: يُصكَّ عند أول محاولة فقط (web 249-251)
    _idempotencyKey ??= _mintIdempotencyKey();
    try {
      final items = <Map<String, dynamic>>[
        for (final _CartLine l in _cart)
          <String, dynamic>{
            'pharmacy_product_id': l.product.id,
            'sale_unit': l.isBox ? 'box' : 'strip',
            'quantity': l.isBox ? l.qty : l.qty * (l.unitChoice > 0 ? l.unitChoice : 1),
          },
      ];
      final options = <String, dynamic>{};
      final discount = _discountPiastres;
      if (discount > 0) {
        options['discount'] = _discountIsPercent
            ? <String, dynamic>{'kind': 'percent', 'value': double.tryParse(_discountCtrl.text.trim()) ?? 0}
            : <String, dynamic>{'kind': 'amount', 'value': discount};
      }
      if (_credit && _customer != null) {
        options['payment_type'] = 'credit';
        options['customer_id'] = _customer!.id;
      }
      final result = await ApiClient.instance.createPOSSale(
        items: items,
        idempotencyKey: _idempotencyKey,
        options: options.isEmpty ? null : options,
      );
      if (!mounted) return;
      // تُلتقط قبل الـsetState الذي يمسح السلة/العميل (رسالة البيع الآجل)
      final String creditCustomerName = _credit ? (_customer?.name ?? '') : '';
      setState(() {
        _cart.clear();
        _discountCtrl.clear();
        _credit = false;
        _customer = null;
        _idempotencyKey = null; // نجاح البيع = سلسلة جديدة للفاتورة التالية
        _lastSaleId = result.saleId;
        _message = creditCustomerName.isNotEmpty
            ? i18n.t('pos', 'creditSaleSuccess', {
                'name': creditCustomerName,
                'total': Fmt.money(result.totalAmount, locale: i18n.locale),
              })
            : i18n.t('pos', 'saleSuccess', {'total': Fmt.money(result.totalAmount, locale: i18n.locale)});
      });
      await _openReceipt(result.saleId);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.status == 409 ? e.message : i18n.error(e.code, i18n.t('errors', 'sale_failed')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = AppI18n.instance.t('errors', 'sale_failed'));
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  /// مفتاح فريد ≥8 خانات بصيغة UUID-ish (باكند: 8..128 حرفًا)
  static String _mintIdempotencyKey() =>
      'pos-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
      '${Random().nextInt(0x7fffffff).toRadixString(36)}';

  Future<void> _openReceipt(String saleId) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ReceiptScreen(saleId: saleId, autoPrint: _autoPrint),
    ));
  }

  // ------------------------------------------------------------ الواجهة

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final bool busy = _resolving || (_searching && _suggestions.isEmpty);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        PageHeader(i18n.t('pos', 'title'), subtitle: i18n.t('pos', 'subtitle')),
        const SizedBox(height: 24),

        // بطاقة إضافة الأصناف
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: CardTitle(i18n.t('pos', 'addProductTitle'),
                    icon: Icons.search, subtitle: i18n.t('pos', 'addProductDesc')),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: <Widget>[
                    TextField(
                      controller: _searchCtrl,
                      onChanged: _onSearchChanged,
                      onSubmitted: _onSearchSubmitted,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: i18n.t('pos', 'searchPlaceholder'),
                        prefixIcon: const Icon(Icons.qr_code_scanner, size: 20),
                        suffixIcon: busy
                            ? const Padding(
                                padding: EdgeInsets.all(10),
                                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                            : (_searchCtrl.text.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () {
                                      _searchSeq++;
                                      _searchCtrl.clear();
                                      setState(() {
                                        _suggestions = <_Suggestion>[];
                                        _searchedFor = '';
                                      });
                                    },
                                  )),
                        isDense: true,
                      ),
                    ),
                    if (_showSuggestionsList) ...<Widget>[
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 320), // max-h-80 مع تمرير
                        decoration: BoxDecoration(
                          borderRadius: AppRadius.br,
                          border: Border.all(color: theme.dividerColor),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: SingleChildScrollView(
                          child: Column(
                            children: <Widget>[
                              for (final _Suggestion s in _suggestions.take(_searchLimit))
                                _SuggestionTile(
                                  suggestion: s,
                                  query: _searchCtrl.text,
                                  onAdd: () => _pick(s.product),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (_showNoResults) ...<Widget>[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: AppRadius.br,
                          border: Border.all(color: theme.dividerColor),
                          color: theme.colorScheme.surface,
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(Icons.search_off,
                                size: 16, color: theme.colorScheme.onSurface.withOpacity(0.45)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(i18n.t('pos', 'noResults'),
                                  style: TextStyle(
                                      fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // بطاقة السلة
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: CardTitle(
                        i18n.t('pos', 'cartTitle'),
                        icon: Icons.receipt_long_outlined,
                        subtitle: _cart.isNotEmpty
                            ? i18n.t('pos', 'cartCount', {'count': Fmt.number(_cart.length)})
                            : i18n.t('pos', 'cartEmpty'),
                      ),
                    ),
                    if (_cart.isNotEmpty) ...<Widget>[
                      WButton(i18n.t('pos', 'park'),
                          icon: Icons.pause_circle_outline,
                          variant: WButtonVariant.outline,
                          onPressed: _park),
                      const SizedBox(width: 8),
                      IconButtonGhost(
                        Icons.delete_outline,
                        tooltip: i18n.t('pos', 'clearCart'),
                        color: theme.colorScheme.error,
                        onPressed: () => setState(() {
                          _cart.clear();
                          _discountCtrl.clear();
                          _idempotencyKey = null; // تفريغ السلة = سلسلة جديدة
                        }),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // الفواتير المعلّقة — شرائط استئناف/حذف على خلفية muted/40
                    if (_parked.isNotEmpty) ...<Widget>[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface.withOpacity(0.04),
                          borderRadius: AppRadius.brXl,
                        ),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: <Widget>[
                            Text(i18n.t('pos', 'parkedInvoices'),
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                            for (final _ParkedSale p in _parked)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: theme.dividerColor),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    GestureDetector(
                                      onTap: () => _resume(p),
                                      child: Text(
                                        // التسمية محفوظة وقت الإيقاف (parkedLabelOne/Many)
                                        p.label,
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () => _deleteParked(p),
                                      child: Icon(Icons.delete_outline,
                                          size: 14, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_cart.isEmpty)
                      EmptyState(i18n.t('pos', 'startEmpty'), icon: null, dashed: true)
                    else
                      for (final _CartLine l in _cart) ...<Widget>[
                        _CartLineTile(line: l, onChanged: () => setState(() {}), onRemove: () => setState(() => _cart.remove(l))),
                        const SizedBox(height: 12),
                      ],

                    // الخصم + طريقة الدفع
                    if (_cart.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      CardBox(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Expanded(
                                  flex: 2,
                                  child: AppField(
                                    label: i18n.t('pos', 'discountLabel'),
                                    child: AppInput(
                                      controller: _discountCtrl,
                                      keyboard: const TextInputType.numberWithOptions(decimal: true),
                                      hint: _discountIsPercent ? i18n.t('pos', 'discountPercentPlaceholder') : i18n.t('pos', 'discountAmountPlaceholder'),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: AppField(
                                    label: '',
                                    child: AppDropdown<String>(
                                      value: _discountIsPercent ? 'percent' : 'amount',
                                      items: <DropdownMenuItem<String>>[
                                        DropdownMenuItem<String>(value: 'amount', child: Text(i18n.t('pos', 'discountKindAmount'), style: const TextStyle(fontSize: 13))),
                                        DropdownMenuItem<String>(value: 'percent', child: Text(i18n.t('pos', 'discountKindPercent'), style: const TextStyle(fontSize: 13))),
                                      ],
                                      onChanged: (String? v) => setState(() {
                                        _discountIsPercent = v == 'percent';
                                        _discountCtrl.clear();
                                      }),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_discountInvalid)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  _discountIsPercent ? i18n.t('pos', 'discountInvalidPercent') : i18n.t('pos', 'discountInvalidAmount'),
                                  style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
                                ),
                              ),
                            const SizedBox(height: 16),
                            AppField(
                              label: i18n.t('pos', 'paymentLabel'),
                              child: AppDropdown<String>(
                                value: _credit ? 'credit' : 'cash',
                                items: <DropdownMenuItem<String>>[
                                  DropdownMenuItem<String>(value: 'cash', child: Text(i18n.t('pos', 'paymentCash'), style: const TextStyle(fontSize: 14))),
                                  if (context.read<AppState>().can('customers.view'))
                                    DropdownMenuItem<String>(value: 'credit', child: Text(i18n.t('pos', 'paymentCredit'), style: const TextStyle(fontSize: 14))),
                                ],
                                onChanged: (String? v) => setState(() => _credit = v == 'credit'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // اختيار العميل للآجل
                      if (_credit) ...<Widget>[
                        CardBox(
                          borderColor: theme.colorScheme.primary.withOpacity(0.30),
                          color: theme.colorScheme.primary.withOpacity(0.05),
                          child: _customer == null
                              ? InkWell(
                                  borderRadius: AppRadius.brXl,
                                  onTap: _pickCustomer,
                                  child: Row(
                                    children: <Widget>[
                                      Icon(Icons.person_outline, size: 20, color: theme.colorScheme.primary),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(i18n.t('pos', 'customerSearchPlaceholder'), style: const TextStyle(fontSize: 14))),
                                      Text(i18n.t('pos', 'changeCustomer'),
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.primary)),
                                    ],
                                  ),
                                )
                              : Row(
                                  children: <Widget>[
                                    Icon(Icons.person, size: 20, color: theme.colorScheme.primary),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(_customer!.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                          Text(
                                            '${_customer!.phone.isEmpty ? i18n.t('pos', 'noPhone') : _customer!.phone}'
                                            '${_customer!.balancePiastres != 0 ? ' ${i18n.t('pos', 'previousBalance', {'total': Fmt.money(_customer!.balancePiastres, locale: i18n.locale)})}' : ''}',
                                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    GhostButton(i18n.t('pos', 'changeCustomer'), onPressed: _pickCustomer),
                                  ],
                                ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // صف الإجماليات
                      Container(
                        padding: const EdgeInsets.only(top: 20), // border-t pt-5
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: theme.dividerColor)),
                        ),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(i18n.t('pos', 'totalsHint'),
                                  style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: <Widget>[
                                if (_discountPiastres > 0) ...<Widget>[
                                  Text(i18n.t('pos', 'beforeDiscount', {'total': Fmt.money(_subtotal, locale: i18n.locale)}),
                                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                                  Text(i18n.t('pos', 'discountLine', {'total': Fmt.money(_discountPiastres, locale: i18n.locale)}),
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.error)),
                                ],
                                Text(i18n.t('pos', 'total'),
                                    style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                                Text(Fmt.money(_total, locale: i18n.locale),
                                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
                              ],
                            ),
                            const SizedBox(width: 20),
                            WButton(
                              _credit ? i18n.t('pos', 'checkoutCredit') : i18n.t('pos', 'checkout'),
                              onPressed: _checkout,
                              loading: _checkingOut,
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (_error != null) ...<Widget>[
                      const SizedBox(height: 16),
                      ErrorBanner(_error!),
                    ],
                    if (_message != null) ...<Widget>[
                      const SizedBox(height: 16),
                      SuccessBanner(
                        _message!,
                        // الويب: زر الطباعة اليدوية في وضع manual فقط (auto يطبع تلقائيًا)
                        action: _lastSaleId != null && !_autoPrint
                            ? WButton(
                                i18n.t('pos', 'printInvoice'),
                                icon: Icons.print_outlined,
                                variant: WButtonVariant.outline,
                                size: WButtonSize.sm,
                                onPressed: () => _openReceipt(_lastSaleId!),
                              )
                            : null,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ------------------------------------------------------------ مساعدات العرض

/// extraStrengthLabel من lib/product.ts: لا يُلحق التركيز إن كان الاسم
/// يحتويه أصلًا أو يحمل جرعة — منع «كاربيمازول 200mg 500mg».
String _extraStrengthLabel(String name, String strength) {
  final clean = strength.trim();
  if (clean.isEmpty) return '';
  if (name.toLowerCase().contains(clean.toLowerCase())) return '';
  if (RegExp(r'\d\s*(?:mg|µg|mcg|g|ml|iu|ملجم|ملغ|مل|جرام|وحدة)', caseSensitive: false).hasMatch(name)) {
    return '';
  }
  return clean;
}

/// matchLabelKeys من الويب — مفتاح الكتالوج لكل نوع مطابقة يعيده الخادم.
const Map<String, String> _kMatchLabelKeys = <String, String>{
  'barcode_exact': 'matchBarcodeExact',
  'barcode_prefix': 'matchBarcodePrefix',
  'barcode_fuzzy': 'matchBarcodeFuzzy',
  'name_prefix': 'matchNamePrefix',
  'name_substring': 'matchNameSubstring',
  'name_fuzzy': 'matchNameFuzzy',
  'generic_fuzzy': 'matchGenericFuzzy',
};

/// تسمية نوع المطابقة من كتالوج pos — null للأنواع غير المعروفة (يعرض الخام).
String? _matchLabel(String matchType) {
  final String? key = _kMatchLabelKeys[matchType];
  return key == null ? null : AppI18n.instance.t('pos', key);
}

/// HighlightName من الويب: يبرز الجزء المطابق (بادئة/احتواء) فقط.
List<InlineSpan> _highlightNameSpans(BuildContext context, String name, String query) {
  final theme = Theme.of(context);
  final q = query.trim();
  final base = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
  if (q.isEmpty) return <InlineSpan>[TextSpan(text: name, style: base)];
  final index = name.indexOf(q);
  if (index < 0) return <InlineSpan>[TextSpan(text: name, style: base)];
  final markStyle = base.copyWith(
    backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
    color: theme.colorScheme.primary,
  );
  return <InlineSpan>[
    TextSpan(text: name.substring(0, index), style: base),
    TextSpan(text: name.substring(index, index + q.length), style: markStyle),
    TextSpan(text: name.substring(index + q.length), style: base),
  ];
}

/// صف اقتراح — مثل dropdown نتائج الويب: الاسم مع تمييز المطابقة + لاحقة
/// التركيز، سطر المادة الفعالة والباركود، السعر + متاح/نافد، وشارة نوع
/// المطابقة (باركود بلون الهوية، اسم بلون محايد).
class _SuggestionTile extends StatelessWidget {
  final _Suggestion suggestion;
  final String query;
  final VoidCallback onAdd;
  const _SuggestionTile({required this.suggestion, required this.query, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final Product p = suggestion.product;
    final subtitle = <String>[
      if (p.genericName.isNotEmpty) p.genericName,
      if (p.barcode.isNotEmpty) p.barcode,
    ].join(' · ');
    final stockLabel = p.stock <= 0
        ? Text(i18n.t('pos', 'outOfStock'),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: theme.colorScheme.error))
        : Text(i18n.t('pos', 'inStock', {'count': Fmt.number(p.stock)}),
            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.55)));
    final strengthLabel = _extraStrengthLabel(p.name, p.strength);
    final matchLabelText = _matchLabel(suggestion.matchType);
    final isBarcodeMatch = suggestion.matchType.startsWith('barcode');
    return InkWell(
      onTap: onAdd,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        ..._highlightNameSpans(context, p.name, query),
                        if (strengthLabel.isNotEmpty)
                          TextSpan(
                            text: ' $strengthLabel',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: theme.colorScheme.onSurface.withOpacity(0.55)),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(Fmt.money(
                      p.boxStrip ? p.sellingPricePiastres : Fmt.stripPrice(sellingPricePiastres: p.sellingPricePiastres, partialSellingPricePiastres: p.partialSellingPricePiastres, unitsPerBox: p.unitsPerBox),
                      locale: i18n.locale,
                    ),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
                stockLabel,
              ],
            ),
            const SizedBox(width: 8),
            if (matchLabelText != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: isBarcodeMatch
                          ? theme.colorScheme.primary.withOpacity(0.40)
                          : theme.dividerColor),
                  color: isBarcodeMatch
                      ? theme.colorScheme.primary.withOpacity(0.10)
                      : theme.colorScheme.onSurface.withOpacity(0.04),
                ),
                child: Text(matchLabelText,
                    style: TextStyle(
                        fontSize: 10,
                        height: 1.4,
                        color: isBarcodeMatch
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withOpacity(0.55))),
              ),
          ],
        ),
      ),
    );
  }
}

/// سطر سلة POS — rounded-xl border p-4: الاسم + المخزون، اختيار الوحدة
/// (يحفظ عدد الشرائط المختار على السطر — H)، عدّاد كمية h-10، الإجمالي
/// + تحذير تجاوز المخزون، وحذف شبحي.
class _CartLineTile extends StatelessWidget {
  final _CartLine line;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  const _CartLineTile({required this.line, required this.onChanged, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final p = line.product;
    final unitsPerBox = p.unitsPerBox > 0 ? p.unitsPerBox : 1;
    final boxes = p.boxStrip ? p.stock ~/ unitsPerBox : p.stock;
    final strips = p.boxStrip ? p.stock % unitsPerBox : 0;
    final stockText = p.boxStrip
        ? i18n.t('pos', 'stockBoxStrip', {'boxes': Fmt.number(boxes), 'strips': Fmt.number(strips)})
        : i18n.t('pos', 'stockPacks', {'count': Fmt.number(p.stock)});
    final strengthLabel = _extraStrengthLabel(p.name, p.strength);
    String unitLabel;
    if (line.isBox) {
      unitLabel = i18n.t('pos', 'unitBox');
    } else {
      final total = line.qty * (line.unitChoice > 0 ? line.unitChoice : 1);
      unitLabel = total == 1
          ? i18n.t('pos', 'unitStripOne')
          : total == 2
              ? i18n.t('pos', 'unitStripTwo')
              : i18n.t('pos', 'unitStrips', {'count': Fmt.number(total)});
    }
    return CardBox(
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
                    Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(text: p.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          if (strengthLabel.isNotEmpty)
                            TextSpan(
                              text: ' $strengthLabel',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: theme.colorScheme.onSurface.withOpacity(0.55)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('${p.barcode} · $stockText',
                        style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                  ],
                ),
              ),
              IconButtonGhost(
                Icons.delete_outline,
                tooltip: i18n.t('pos', 'deleteLine'),
                color: theme.colorScheme.error,
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              // الوحدة
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(i18n.t('pos', 'unitLabel'), style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                    const SizedBox(height: 4),
                    if (p.boxStrip)
                      AppDropdown<String>(
                        // القيمة = عدد الشرائط المختار المحفوظ على السطر (H)
                        value: line.isBox ? 'box' : '${line.unitChoice > 0 ? line.unitChoice : 1}',
                        items: <DropdownMenuItem<String>>[
                          DropdownMenuItem<String>(value: 'box', child: Text(i18n.t('pos', 'unitBox'), style: const TextStyle(fontSize: 13))),
                          for (int s = 1; s < unitsPerBox; s++)
                            DropdownMenuItem<String>(
                              value: '$s',
                              child: Text(
                                s == 1 ? i18n.t('pos', 'unitStripOne') : s == 2 ? i18n.t('pos', 'unitStripTwo') : i18n.t('pos', 'unitStrips', {'count': Fmt.number(s)}),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                        ],
                        onChanged: (String? v) {
                          line.isBox = v == 'box';
                          line.unitChoice = v == 'box' ? 1 : int.tryParse(v ?? '1') ?? 1;
                          line.qty = 1;
                          onChanged();
                        },
                      )
                    else
                      Text(unitLabel, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // الكمية
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(i18n.t('pos', 'quantity'), style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                    const SizedBox(height: 4),
                    QtyStepper(
                      value: line.qty,
                      onDec: () {
                        if (line.qty > 1) {
                          line.qty -= 1;
                          onChanged();
                        }
                      },
                      onInc: () {
                        line.qty += 1;
                        onChanged();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // الإجمالي
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(unitLabel, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                    const SizedBox(height: 4),
                    Text(Fmt.money(line.lineTotal, locale: i18n.locale),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    if (line.requestedBase > p.stock)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(i18n.t('pos', 'overStock'),
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.error)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// منتقي العملاء للآجل: بحث + إضافة عميل جديد (مقيدة بـ customers.create — E)
class _CustomerPickerSheet extends StatefulWidget {
  @override
  State<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<_CustomerPickerSheet> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _newName = TextEditingController();
  final TextEditingController _newPhone = TextEditingController();
  List<Customer> _list = <Customer>[];
  bool _loading = true;
  bool _adding = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _newName.dispose();
    _newPhone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ApiClient.instance.customers(search: _search.text.trim());
      if (!mounted) return;
      setState(() {
        _list = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _addNew() async {
    final name = _newName.text.trim();
    if (name.isEmpty || _adding) return;
    setState(() => _adding = true);
    try {
      final c = await ApiClient.instance.createCustomer(name, _newPhone.text.trim());
      if (!mounted) return;
      Navigator.pop(context, c);
    } on ApiException catch (e) {
      if (!mounted) return;
      appSnackbar(context, AppI18n.instance.error(e.code, e.message), error: true);
      setState(() => _adding = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    // إضافة العملاء صلاحية مستقلة — القسم كله يختفي بلا customers.create (E)
    final bool canAddCustomers = context.read<AppState>().can('customers.create');
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(i18n.t('nav', 'customers'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              SearchField(controller: _search, hint: i18n.t('pos', 'customerSearchPlaceholder'), onChanged: _onChanged, onClear: () { _search.clear(); _load(); }),
              const SizedBox(height: 12),
              if (_loading)
                const LoadingBox()
              else if (_list.isEmpty)
                Text(i18n.t('common', 'no_options'), style: const TextStyle(fontSize: 14), textAlign: TextAlign.center)
              else
                ..._list.take(8).map((Customer c) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(c.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text(c.phone.isEmpty ? i18n.t('pos', 'noPhoneShort') : c.phone, style: const TextStyle(fontSize: 12)),
                      trailing: Text(Fmt.money(c.balancePiastres, locale: i18n.locale),
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.balancePiastres > 0 ? AppColors.warningFg : null)),
                      onTap: () => Navigator.pop(context, c),
                    )),
              if (canAddCustomers) ...<Widget>[
                const Divider(height: 22),
                Text(i18n.t('pos', 'customerAutoAddedHint'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55))),
                const SizedBox(height: 8),
                AppInput(controller: _newName, hint: i18n.t('pos', 'customerNamePlaceholder')),
                const SizedBox(height: 8),
                AppInput(controller: _newPhone, hint: i18n.t('pos', 'customerPhonePlaceholder'), keyboard: TextInputType.phone),
                const SizedBox(height: 12),
                WButton(i18n.t('pos', 'add'), icon: Icons.person_add_alt_1, loading: _adding, onPressed: _addNew),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
