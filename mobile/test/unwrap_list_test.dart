// Task 71 — اختبارات انحدار لفكّ القوائم: سبب «صفحات الموظفين/الفروع
// لا تجلب البيانات» هو أن unwrapList بمفتاح مسمّى على الردّ المسطح
// {"data":[...]} كانت تأخذ القائمة وتحاول قراءة المفتاح منها كخريطة
// فتُرجع [] دائمًا. الأشكال أدناه هي كل عقود الخادم المعروفة
// (backend/internal/handlers/*.go) ويجب أن تُفكّ كلها بلا استثناء.
import 'package:flutter_test/flutter_test.dart';

import 'package:pharmacy_mobile/models/models.dart';

void main() {
  group('unwrapList — كل أشكال رد الخادم', () {
    test('مسطح بمفتاح مسمّى: {"data":[...]} + employees (عقد الموظفين)', () {
      final body = <String, dynamic>{
        'data': <dynamic>[
          <String, dynamic>{'id': 'e1', 'email': 'a@b.c'},
          <String, dynamic>{'id': 'e2'},
        ],
        'total': 2,
      };
      final list = unwrapList(body, 'employees');
      expect(list.length, 2);
      expect(mOf(list.first)['id'], 'e1');
    });

    test('مسطح بمفتاح مسمّى: branches (نفس العقد)', () {
      final body = <String, dynamic>{
        'data': <dynamic>[<String, dynamic>{'id': 'b1', 'is_main': true}],
        'total': 1,
      };
      expect(unwrapList(body, 'branches').length, 1);
    });

    test('متداخل بمفتاح: {"data":{"customers":[...]}} (عقد العملاء)', () {
      final body = <String, dynamic>{
        'data': <String, dynamic>{
          'customers': <dynamic>[<String, dynamic>{'id': 'c1'}],
        },
      };
      expect(unwrapList(body, 'customers').length, 1);
    });

    test('متداخل بـ items: {"data":{"items":[...]}} (سجل الترحيلات)', () {
      final body = <String, dynamic>{
        'data': <String, dynamic>{
          'items': <dynamic>[<String, dynamic>{'version': '0001'}],
          'total': 1,
        },
      };
      expect(unwrapList(body).length, 1);
    });

    test('مسطح بلا مفتاح: {"data":[...]} (المخزون/المنتجات/النشاط)', () {
      final body = <String, dynamic>{'data': <dynamic>[1, 2, 3]};
      expect(unwrapList(body).length, 3);
    });

    test('قديم بمفتاح أعلى: {"branches":[...]}', () {
      final body = <String, dynamic>{
        'branches': <dynamic>[<String, dynamic>{'id': 'b9'}],
      };
      expect(unwrapList(body, 'branches').length, 1);
    });

    test('جسم غير معروف → قائمة فارغة لا استثناء', () {
      expect(unwrapList(<String, dynamic>{}), isEmpty);
      expect(unwrapList(<String, dynamic>{'data': null}), isEmpty);
      expect(
        unwrapList(<String, dynamic>{'data': <String, dynamic>{}}, 'x'),
        isEmpty,
      );
    });

    test('Employee.fromJson يقرأ حقول عقد /pharmacy/employees كاملة', () {
      final e = Employee.fromJson(mOf(<String, dynamic>{
        'id': '1', 'first_name': 'أحمد', 'last_name': 'سيد',
        'display_name': 'أحمد سيد', 'email': 'a@b.c', 'phone': '010',
        'job_title': 'صيدلي', 'status': 'active', 'branch_id': '7',
        'branch_name': 'الفرع الرئيسي', 'created_at': '2026-01-01T00:00:00Z',
      }));
      expect(e.displayName, 'أحمد سيد');
      expect(e.email, 'a@b.c');
      expect(e.jobTitle, 'صيدلي');
      expect(e.branchName, 'الفرع الرئيسي');
      expect(e.status, 'active');
    });

    test('Branch.fromJson يقرأ حقول عقد /pharmacy/branches كاملة', () {
      final b = Branch.fromJson(mOf(<String, dynamic>{
        'id': '2', 'name': 'الرئيسي', 'code': 'BR1', 'phone': '011',
        'email': 'br@x.y', 'address': 'شارع 1', 'city': 'القاهرة',
        'is_active': true, 'manager_name': 'منير', 'is_main': true,
        'pharmacy_name': 'صيدلية النور',
      }));
      expect(b.name, 'الرئيسي');
      expect(b.code, 'BR1');
      expect(b.isMain, isTrue);
      expect(b.managerName, 'منير');
      expect(b.pharmacyName, 'صيدلية النور');
    });
  });
}
