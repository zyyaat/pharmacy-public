#!/usr/bin/env python3
"""Task 61 — ترقيعات تحليل flutter analyze الدفعة الأولى (imports/نطاقات)."""
import os
import re

BASE = "/home/z/my-project/pharmacy-public/mobile/lib/screens"

FIXES = {
    "inventory_screen.dart": [
        ("import 'package:flutter/material.dart';", "import 'dart:async';\n\nimport 'package:flutter/material.dart';"),
        ("import '../core/theme.dart';\n", ""),
        ("it.productName.toLowerCase().contains(q) ||", "it.productName.toLowerCase().contains(q) ||"),
        ("""  String _qtyLabel(InventoryItem it) {
    final i18n = AppI18n.instance;
    if (it.quantity <= 0) return i18n.t('inventory', 'qty_out_of_stock');
    if (it.boxStrip) {
      final boxes = it.quantity;
      if (it.strips > 0) return i18n.t('inventory', 'qty_box_and_strip', {'boxes': Fmt.num(boxes), 'strips': Fmt.num(it.strips)});
      return it.quantity == 1 ? i18n.t('inventory', 'qty_boxes_only', {'count': Fmt.num(1)}) : i18n.t('inventory', 'qty_boxes_only', {'count': Fmt.num(boxes)});
    }
    return i18n.t('inventory', 'qty_strips_only', {'count': Fmt.num(it.quantity)});
  }""", """  String _qtyLabel(InventoryItem it) {
    final i18n = AppI18n.instance;
    if (it.quantity <= 0) return i18n.t('inventory', 'qty_out_of_stock');
    if (it.boxStrip) {
      return i18n.t('inventory', 'qty_boxes_only', {'count': Fmt.num(it.quantity)});
    }
    return i18n.t('inventory', 'qty_strips_only', {'count': Fmt.num(it.quantity)});
  }"""),
    ],
    "pos_screen.dart": [
        ("import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';\nimport 'package:provider/provider.dart';\n", "import 'dart:async';\n\nimport 'package:flutter/material.dart';\n"),
        ("import '../core/strings.dart';\nimport '../models/models.dart';\nimport '../state/app_state.dart';\n", "import '../core/strings.dart';\nimport '../core/theme.dart';\nimport '../models/models.dart';\n"),
        ("  _CartLine({required this.product, this.isBox = true, this.qty = 1});", "  _CartLine({required this.product, this.isBox = true, this.qty = 1});"),
        ("\n  String get unitKey => isBox ? 'unitBox' : 'unitStrips';\n", ""),
    ],
    "sales_list_screen.dart": [
        ("import 'package:flutter/material.dart';", "import 'dart:async';\n\nimport 'package:flutter/material.dart';"),
    ],
    "onboarding_screen.dart": [
        ("import '../models/models.dart';\n", ""),
        ("<TextController>[", "<TextEditingController>["),
        ("  bool _loading = true;", "  bool _loading = true;"),
    ],
    "sale_detail_screen.dart": [
        ("child: AppInput(controller: controllers[it.saleItemId], keyboard: TextInputType.number),", "child: AppInput(controller: controllers[it.saleItemId]!, keyboard: TextInputType.number),"),
        ("d.returns.isNotEmpty", "d.sale.returns.isNotEmpty"),
        ("for (final SaleReturnSummary r in d.returns)", "for (final SaleReturnSummary r in d.sale.returns)"),
        ("{ 'count': Fmt.num(d.returns.length) }", "{ 'count': Fmt.num(d.sale.returns.length) }"),
    ],
    "product_detail_screen.dart": [
        ("final i18n = AppI18n.instance;\n    final p = _product!;\n    final isAdd = await showModalBottomSheet<bool>(", "final p = _product!;\n    final isAdd = await showModalBottomSheet<bool>("),
        ("_PayChoice(", "PayChoice("),
        ("_PayChoice(", "PayChoice("),
    ],
    "product_form_screen.dart": [
        ("import '../core/strings.dart';", "import '../core/strings.dart';\nimport '../core/theme.dart';"),
    ],
    "reports_screen.dart": [
        ("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'package:provider/provider.dart';"),
        ("import '../models/models.dart';", "import '../models/models.dart';\nimport '../state/app_state.dart';"),
    ],
    "settings_receipts_screen.dart": [
        ("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'package:provider/provider.dart';"),
        ("import '../core/format.dart';\n", ""),
        ("import '../models/models.dart';", "import '../models/models.dart';\nimport '../state/app_state.dart';"),
    ],
    "settings_screen.dart": [
        ("KVRow(i18n.t('onboarding', 'city') .isEmpty ? 'المدينة' : 'المدينة',", "KVRow('المدينة',"),
    ],
    "settings_import_screen.dart": [
        ("import '../core/theme.dart';\n", ""),
    ],
    "receipt_screen.dart": [
        ("import '../core/theme.dart';\n", ""),
    ],
    "register_screen.dart": [
        ("import '../core/theme.dart';\n", ""),
    ],
    "splash_screen.dart": [
        ("import '../core/theme.dart';\n", ""),
    ],
    "movements_screen.dart": [
        ("  Future<void> _pickDate({required bool isFrom}) async {\n    final i18n = AppI18n.instance;\n", "  Future<void> _pickDate({required bool isFrom}) async {\n"),
    ],
    "product_detail_screen.dart__2": [],
}

# PayChoice تُنقل إلى ui.dart كصنف عام
UI = "/home/z/my-project/pharmacy-public/mobile/lib/widgets/ui.dart"
PAYCHOICE = '''

/// اختيار بين خيارين (نقدي/آجل، إضافة/خصم) — مستخدم في نقطة البيع والتسوية
class PayChoice extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const PayChoice({super.key, required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: AppRadius.br,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary.withOpacity(0.10) : Colors.transparent,
          borderRadius: AppRadius.br,
          border: Border.all(color: selected ? theme.colorScheme.primary : theme.dividerColor, width: selected ? 1.4 : 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 18, color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.6)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.7))),
          ],
        ),
      ),
    );
  }
}
'''

POS = os.path.join(BASE, "pos_screen.dart")
DETAIL = os.path.join(BASE, "product_detail_screen.dart")

def remove_paychoice_from_pos():
    with open(POS, encoding="utf-8") as f:
        src = f.read()
    start = src.find("class _PayChoice extends StatelessWidget {")
    if start != -1:
        end = src.find("\n}\n", start)
        end = src.find("\n", end + 1)
        src = src[:start] + src[end + 3:]
    with open(POS, "w", encoding="utf-8") as f:
        f.write(src)

def main():
    # PayChoice إلى ui.dart
    with open(UI, encoding="utf-8") as f:
        ui_src = f.read()
    if "class PayChoice" not in ui_src:
        with open(UI, "a", encoding="utf-8") as f:
            f.write(PAYCHOICE)

    for fname, patches in FIXES.items():
        if fname.endswith("__2") or not patches:
            continue
        path = os.path.join(BASE, fname)
        if not os.path.exists(path):
            print(f"SKIP missing {fname}")
            continue
        with open(path, encoding="utf-8") as f:
            src = f.read()
        for old, new in patches:
            if old in src:
                src = src.replace(old, new)
            elif old not in src and new != old:
                print(f"MISS in {fname}: {old[:60]!r}")
        with open(path, "w", encoding="utf-8") as f:
            f.write(src)
    remove_paychoice_from_pos()
    print("done")

if __name__ == "__main__":
    main()
