import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/strings.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';

/// هل نعمل على ويندوز (سطح مكتب) — لا WebView متاحًا هناك؟
bool get _isWindows => !kIsWeb && Platform.isWindows;

/// Phase G — شاشة الدفع المضمّن: فورم Paymob يُصيَّر داخل WebView داخل
/// التطبيق نفسه — العميل لا يخرج إلى متصفح خارجي إطلاقًا، وبيانات البطاقة
/// لا تلمس خوادمنا (PCI على Paymob). التفعيل يحدث حصرًا من الويبهوك الموثق
/// خادميًا؛ الـ polling هنا للعرض فقط:
///   succeeded → pop(true)  |  failed/cancelled/voided → pop(false).
/// Windows desktop: لا WebView في الإطارات لويندوز — يُفتح الفورم في
/// متصفح الكمبيوتر الخارجي ونفس الـ polling يكشف النتيجة هنا تلقائيًا.
class PaymobCheckoutScreen extends StatefulWidget {
  final CheckoutInfo checkout;

  const PaymobCheckoutScreen({super.key, required this.checkout});

  @override
  State<PaymobCheckoutScreen> createState() => _PaymobCheckoutScreenState();
}

class _PaymobCheckoutScreenState extends State<PaymobCheckoutScreen> {
  /// null على ويندوز — الفورم في المتصفح الخارجي بدل الـWebView.
  WebViewController? _web;
  Timer? _poll;
  int _elapsed = 0;
  bool _settled = false;

  static const int _pollIntervalSec = 3;
  static const int _pollMaxSec = 600; // 10 دقائق ثم توقف صامت

  @override
  void initState() {
    super.initState();
    if (!_isWindows) {
      _web = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          // منع أي تنقل خارج نطاق بوابة الدفع بعد اكتمال العملية
          onPageFinished: (_) => setState(() {}),
        ))
        ..loadRequest(Uri.parse(widget.checkout.embedUrl));
    }
    _poll = Timer.periodic(
        const Duration(seconds: _pollIntervalSec), (_) => _check());
  }

  Future<void> _openExternal() async {
    final Uri url = Uri.parse(widget.checkout.embedUrl);
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n.t('subscription', 'checkout_title')),
        leading: BackButton(onPressed: () => Navigator.of(context).pop(null)),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: _isWindows
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Container(
                            width: 64,
                            height: 64,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withOpacity(0.10),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.open_in_new,
                                size: 28, color: theme.colorScheme.primary),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            i18n.t('subscription', 'checkout_desktop_hint'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 14,
                                height: 1.7,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.75)),
                          ),
                          const SizedBox(height: 20),
                          WButton(
                            i18n.t('subscription', 'checkout_open_browser'),
                            icon: Icons.open_in_new,
                            onPressed: () => _openExternal(),
                          ),
                        ],
                      ),
                    ),
                  )
                : WebViewWidget(controller: _web!),
          ),
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
