/// Task 61 — نماذج البيانات الكاملة: نسخة موبايل من كل interfaces في
/// lib/api.ts بالويب. تحليل دفاعي: أي مفتاح ناقص لا يرمي استثناء أبدًا.
// ignore_for_file: non_constant_identifier_names

// ------------------------------------------------------------- أدوات تحليل

Map<String, dynamic> mOf(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<dynamic> lOf(dynamic v) => v is List ? v : const <dynamic>[];

String sOf(dynamic v, [String def = '']) {
  if (v == null) return def;
  if (v is String) return v;
  return v.toString();
}

int iOf(dynamic v, [int def = 0]) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) {
    final p = int.tryParse(v) ?? double.tryParse(v)?.round();
    if (p != null) return p;
  }
  return def;
}

bool bOf(dynamic v, [bool def = false]) {
  if (v is bool) return v;
  if (v is String) return v == 'true' || v == '1';
  return def;
}

double dOf(dynamic v, [double def = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? def;
  return def;
}

/// يفك غلاف {"data": ...} إن وُجد — بعض نقاط النهاية تلف والبعض لا.
Map<String, dynamic> unwrapMap(Map<String, dynamic> body) {
  if (body.containsKey('data') && body['data'] is Map) return mOf(body['data']);
  return body;
}

List<dynamic> unwrapList(Map<String, dynamic> body, [String? key]) {
  if (key != null) {
    final inner = body.containsKey('data') ? body['data'] : body;
    return lOf(mOf(inner)[key]);
  }
  if (body['data'] is List) return lOf(body['data']);
  return const <dynamic>[];
}

// ------------------------------------------------------------- الجلسة

class User {
  final String id;
  final String email;
  final String firstName;
  final String lastName;
  final String displayName;
  final String role;
  User({required this.id, required this.email, required this.firstName,
      required this.lastName, required this.displayName, required this.role});

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: sOf(j['id']),
        email: sOf(j['email']),
        firstName: sOf(j['first_name']),
        lastName: sOf(j['last_name']),
        displayName: sOf(j['display_name'], sOf(j['first_name'])),
        role: sOf(j['role']),
      );
}

// ------------------------------------------------------------- السياق

class PharmacyContext {
  final String pharmacyId, pharmacyName, city, address, phone;
  final int productCount;
  final String? branchId, branchName, branchCity;
  final User user;
  PharmacyContext({required this.pharmacyId, required this.pharmacyName,
      required this.city, required this.address, required this.phone,
      required this.productCount, this.branchId, this.branchName, this.branchCity,
      required this.user});

  factory PharmacyContext.fromJson(Map<String, dynamic> j) {
    final p = mOf(j['pharmacy']);
    final b = j['branch'] is Map ? mOf(j['branch']) : null;
    return PharmacyContext(
      pharmacyId: sOf(p['id']),
      pharmacyName: sOf(p['name']),
      city: sOf(p['city']),
      address: sOf(p['address']),
      phone: sOf(p['phone']),
      productCount: iOf(p['product_count']),
      branchId: b == null ? null : sOf(b['id']),
      branchName: b == null ? null : sOf(b['name']),
      branchCity: b == null ? null : sOf(b['city']),
      user: User.fromJson(mOf(j['user'])),
    );
  }
}

// ------------------------------------------------------------- اللوحة

class DashboardStats {
  final int totalProducts, lowStockCount, activeEmployees, activeToday, salesUnitsToday;
  final List<DashboardLowStock> lowStockItems;
  DashboardStats({required this.totalProducts, required this.lowStockCount,
      required this.activeEmployees, required this.activeToday,
      required this.salesUnitsToday, required this.lowStockItems});

  factory DashboardStats.fromJson(Map<String, dynamic> j) => DashboardStats(
        totalProducts: iOf(j['totalProducts']),
        lowStockCount: iOf(j['lowStockCount']),
        activeEmployees: iOf(j['activeEmployees']),
        activeToday: iOf(j['activeToday']),
        salesUnitsToday: iOf(j['salesUnitsToday']),
        lowStockItems: lOf(j['lowStockItems'])
            .whereType<Map>()
            .map((e) => DashboardLowStock.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class DashboardLowStock {
  final String name, genericName, status;
  final int quantity, strips, minStockLevel;
  DashboardLowStock({required this.name, required this.genericName,
      required this.status, required this.quantity, required this.strips,
      required this.minStockLevel});

  factory DashboardLowStock.fromJson(Map<String, dynamic> j) => DashboardLowStock(
        name: sOf(j['name']),
        genericName: sOf(j['generic_name']),
        status: sOf(j['status']),
        quantity: iOf(j['quantity']),
        strips: iOf(j['strips']),
        minStockLevel: iOf(j['min_stock_level']),
      );
}

class ActivityItem {
  final String id, type, description, userName, timestamp;
  ActivityItem({required this.id, required this.type, required this.description,
      required this.userName, required this.timestamp});

  factory ActivityItem.fromJson(Map<String, dynamic> j) => ActivityItem(
        id: sOf(j['id']),
        type: sOf(j['type'], sOf(j['action'])),
        description: sOf(j['description'], sOf(j['changes_summary'], sOf(j['action']))),
        userName: sOf(j['user_name'], sOf(j['actor_display_name'], 'System')),
        timestamp: sOf(j['timestamp'], sOf(j['created_at'])),
      );
}

// ------------------------------------------------------------- المخزون

class InventoryItem {
  final String batchId, pharmacyProductId, productName, genericName, brandName;
  final String barcode, dosageForm, strength, batchNumber, unit, branchName, status;
  final int quantity, costPerUnitPiastres, sellingPricePiastres, partialSellingPricePiastres;
  final int unitsPerBox, minStockLevel;
  final String? expiryDate;
  final int? daysUntilExpiry;
  final String packagingType; // WHOLE_ONLY | BOX_STRIP
  final bool boxStrip;
  InventoryItem({required this.batchId, required this.pharmacyProductId,
      required this.productName, required this.genericName, required this.brandName,
      required this.barcode, required this.dosageForm, required this.strength,
      required this.batchNumber, required this.unit, required this.branchName,
      required this.status, required this.quantity, required this.costPerUnitPiastres,
      required this.sellingPricePiastres, required this.partialSellingPricePiastres,
      required this.unitsPerBox, required this.minStockLevel, this.expiryDate,
      this.daysUntilExpiry, required this.packagingType})
      : boxStrip = packagingType == 'BOX_STRIP';

  factory InventoryItem.fromJson(Map<String, dynamic> j) => InventoryItem(
        batchId: sOf(j['batch_id']),
        pharmacyProductId: sOf(j['pharmacy_product_id']),
        productName: sOf(j['product_name']),
        genericName: sOf(j['generic_name']),
        brandName: sOf(j['brand_name']),
        barcode: sOf(j['barcode']),
        dosageForm: sOf(j['dosage_form']),
        strength: sOf(j['strength']),
        batchNumber: sOf(j['batch_number']),
        unit: sOf(j['unit']),
        branchName: sOf(j['branch_name']),
        status: sOf(j['status']),
        quantity: iOf(j['quantity']),
        costPerUnitPiastres: iOf(j['cost_per_unit_piastres']),
        sellingPricePiastres: iOf(j['selling_price_piastres']),
        partialSellingPricePiastres: iOf(j['partial_selling_price_piastres']),
        unitsPerBox: iOf(j['units_per_box'], 1),
        minStockLevel: iOf(j['min_stock_level']),
        expiryDate: j['expiry_date'] == null ? null : sOf(j['expiry_date']),
        daysUntilExpiry: j['days_until_expiry'] == null ? null : iOf(j['days_until_expiry']),
        packagingType: sOf(j['packaging_type'], 'WHOLE_ONLY'),
      );
}

class Product {
  final String id, name, genericName, strength, barcode, packagingType;
  final int unitsPerBox, sellingPricePiastres, partialSellingPricePiastres, stock;
  final bool boxStrip;
  Product({required this.id, required this.name, required this.genericName,
      required this.strength, required this.barcode, required this.packagingType,
      required this.unitsPerBox, required this.sellingPricePiastres,
      required this.partialSellingPricePiastres, required this.stock})
      : boxStrip = packagingType == 'BOX_STRIP';

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: sOf(j['id'], sOf(j['pharmacy_product_id'])),
        name: sOf(j['name']),
        genericName: sOf(j['generic_name']),
        strength: sOf(j['strength']),
        barcode: sOf(j['barcode']),
        packagingType: sOf(j['packaging_type'], 'WHOLE_ONLY'),
        unitsPerBox: iOf(j['units_per_box'], 1),
        sellingPricePiastres: iOf(j['selling_price_piastres']),
        partialSellingPricePiastres: iOf(j['partial_selling_price_piastres']),
        stock: iOf(j['stock']),
      );
}

class ProductDetail {
  final String id, name, genericName, strength, barcode, dosageForm, packagingType;
  final int unitsPerBox, costPricePiastres, sellingPricePiastres, partialSellingPricePiastres, minStockLevel, stock;
  final bool isActive, boxStrip;
  ProductDetail({required this.id, required this.name, required this.genericName,
      required this.strength, required this.barcode, required this.dosageForm,
      required this.packagingType, required this.unitsPerBox,
      required this.costPricePiastres, required this.sellingPricePiastres,
      required this.partialSellingPricePiastres, required this.minStockLevel,
      required this.stock, required this.isActive})
      : boxStrip = packagingType == 'BOX_STRIP';

  factory ProductDetail.fromJson(Map<String, dynamic> j) => ProductDetail(
        id: sOf(j['id']),
        name: sOf(j['name']),
        genericName: sOf(j['generic_name']),
        strength: sOf(j['strength']),
        barcode: sOf(j['barcode']),
        dosageForm: sOf(j['dosage_form']),
        packagingType: sOf(j['packaging_type'], 'WHOLE_ONLY'),
        unitsPerBox: iOf(j['units_per_box'], 1),
        costPricePiastres: iOf(j['cost_price_piastres']),
        sellingPricePiastres: iOf(j['selling_price_piastres']),
        partialSellingPricePiastres: iOf(j['partial_selling_price_piastres']),
        minStockLevel: iOf(j['min_stock_level']),
        stock: iOf(j['stock']),
        isActive: bOf(j['is_active'], true),
      );
}

class LowStockItem {
  final String pharmacyProductId, productName, strength, barcode, packagingType;
  final int unitsPerBox, fullBoxes, strips, minStockLevel;
  LowStockItem({required this.pharmacyProductId, required this.productName,
      required this.strength, required this.barcode, required this.packagingType,
      required this.unitsPerBox, required this.fullBoxes, required this.strips,
      required this.minStockLevel});

  factory LowStockItem.fromJson(Map<String, dynamic> j) => LowStockItem(
        pharmacyProductId: sOf(j['pharmacy_product_id']),
        productName: sOf(j['product_name']),
        strength: sOf(j['strength']),
        barcode: sOf(j['barcode']),
        packagingType: sOf(j['packaging_type'], 'WHOLE_ONLY'),
        unitsPerBox: iOf(j['units_per_box'], 1),
        fullBoxes: iOf(j['full_boxes']),
        strips: iOf(j['strips']),
        minStockLevel: iOf(j['min_stock_level']),
      );
}

// ------------------------------------------------------------- العملاء

class Customer {
  final String id, name, phone;
  final int balancePiastres;
  final String? createdAt;
  Customer({required this.id, required this.name, required this.phone,
      required this.balancePiastres, this.createdAt});

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: sOf(j['id']),
        name: sOf(j['name']),
        phone: sOf(j['phone']),
        balancePiastres: iOf(j['balance_piastres'], iOf(j['balance'])),
        createdAt: j['created_at'] == null ? null : sOf(j['created_at']),
      );
}

class StatementEntry {
  final String kind, id;
  final int? invoiceNumber;
  final int amountPiastres, returnedAmountPiastres, dueAmountPiastres, balancePiastres;
  final String? note, status;
  final String createdAt;
  StatementEntry({required this.kind, required this.id, this.invoiceNumber,
      required this.amountPiastres, required this.returnedAmountPiastres,
      required this.dueAmountPiastres, required this.balancePiastres,
      this.note, this.status, required this.createdAt});

  bool get isPayment => kind == 'payment';

  factory StatementEntry.fromJson(Map<String, dynamic> j) => StatementEntry(
        kind: sOf(j['kind']),
        id: sOf(j['id']),
        invoiceNumber: j['invoice_number'] == null ? null : iOf(j['invoice_number']),
        amountPiastres: iOf(j['amount_piastres']),
        returnedAmountPiastres: iOf(j['returned_amount_piastres']),
        dueAmountPiastres: iOf(j['due_amount_piastres']),
        balancePiastres: iOf(j['balance_piastres']),
        note: j['note'] == null ? null : sOf(j['note']),
        status: j['status'] == null ? null : sOf(j['status']),
        createdAt: sOf(j['created_at']),
      );
}

class CustomerStatement {
  final Customer customer;
  final List<StatementEntry> entries;
  final int balancePiastres;
  CustomerStatement({required this.customer, required this.entries, required this.balancePiastres});

  factory CustomerStatement.fromJson(Map<String, dynamic> j) => CustomerStatement(
        customer: Customer.fromJson(mOf(j['customer'])),
        entries: lOf(j['entries']).map((e) => StatementEntry.fromJson(mOf(e))).toList(),
        balancePiastres: iOf(j['balance_piastres']),
      );
}

// ------------------------------------------------------------- نقطة البيع والمبيعات

class SaleSummary {
  final String id;
  final int invoiceNumber, totalAmountPiastres, discountAmountPiastres;
  final int productsCount, totalQuantityBase, returnedAmountPiastres;
  final String status, paymentType, customerName, createdAt;
  final List<SaleReturnSummary> returns;
  SaleSummary({required this.id, required this.invoiceNumber, required this.status,
      required this.totalAmountPiastres, required this.discountAmountPiastres,
      required this.paymentType, required this.customerName, required this.createdAt,
      required this.productsCount, required this.totalQuantityBase,
      required this.returnedAmountPiastres, required this.returns});

  factory SaleSummary.fromJson(Map<String, dynamic> j) => SaleSummary(
        id: sOf(j['id']),
        invoiceNumber: iOf(j['invoice_number']),
        status: sOf(j['status'], 'completed'),
        totalAmountPiastres: iOf(j['total_amount_piastres']),
        discountAmountPiastres: iOf(j['discount_amount_piastres']),
        paymentType: sOf(j['payment_type'], 'cash'),
        customerName: sOf(j['customer_name']),
        createdAt: sOf(j['created_at']),
        productsCount: iOf(j['products_count']),
        totalQuantityBase: iOf(j['total_quantity_base']),
        returnedAmountPiastres: iOf(j['returned_amount_piastres']),
        returns: lOf(j['returns']).map((e) => SaleReturnSummary.fromJson(mOf(e))).toList(),
      );
}

class SaleReturnSummary {
  final String id, reason, createdAt;
  final int returnNumber, totalAmountPiastres, quantityBase;
  SaleReturnSummary({required this.id, required this.reason, required this.createdAt,
      required this.returnNumber, required this.totalAmountPiastres, required this.quantityBase});

  factory SaleReturnSummary.fromJson(Map<String, dynamic> j) => SaleReturnSummary(
        id: sOf(j['id']),
        reason: sOf(j['reason']),
        createdAt: sOf(j['created_at']),
        returnNumber: iOf(j['return_number']),
        totalAmountPiastres: iOf(j['total_amount_piastres']),
        quantityBase: iOf(j['quantity_base']),
      );
}

class SaleItemRow {
  final String saleItemId, productId, productName, genericName, strength, barcode;
  final String packagingType, saleUnit, batchNumber;
  final int unitsPerBox, quantityBase, unitPricePiastres, amountPiastres;
  final int returnedQuantityBase, returnableQuantityBase, returnedAmountPiastres;
  SaleItemRow({required this.saleItemId, required this.productId, required this.productName,
      required this.genericName, required this.strength, required this.barcode,
      required this.packagingType, required this.saleUnit, required this.batchNumber,
      required this.unitsPerBox, required this.quantityBase, required this.unitPricePiastres,
      required this.amountPiastres, required this.returnedQuantityBase,
      required this.returnableQuantityBase, required this.returnedAmountPiastres});

  factory SaleItemRow.fromJson(Map<String, dynamic> j) => SaleItemRow(
        saleItemId: sOf(j['sale_item_id']),
        productId: sOf(j['pharmacy_product_id']),
        productName: sOf(j['product_name']),
        genericName: sOf(j['generic_name']),
        strength: sOf(j['strength']),
        barcode: sOf(j['barcode']),
        packagingType: sOf(j['packaging_type'], 'WHOLE_ONLY'),
        saleUnit: sOf(j['sale_unit'], 'box'),
        batchNumber: sOf(j['batch_number']),
        unitsPerBox: iOf(j['units_per_box'], 1),
        quantityBase: iOf(j['quantity_base']),
        unitPricePiastres: iOf(j['unit_price_piastres']),
        amountPiastres: iOf(j['amount_piastres']),
        returnedQuantityBase: iOf(j['returned_quantity_base']),
        returnableQuantityBase: iOf(j['returnable_quantity_base']),
        returnedAmountPiastres: iOf(j['returned_amount_piastres']),
      );
}

class SaleDetail {
  final SaleSummary sale;
  final List<SaleItemRow> items;
  SaleDetail({required this.sale, required this.items});

  factory SaleDetail.fromJson(Map<String, dynamic> j) => SaleDetail(
        sale: SaleSummary.fromJson(mOf(j['sale'])),
        items: lOf(j['items']).map((e) => SaleItemRow.fromJson(mOf(e))).toList(),
      );
}

class PriceChangedItem {
  final int index;
  final String productId, saleUnit;
  final int quantity, unitPricePiastres, lineTotalPiastres;
  PriceChangedItem({required this.index, required this.productId, required this.saleUnit,
      required this.quantity, required this.unitPricePiastres, required this.lineTotalPiastres});

  factory PriceChangedItem.fromJson(Map<String, dynamic> j) => PriceChangedItem(
        index: iOf(j['index']),
        productId: sOf(j['pharmacy_product_id']),
        saleUnit: sOf(j['sale_unit'], 'box'),
        quantity: iOf(j['quantity']),
        unitPricePiastres: iOf(j['unit_price_piastres']),
        lineTotalPiastres: iOf(j['line_total_piastres']),
      );
}

// ------------------------------------------------------------- حركات المخزون

class StockMovementRow {
  final String id, movementType, productName;
  final int quantity;
  final String unit, createdAt;
  final String? genericName, batchNumber, branchName, actorName, referenceType, reason, notes;
  final int? quantityAfter;
  StockMovementRow({required this.id, required this.movementType, required this.productName,
      required this.quantity, required this.unit, required this.createdAt,
      this.genericName, this.batchNumber, this.branchName, this.actorName,
      this.referenceType, this.reason, this.notes, this.quantityAfter});

  factory StockMovementRow.fromJson(Map<String, dynamic> j) => StockMovementRow(
        id: sOf(j['id']),
        movementType: sOf(j['movement_type']),
        productName: sOf(j['product_name']),
        quantity: iOf(j['quantity']),
        unit: sOf(j['unit']),
        createdAt: sOf(j['created_at']),
        genericName: j['generic_name'] == null ? null : sOf(j['generic_name']),
        batchNumber: j['batch_number'] == null ? null : sOf(j['batch_number']),
        branchName: j['branch_name'] == null ? null : sOf(j['branch_name']),
        actorName: j['actor_name'] == null ? null : sOf(j['actor_name']),
        referenceType: j['reference_type'] == null ? null : sOf(j['reference_type']),
        reason: j['reason'] == null ? null : sOf(j['reason']),
        notes: j['notes'] == null ? null : sOf(j['notes']),
        quantityAfter: j['quantity_after'] == null ? null : iOf(j['quantity_after']),
      );
}

// ------------------------------------------------------------- التقارير

class SalesReport {
  final int invoicesCount, grossPiastres, unitsBase, returnsCount, returnedPiastres, netPiastres, avgInvoicePiastres;
  final List<({String day, int invoices, int gross, int returned, int net})> daily;
  final List<({String productId, String name, String genericName, int qtyBase, int amount})> topProducts;
  SalesReport({required this.invoicesCount, required this.grossPiastres, required this.unitsBase,
      required this.returnsCount, required this.returnedPiastres, required this.netPiastres,
      required this.avgInvoicePiastres, required this.daily, required this.topProducts});

  factory SalesReport.fromJson(Map<String, dynamic> j) {
    final s = mOf(j['sales']);
    return SalesReport(
      invoicesCount: iOf(s['invoices_count']),
      grossPiastres: iOf(s['gross_piastres']),
      unitsBase: iOf(s['units_base']),
      returnsCount: iOf(s['returns_count']),
      returnedPiastres: iOf(s['returned_piastres']),
      netPiastres: iOf(s['net_piastres']),
      avgInvoicePiastres: iOf(s['avg_invoice_piastres']),
      daily: lOf(j['daily']).map((e) {
        final m = mOf(e);
        return (
          day: sOf(m['day']),
          invoices: iOf(m['invoices_count']),
          gross: iOf(m['gross_piastres']),
          returned: iOf(m['returned_piastres']),
          net: iOf(m['net_piastres']),
        );
      }).toList(),
      topProducts: lOf(j['top_products']).map((e) {
        final m = mOf(e);
        return (
          productId: sOf(m['product_id']),
          name: sOf(m['name']),
          genericName: sOf(m['generic_name']),
          qtyBase: iOf(m['quantity_base']),
          amount: iOf(m['amount_piastres']),
        );
      }).toList(),
    );
  }
}

class InventoryAlertItem {
  final String name, genericName, batchNumber, branchName, status;
  final int quantity, threshold, sellingPricePiastres;
  final String? extraDate;
  InventoryAlertItem({required this.name, required this.genericName, required this.batchNumber,
      required this.branchName, required this.quantity, required this.threshold,
      required this.sellingPricePiastres, required this.status, this.extraDate});

  factory InventoryAlertItem.fromJson(Map<String, dynamic> j) => InventoryAlertItem(
        name: sOf(j['name']),
        genericName: sOf(j['generic_name']),
        batchNumber: sOf(j['batch_number']),
        branchName: sOf(j['branch_name']),
        quantity: iOf(j['quantity']),
        threshold: iOf(j['threshold']),
        sellingPricePiastres: iOf(j['selling_price_piastres']),
        status: sOf(j['status']),
        extraDate: j['extra_date'] == null ? null : sOf(j['extra_date']),
      );
}

class InventoryReport {
  final int batchesCount, productsCount, unitsBase, costValue, retailValue, lowStockCount, outOfStockCount;
  final int expiredCount, expiring30, expiring60, expiring90, expiredValue, expiringValue;
  final List<InventoryAlertItem> lowStockItems, expiringItems;
  InventoryReport({required this.batchesCount, required this.productsCount, required this.unitsBase,
      required this.costValue, required this.retailValue, required this.lowStockCount,
      required this.outOfStockCount, required this.expiredCount, required this.expiring30,
      required this.expiring60, required this.expiring90, required this.expiredValue,
      required this.expiringValue, required this.lowStockItems, required this.expiringItems});

  factory InventoryReport.fromJson(Map<String, dynamic> j) {
    final t = mOf(j['totals']);
    final ex = mOf(j['expiry']);
    return InventoryReport(
      batchesCount: iOf(t['batches_count']),
      productsCount: iOf(t['products_count']),
      unitsBase: iOf(t['units_base']),
      costValue: iOf(t['cost_value_piastres']),
      retailValue: iOf(t['retail_value_piastres']),
      lowStockCount: iOf(t['low_stock_count']),
      outOfStockCount: iOf(t['out_of_stock_count']),
      expiredCount: iOf(ex['expired_count']),
      expiring30: iOf(ex['expiring_30_count']),
      expiring60: iOf(ex['expiring_60_count']),
      expiring90: iOf(ex['expiring_90_count']),
      expiredValue: iOf(ex['expired_value_piastres']),
      expiringValue: iOf(ex['expiring_value_piastres']),
      lowStockItems: lOf(j['low_stock_items']).map((e) => InventoryAlertItem.fromJson(mOf(e))).toList(),
      expiringItems: lOf(j['expiring_items']).map((e) => InventoryAlertItem.fromJson(mOf(e))).toList(),
    );
  }
}

class MovementsReport {
  final int transactions, quantityIn, quantityOut;
  final List<({String type, int tx, int qtyIn, int qtyOut})> byType;
  MovementsReport({required this.transactions, required this.quantityIn, required this.quantityOut,
      required this.byType});

  factory MovementsReport.fromJson(Map<String, dynamic> j) {
    final t = mOf(j['totals']);
    return MovementsReport(
      transactions: iOf(t['transactions']),
      quantityIn: iOf(t['quantity_in']),
      quantityOut: iOf(t['quantity_out']),
      byType: lOf(j['by_type']).map((e) {
        final m = mOf(e);
        return (
          type: sOf(m['movement_type']),
          tx: iOf(m['transactions']),
          qtyIn: iOf(m['quantity_in']),
          qtyOut: iOf(m['quantity_out']),
        );
      }).toList(),
    );
  }
}

// ------------------------------------------------------------- الموظفون والصلاحيات

class Employee {
  final String id, firstName, lastName, displayName, email, phone, jobTitle, status;
  final String? role, branchId, branchName, createdAt;
  Employee({required this.id, required this.firstName, required this.lastName,
      required this.displayName, required this.email, required this.phone,
      required this.jobTitle, required this.status, this.role, this.branchId,
      this.branchName, this.createdAt});

  factory Employee.fromJson(Map<String, dynamic> j) => Employee(
        id: sOf(j['id']),
        firstName: sOf(j['first_name']),
        lastName: sOf(j['last_name']),
        displayName: sOf(j['display_name'], '${sOf(j['first_name'])} ${sOf(j['last_name'])}'.trim()),
        email: sOf(j['email']),
        phone: sOf(j['phone']),
        jobTitle: sOf(j['job_title']),
        status: sOf(j['status'], 'active'),
        role: j['role'] == null ? null : sOf(j['role']),
        branchId: j['branch_id'] == null ? null : sOf(j['branch_id']),
        branchName: j['branch_name'] == null ? null : sOf(j['branch_name']),
        createdAt: j['created_at'] == null ? null : sOf(j['created_at']),
      );
}

class PermissionModule {
  final String module, label;
  final List<({String key, String nameAr, String category})> permissions;
  PermissionModule({required this.module, required this.label, required this.permissions});

  factory PermissionModule.fromJson(Map<String, dynamic> j) => PermissionModule(
        module: sOf(j['module']),
        label: sOf(j['label']),
        permissions: lOf(j['permissions']).map((e) {
          final m = mOf(e);
          return (key: sOf(m['key']), nameAr: sOf(m['name_ar'], sOf(m['name'])), category: sOf(m['category']));
        }).toList(),
      );
}

class PermissionTemplate {
  final String id, name, displayName, displayNameAr, descriptionAr;
  final bool isSystem;
  final List<String> permissions;
  PermissionTemplate({required this.id, required this.name, required this.displayName,
      required this.displayNameAr, required this.descriptionAr, required this.isSystem,
      required this.permissions});

  factory PermissionTemplate.fromJson(Map<String, dynamic> j) => PermissionTemplate(
        id: sOf(j['id']),
        name: sOf(j['name']),
        displayName: sOf(j['display_name']),
        displayNameAr: sOf(j['display_name_ar']),
        descriptionAr: sOf(j['description_ar']),
        isSystem: bOf(j['is_system']),
        permissions: lOf(j['permissions']).map((e) => e.toString()).toList(),
      );
}

class MyPermissions {
  final String principalType, role;
  final List<String> permissions;
  final bool fullAccess;
  MyPermissions({required this.principalType, required this.role, required this.permissions,
      required this.fullAccess});

  bool can(String key) => fullAccess || permissions.contains(key);
  bool canAny(List<String> keys) => fullAccess || keys.any(permissions.contains);

  factory MyPermissions.fromJson(Map<String, dynamic> j) => MyPermissions(
        principalType: sOf(j['principal_type']),
        role: sOf(j['role']),
        permissions: lOf(j['permissions']).map((e) => e.toString()).toList(),
        fullAccess: bOf(j['full_access']),
      );
}

class EmployeePermissions {
  final String employeeId, displayName, email;
  final List<String> permissions;
  final bool hasExplicit, fullAccess;
  EmployeePermissions({required this.employeeId, required this.displayName, required this.email,
      required this.permissions, required this.hasExplicit, required this.fullAccess});

  factory EmployeePermissions.fromJson(Map<String, dynamic> j) => EmployeePermissions(
        employeeId: sOf(j['employee_id']),
        displayName: sOf(j['display_name']),
        email: sOf(j['email']),
        permissions: lOf(j['permissions']).map((e) => e.toString()).toList(),
        hasExplicit: bOf(j['has_explicit']),
        fullAccess: bOf(j['full_access']),
      );
}

// ------------------------------------------------------------- الفروع والحضور

class Branch {
  final String id, name, code, phone, email, address, city, managerName;
  final bool isActive, isMain;
  final String? pharmacyName;
  Branch({required this.id, required this.name, required this.code, required this.phone,
      required this.email, required this.address, required this.city,
      required this.managerName, required this.isActive, required this.isMain,
      this.pharmacyName});

  factory Branch.fromJson(Map<String, dynamic> j) => Branch(
        id: sOf(j['id']),
        name: sOf(j['name']),
        code: sOf(j['code']),
        phone: sOf(j['phone']),
        email: sOf(j['email']),
        address: sOf(j['address']),
        city: sOf(j['city']),
        managerName: sOf(j['manager_name']),
        isActive: bOf(j['is_active'], true),
        isMain: bOf(j['is_main']),
        pharmacyName: j['pharmacy_name'] == null ? null : sOf(j['pharmacy_name']),
      );
}

class AttendanceRow {
  final String id, employeeId, employeeName, branchId, branchName, status;
  final String clockIn;
  final String? clockOut;
  final int? totalMinutes;
  AttendanceRow({required this.id, required this.employeeId, required this.employeeName,
      required this.branchId, required this.branchName, required this.status,
      required this.clockIn, this.clockOut, this.totalMinutes});

  factory AttendanceRow.fromJson(Map<String, dynamic> j) => AttendanceRow(
        id: sOf(j['id']),
        employeeId: sOf(j['employee_id']),
        employeeName: sOf(j['employee_name']),
        branchId: sOf(j['branch_id']),
        branchName: sOf(j['branch_name']),
        status: sOf(j['status']),
        clockIn: sOf(j['clock_in']),
        clockOut: j['clock_out'] == null ? null : sOf(j['clock_out']),
        totalMinutes: j['total_minutes'] == null ? null : iOf(j['total_minutes']),
      );
}

// ------------------------------------------------------------- الإعدادات

class ReceiptSettings {
  final int paperWidthMm; // 58 | 80
  final String printMode; // auto | manual
  final int copies; // 1 | 2
  final String namePrefix, thankYouText, returnPolicyText;
  final bool showPhone, showAddress, showCashier, showThankYou, showReturnPolicy;
  ReceiptSettings({required this.paperWidthMm, required this.printMode, required this.copies,
      required this.namePrefix, required this.thankYouText, required this.returnPolicyText,
      required this.showPhone, required this.showAddress, required this.showCashier,
      required this.showThankYou, required this.showReturnPolicy});

  Map<String, dynamic> toPayload() => <String, dynamic>{
        'paper_width_mm': paperWidthMm,
        'print_mode': printMode,
        'copies': copies,
        'name_prefix': namePrefix,
        'show_phone': showPhone,
        'show_address': showAddress,
        'show_cashier': showCashier,
        'show_thank_you': showThankYou,
        'thank_you_text': thankYouText,
        'show_return_policy': showReturnPolicy,
        'return_policy_text': returnPolicyText,
      };

  factory ReceiptSettings.fromJson(Map<String, dynamic> j) => ReceiptSettings(
        paperWidthMm: iOf(j['paper_width_mm'], 80),
        printMode: sOf(j['print_mode'], 'auto'),
        copies: iOf(j['copies'], 1),
        namePrefix: sOf(j['name_prefix']),
        thankYouText: sOf(j['thank_you_text']),
        returnPolicyText: sOf(j['return_policy_text']),
        showPhone: bOf(j['show_phone']),
        showAddress: bOf(j['show_address']),
        showCashier: bOf(j['show_cashier']),
        showThankYou: bOf(j['show_thank_you']),
        showReturnPolicy: bOf(j['show_return_policy']),
      );
}

class MigrationItem {
  final String version, appliedAt;
  MigrationItem({required this.version, required this.appliedAt});

  factory MigrationItem.fromJson(Map<String, dynamic> j) =>
      MigrationItem(version: sOf(j['version']), appliedAt: sOf(j['applied_at']));
}

// ------------------------------------------------------------- الإعداد والتوريد

class OnboardingProfile {
  final String name, phone, website, addressLine1, addressLine2, city, stateProvince, postalCode, country;
  OnboardingProfile({required this.name, required this.phone, required this.website,
      required this.addressLine1, required this.addressLine2, required this.city,
      required this.stateProvince, required this.postalCode, required this.country});

  factory OnboardingProfile.fromJson(Map<String, dynamic> j) => OnboardingProfile(
        name: sOf(j['name']),
        phone: sOf(j['phone']),
        website: sOf(j['website']),
        addressLine1: sOf(j['address_line1']),
        addressLine2: sOf(j['address_line2']),
        city: sOf(j['city']),
        stateProvince: sOf(j['state_province']),
        postalCode: sOf(j['postal_code']),
        country: sOf(j['country']),
      );
}

class OnboardingState {
  final bool onboardingRequired;
  final OnboardingProfile pharmacy;
  OnboardingState({required this.onboardingRequired, required this.pharmacy});

  factory OnboardingState.fromJson(Map<String, dynamic> j) => OnboardingState(
        onboardingRequired: bOf(j['onboarding_required']),
        pharmacy: OnboardingProfile.fromJson(mOf(j['pharmacy'])),
      );
}

class ImportPreview {
  final String fileType;
  final int totalRows, validEstimate, invalidEstimate, maxRows;
  final List<String> headers;
  final Map<String, int> mapping;
  final List<List<String>> rows;
  ImportPreview({required this.fileType, required this.totalRows, required this.validEstimate,
      required this.invalidEstimate, required this.maxRows, required this.headers,
      required this.mapping, required this.rows});

  factory ImportPreview.fromJson(Map<String, dynamic> j) => ImportPreview(
        fileType: sOf(j['file_type']),
        totalRows: iOf(j['total_rows']),
        validEstimate: iOf(j['valid_estimate']),
        invalidEstimate: iOf(j['invalid_estimate']),
        maxRows: iOf(j['max_rows']),
        headers: lOf(j['headers']).map((e) => e.toString()).toList(),
        mapping: mOf(j['mapping']).map((k, v) => MapEntry(k, iOf(v, -1))),
        rows: lOf(j['rows']).map((r) => lOf(r).map((c) => c.toString()).toList()).toList(),
      );
}

class ImportReport {
  final int totalRows, created, updated, skipped, failed, stockLines;
  final List<({int row, String name, String reason})> errors;
  ImportReport({required this.totalRows, required this.created, required this.updated,
      required this.skipped, required this.failed, required this.stockLines, required this.errors});

  factory ImportReport.fromJson(Map<String, dynamic> j) => ImportReport(
        totalRows: iOf(j['total_rows']),
        created: iOf(j['created']),
        updated: iOf(j['updated']),
        skipped: iOf(j['skipped']),
        failed: iOf(j['failed']),
        stockLines: iOf(j['stock_lines']),
        errors: lOf(j['errors']).map((e) {
          final m = mOf(e);
          return (row: iOf(m['row']), name: sOf(m['name']), reason: sOf(m['reason']));
        }).toList(),
      );
}
