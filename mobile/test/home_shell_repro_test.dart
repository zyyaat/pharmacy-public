// Task 63 — إعادة إنتاج «الشاشة الرمادية المتجمدة» التي أرسلها المستخدم:
// 1) يثبت انهيار زر القائمة الجانبية (Scaffold.of بسياق أعلى من Scaffold)
// 2) يبني هيكل /home كاملًا (IndexedStack بكل الصفحات) ببيانات واقعية عبر
//    محوّل dio وهمي — ويتنقّل بين كل الصفحات لالتقاط أي استثناء build
//    (يظهر للمستخدم في وضع release كصندوق رمادي متجمد).
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pharmacy_mobile/core/api_client.dart';
import 'package:pharmacy_mobile/core/strings.dart';
import 'package:pharmacy_mobile/core/theme.dart';
import 'package:pharmacy_mobile/models/models.dart';
import 'package:pharmacy_mobile/screens/dashboard_screen.dart';
import 'package:pharmacy_mobile/screens/home_screen.dart';
import 'package:pharmacy_mobile/state/app_state.dart';

/// بديل خادم: يرد على كل المسارات بأشكال مطابقة للباكند بقيم حافّة
/// (أسماء فارغة، أصفار، حالات متنوعة) لكشف أي هشاشة بناء.
Map<String, dynamic> _bodyFor(String path) {
  if (path.endsWith('/auth/pharmacy/me')) {
    return <String, dynamic>{
      'user': <String, dynamic>{
        'id': 'u1',
        'email': 'owner@pharmacy.eg',
        'first_name': 'صاحب',
        'last_name': 'الصيدلية',
        'display_name': 'صاحب الصيدلية',
        'role': 'OWNER',
      },
    };
  }
  if (path.endsWith('/pharmacy/context')) {
    return <String, dynamic>{
      'data': <String, dynamic>{
        'pharmacy': <String, dynamic>{
          'id': 'p1',
          'name': 'صيدلية الشفاء',
          'city': 'القاهرة',
          'address': 'شارع التحرير',
          'phone': '0223334444',
          'product_count': 42,
        },
        'branch': <String, dynamic>{'id': 'b1', 'name': 'الفرع الرئيسي', 'city': 'القاهرة'},
        'user': <String, dynamic>{'id': 'u1', 'role': 'OWNER'},
      },
    };
  }
  if (path.endsWith('/pharmacy/permissions/me')) {
    return <String, dynamic>{
      'data': <String, dynamic>{
        'principal_type': 'pharmacy',
        'role': 'owner',
        'permissions': <String>[],
        'full_access': true,
      },
    };
  }
  if (path.endsWith('/pharmacy/dashboard/stats')) {
    return <String, dynamic>{
      'data': <String, dynamic>{
        'totalProducts': 42,
        'lowStockCount': 2,
        'activeEmployees': 3,
        'activeToday': 2,
        'salesUnitsToday': 15,
        'lowStockItems': <dynamic>[
          <String, dynamic>{
            'name': 'بنادول اكسترا 500 ملغ أقراص',
            'generic_name': 'Paracetamol',
            'status': 'LOW_STOCK',
            'quantity': 2,
            'strips': 5,
            'min_stock_level': 5,
          },
          <String, dynamic>{
            'name': 'أوجمنتين 1g أقراص',
            'generic_name': 'Amoxicillin',
            'status': 'OUT_OF_STOCK',
            'quantity': 0,
            'strips': 0,
            'min_stock_level': 2,
          },
        ],
      },
    };
  }
  if (path.endsWith('/pharmacy/inventory/low-stock')) {
    return <String, dynamic>{
      'data': <dynamic>[
        <String, dynamic>{
          'pharmacy_product_id': 'pp1',
          'product_name': 'بنادول اكسترا 500 ملغ أقراص',
          'strength': '500mg',
          'barcode': '622104800001',
          'packaging_type': 'BOX_STRIP',
          'units_per_box': 24,
          'full_boxes': 2,
          'strips': 5,
          'min_stock_level': 5,
        },
        <String, dynamic>{
          'pharmacy_product_id': 'pp2',
          'product_name': '',
          'strength': '',
          'barcode': '',
          'packaging_type': 'WHOLE_ONLY',
          'units_per_box': 1,
          'full_boxes': 0,
          'strips': 0,
          'min_stock_level': 0,
        },
      ],
    };
  }
  if (path.endsWith('/pharmacy/customers')) {
    return <String, dynamic>{
      'data': <dynamic>[
        <String, dynamic>{
          'id': 'c1',
          'name': 'أحمد علي',
          'phone': '01001234567',
          'balance_piastres': 5000,
          'created_at': '2026-01-01T10:00:00Z',
        },
        <String, dynamic>{
          'id': 'c2',
          'name': '',
          'phone': '',
          'balance_piastres': 0,
          'created_at': null,
        },
      ],
    };
  }
  if (path.endsWith('/pharmacy/inventory')) {
    return <String, dynamic>{
      'data': <dynamic>[
        <String, dynamic>{
          'id': 'b1',
          'product_id': 'p1',
          'name': 'بنادول اكسترا',
          'strength': '500mg',
          'barcode': '622104800001',
          'packaging_type': 'BOX_STRIP',
          'units_per_box': 24,
          'selling_price_piastres': 3600,
          'partial_selling_price_piastres': 200,
          'boxes': 10,
          'strips': 5,
          'quantity': 245,
          'min_stock_level': 10,
          'status': 'available',
          'expiry_date': '2027-01-01',
        },
      ],
    };
  }
  if (path.endsWith('/pharmacy/products')) {
    return <String, dynamic>{
      'data': <dynamic>[
        <String, dynamic>{
          'id': 'p1',
          'name': 'بنادول اكسترا',
          'strength': '500mg',
          'barcode': '622104800001',
          'packaging_type': 'BOX_STRIP',
          'units_per_box': 24,
          'selling_price_piastres': 3600,
          'partial_selling_price_piastres': 200,
        },
      ],
    };
  }
  if (path.endsWith('/pharmacy/pos/sales') && !path.contains('/returns')) {
    return <String, dynamic>{
      'data': <String, dynamic>{
        'sales': <dynamic>[
          <String, dynamic>{
            'id': 's1',
            'sale_number': 'INV-000123',
            'total_amount_piastres': 7200,
            'discount_amount_piastres': 0,
            'payment_type': 'cash',
            'status': 'completed',
            'created_at': '2026-09-10T12:00:00Z',
            'items_count': 2,
          },
        ],
        'total': 1,
        'limit': 20,
        'offset': 0,
      },
    };
  }
  if (path.endsWith('/pharmacy/inventory/movements')) {
    return <String, dynamic>{
      'data': <String, dynamic>{
        'movements': <dynamic>[
          <String, dynamic>{
            'id': 'm1',
            'type': 'purchase',
            'direction': 'in',
            'product_name': 'بنادول اكسترا',
            'quantity': 24,
            'created_at': '2026-09-10T12:00:00Z',
            'actor_display_name': 'صاحب الصيدلية',
          },
        ],
        'total': 1,
      },
    };
  }
  if (path.endsWith('/pharmacy/employees')) {
    return <String, dynamic>{
      'employees': <dynamic>[
        <String, dynamic>{
          'id': 'e1',
          'display_name': 'محمود الصيدلي',
          'email': 'mahmoud@pharmacy.eg',
          'status': 'active',
        },
      ],
    };
  }
  if (path.endsWith('/pharmacy/attendance')) {
    return <String, dynamic>{
      'data': <dynamic>[
        <String, dynamic>{
          'id': 'a1',
          'employee_display_name': 'محمود الصيدلي',
          'check_in_at': '2026-09-11T08:00:00Z',
          'check_out_at': null,
          'duration_minutes': null,
        },
      ],
      'total': 1,
    };
  }
  if (path.endsWith('/pharmacy/branches')) {
    return <String, dynamic>{
      'branches': <dynamic>[
        <String, dynamic>{
          'id': 'b1',
          'name': 'الفرع الرئيسي',
          'code': 'MAIN',
          'phone': '0223334444',
          'city': 'القاهرة',
          'is_active': true,
        },
      ],
    };
  }
  if (path.contains('/reports/')) {
    return <String, dynamic>{
      'data': <String, dynamic>{
        'totals': <String, dynamic>{'sales_piastres': 72000, 'invoices': 10, 'units': 30},
        'daily': <dynamic>[
          <String, dynamic>{'day': '2026-09-05', 'total_piastres': 12000},
          <String, dynamic>{'day': '2026-09-06', 'total_piastres': 9000},
        ],
        'top_products': <dynamic>[
          <String, dynamic>{'name': 'بنادول اكسترا', 'units': 12, 'total_piastres': 43200},
        ],
        'inventory_value_piastres': 1500000,
        'low_stock_count': 2,
        'expiring_count': 1,
        'by_type': <dynamic>[
          <String, dynamic>{'type': 'purchase', 'count': 5, 'quantity': 120},
        ],
      },
    };
  }
  return <String, dynamic>{'data': <dynamic>[]};
}

class _MockAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = jsonEncode(_bodyFor(options.uri.path));
    return ResponseBody.fromString(
      body,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

AppState _loggedInState() {
  return AppState()
    ..user = User.fromJson(<String, dynamic>{
      'id': 'u1',
      'email': 'owner@pharmacy.eg',
      'first_name': 'صاحب',
      'last_name': 'الصيدلية',
      'display_name': 'صاحب الصيدلية',
      'role': 'OWNER',
    })
    ..context = PharmacyContext.fromJson(<String, dynamic>{
      'pharmacy': <String, dynamic>{
        'id': 'p1',
        'name': 'صيدلية الشفاء',
        'city': 'القاهرة',
        'address': 'شارع التحرير',
        'phone': '0223334444',
        'product_count': 42,
      },
      'branch': <String, dynamic>{'id': 'b1', 'name': 'الفرع الرئيسي', 'city': 'القاهرة'},
      'user': <String, dynamic>{'id': 'u1', 'role': 'OWNER'},
    })
    ..permissions = MyPermissions.fromJson(<String, dynamic>{
      'principal_type': 'pharmacy',
      'role': 'owner',
      'permissions': <String>[],
      'full_access': true,
    });
}

void _stubSecureStorage(WidgetTester tester) {
  const MethodChannel channel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    channel,
    (MethodCall call) async => null,
  );
}

Future<void> _pumpShell(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        title: 'Pharmacy OS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        locale: const Locale('ar'),
        supportedLocales: const <Locale>[Locale('ar'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const HomeScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(() {
    // كل الاختبارات تمر عبر محوّل وهمي — بلا شبكة إطلاقًا
    ApiClient.instance.dio.httpClientAdapter = _MockAdapter();
  });

  testWidgets('dashboard renders with data — no build exception (gray box)',
      (WidgetTester tester) async {
    _stubSecureStorage(tester);
    AppI18n.instance.setLocale('ar');
    await _pumpShell(tester, _loggedInState());

    final exception = tester.takeException();
    if (exception != null) fail('استثناء build: $exception');

    expect(find.text('لوحة التحكم'), findsWidgets);
    expect(find.text('42'), findsWidgets);
    expect(find.text('بنادول اكسترا 500 ملغ أقراص'), findsWidgets);
  });

  testWidgets('hamburger opens the drawer — no silent Scaffold.of crash',
      (WidgetTester tester) async {
    _stubSecureStorage(tester);
    AppI18n.instance.setLocale('ar');
    await _pumpShell(tester, _loggedInState());

    await tester.tap(find.byIcon(Icons.menu).first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    final exception = tester.takeException();
    if (exception != null) fail('استثناء عند فتح الدرج: $exception');
    expect(find.text('الصيدلية الحالية'), findsOneWidget);
  });

  testWidgets('switching through ALL shell pages throws nothing',
      (WidgetTester tester) async {
    _stubSecureStorage(tester);
    AppI18n.instance.setLocale('ar');
    await _pumpShell(tester, _loggedInState());

    final shellCtx = tester.element(find.byType(DashboardScreen));
    const keys = <String>[
      'inventory', 'pos', 'sales', 'customers', 'movements',
      'employees', 'attendance', 'branches', 'reports', 'settings',
      'dashboard',
    ];
    for (final key in keys) {
      HomeNav.go(shellCtx, key);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      final exception = tester.takeException();
      if (exception != null) fail('استثناء في صفحة «$key»: $exception');
    }
  });
}
