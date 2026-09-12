import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/strings.dart';
import '../models/models.dart';
import '../state/app_state.dart';

/// Phase G — شاشة الدفع المضمّن: فورم Paymob يُصيَّر داخل WebView داخل
/// التطبيق نفسه — العميل لا يخرج إلى متصفح خارجي إطلاقًا، وبيانات البطاقة
/// لا تلمس خوادمنا (PCI على Paymob). التفعيل يحدث حصرًا من الويبهوك الموثق
/// خادميًا؛ الـ polling هنا للعرض فقط:
///   succeeded → pop(true)  |  failed/cancelled/voided → pop(false).
class PaymobCheckoutScreen extends StatefulWidget {
  final CheckoutInfo checkout;

  const PaymobCheckoutScreen({super.key, required this.checkout});

  @override
  State<PaymobCheckoutScreen> createState() => _PaymobCheckoutScreenState();
}

class _PaymobCheckoutScreenState extends State<PaymobCheckoutScreen> {
  late final WebViewController _web;
  Timer? _poll;
  int _elapsed = 0;
  bool _settled = false;

  static const int _pollIntervalSec = 3;
  static const int _pollMaxSec = 600; // 10 دقائق ثم توقف صامت

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        // منع أي تنقل خارج نطاق بوابة الدفع بعد اكتمال العملية
        onPageFinished: (_) => setState(() {}),
      ))
      ..loadRequest(Uri.parse(widget.checkout.embedUrl));
    _poll = Timer.periodic(
        const Duration(seconds: _pollIntervalSec), (_) => _check());
  }

  Future<void> _check() async {
    if (_settled || !mounted) return;
    _elapsed += _pollIntervalSec;
    if (_elapsed > _pollMaxSec) {
      _stopPoll();
      return;
    }
    try {
      final state = context.read<AppState>();
      final status = await state.api.paymentStatus(widget.checkout.paymentId);
      if (_settled || !mounted) return;
      if (status.status == 'succeeded') {
        _settled = true;
        _stopPoll();
        await state.refreshSubscription();
        if (mounted) Navigator.of(context).pop(true);
      } else if (status.status == 'failed' ||
          status.status == 'cancelled' ||
          status.status == 'voided') {
        _settled = true;
        _stopPoll();
        if (mounted) Navigator.of(context).pop(false);
      }
    } catch (_) {
      // هفحة شبكة أثناء الـ polling — نحاول في الدورة القادمة
    }
  }

  void _stopPoll() {
    _poll?.cancel();
    _poll = null;
  }

  @override
  void dispose() {
    _stopPoll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n.t('subscription', 'checkout_title')),
        leading: BackButton(onPressed: () => Navigator.of(context).pop(null)),
      ),
      body: Column(
        children: <Widget>[
          Expanded(child: WebViewWidget(controller: _web)),
          // مؤشر انتظار ثابت أسفل الشاشة: الدفع قيد التأكيد من الخادم
          LinearProgressIndicator(
            minHeight: 3,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: Text(
              i18n.t('subscription', 'checkout_waiting'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
