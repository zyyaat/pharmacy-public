// Task 72 — اختبار انحدار «شكل الزر غريب»: زر الـgradient يجب أن يحمل
// دائمًا تعبئة لون معتمة تحت التدرّج. تحليل بكسلات لقطة المستخدم أثبت
// أن رمادية الزر = ظلّاه يظهر عبر تعبئة شفافة حين يسقط رسم التدرّج
// (خلل Impeller على أندرويد مع التدرّجات داخل AnimatedContainer).
// العقد: gradient غير فارغ + color معتم بلون primary نفسه.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pharmacy_mobile/widgets/ui.dart';

void main() {
  testWidgets('WButton gradient — تعبئة معتمة تحت التدرّج (شبكة أمان Impeller)',
      (WidgetTester tester) async {
    Color? themePrimary;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (BuildContext context) {
          themePrimary = Theme.of(context).colorScheme.primary;
          return Scaffold(
            body: WButton(
              'إضافة منتج',
              icon: Icons.add,
              variant: WButtonVariant.gradient,
              onPressed: () {},
            ),
          );
        },
      ),
    ));
    await tester.pump();

    final AnimatedContainer box =
        tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    final BoxDecoration decoration = box.decoration! as BoxDecoration;

    // التدرّج موجود بخطّيه اللونين
    final LinearGradient gradient = decoration.gradient! as LinearGradient;
    expect(gradient.colors.length, 2);
    expect(gradient.colors.first, themePrimary);

    // وشبكة الأمان: تعبئة معتمة (وليست transparent) تحت التدرّج = primary
    expect(decoration.color, isNotNull,
        reason: 'بلا تعبئة معتمة يظهر ظلّ الزر عبره إن سقط التدرّج على Impeller');
    expect(decoration.color!.opacity, 1.0);
    expect(decoration.color, themePrimary);
  });
}
