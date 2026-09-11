/// نماذج البيانات — مطابقة لواجهات frontend/apps/pharmacy-app/src/lib/api.ts
/// الملاحظة الحرجة: إحصاءات اللوحة تأتي بمفاتيح camelCase بينما البقية
/// snake_case — كما تردها الواجهة الويب حرفيًا.
library;

String _s(dynamic v) => v == null ? '' : v.toString();

int _i(dynamic v) => int.tryParse('${v ?? ''}') ?? 0;

bool _b(dynamic v) => v == true;

Map<String, dynamic> _m(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return <String, dynamic>{};
}

class User {
  final String id;
  final String email;
  final String firstName;
  final String lastName;
  final String displayName;
  final String role;
  final String accountType;
  final bool isActive;
  final bool emailVerified;
  final String locale;
  final bool onboardingRequired;
  final String pharmacyId;

  const User({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.displayName,
    required this.role,
    required this.accountType,
    required this.isActive,
    required this.emailVerified,
    required this.locale,
    required this.onboardingRequired,
    required this.pharmacyId,
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: _s(j['id']),
        email: _s(j['email']),
        firstName: _s(j['first_name']),
        lastName: _s(j['last_name']),
        displayName: _s(j['display_name']),
        role: _s(j['role']),
        accountType: _s(j['account_type']),
        isActive: _b(j['is_active']),
        emailVerified: _b(j['email_verified']),
        locale: _s(j['locale']),
        onboardingRequired: _b(j['onboarding_required']),
        pharmacyId: _s(j['pharmacy_id']),
      );

  /// الاسم المعروض — اسم المستخدم إن وُجد وإلا البريد
  String get friendlyName {
    if (displayName.trim().isNotEmpty) return displayName.trim();
    final full = '${firstName.trim()} ${lastName.trim()}'.trim();
    if (full.isNotEmpty) return full;
    return email;
  }
}

class OnboardingProfile {
  final String name;
  final String phone;
  final String website;
  final String addressLine1;
  final String addressLine2;
  final String city;
  final String stateProvince;
  final String postalCode;
  final String country;

  const OnboardingProfile({
    required this.name,
    required this.phone,
    required this.website,
    required this.addressLine1,
    required this.addressLine2,
    required this.city,
    required this.stateProvince,
    required this.postalCode,
    required this.country,
  });

  factory OnboardingProfile.fromJson(Map<String, dynamic> j) => OnboardingProfile(
        name: _s(j['name']),
        phone: _s(j['phone']),
        website: _s(j['website']),
        addressLine1: _s(j['address_line1']),
        addressLine2: _s(j['address_line2']),
        city: _s(j['city']),
        stateProvince: _s(j['state_province']),
        postalCode: _s(j['postal_code']),
        country: _s(j['country']),
      );

  Map<String, dynamic> toUpdatePayload({bool? complete}) =>
      <String, dynamic>{
        'name': name,
        'phone': phone,
        'website': website,
        'address_line1': addressLine1,
        'address_line2': addressLine2,
        'city': city,
        'state_province': stateProvince,
        'postal_code': postalCode,
        if (complete != null) 'complete': complete,
      };
}

class OnboardingState {
  final bool onboardingRequired;
  final OnboardingProfile pharmacy;

  const OnboardingState({
    required this.onboardingRequired,
    required this.pharmacy,
  });

  factory OnboardingState.fromJson(Map<String, dynamic> j) => OnboardingState(
        onboardingRequired: _b(j['onboarding_required']),
        pharmacy: OnboardingProfile.fromJson(_m(j['pharmacy'])),
      );
}

class LowStockItem {
  final String name;
  final String genericName;
  final int quantity;
  final int strips;
  final int minStockLevel;
  final String status;

  const LowStockItem({
    required this.name,
    required this.genericName,
    required this.quantity,
    required this.strips,
    required this.minStockLevel,
    required this.status,
  });

  factory LowStockItem.fromJson(Map<String, dynamic> j) => LowStockItem(
        name: _s(j['name']),
        genericName: _s(j['generic_name']),
        quantity: _i(j['quantity']),
        strips: _i(j['strips']),
        minStockLevel: _i(j['min_stock_level']),
        status: _s(j['status']),
      );
}

class DashboardStats {
  final int totalProducts;
  final int lowStockCount;
  final int activeEmployees;
  final int activeToday;
  final int salesUnitsToday;
  final List<LowStockItem> lowStockItems;

  const DashboardStats({
    required this.totalProducts,
    required this.lowStockCount,
    required this.activeEmployees,
    required this.activeToday,
    required this.salesUnitsToday,
    required this.lowStockItems,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> j) => DashboardStats(
        totalProducts: _i(j['totalProducts']),
        lowStockCount: _i(j['lowStockCount']),
        activeEmployees: _i(j['activeEmployees']),
        activeToday: _i(j['activeToday']),
        salesUnitsToday: _i(j['salesUnitsToday']),
        lowStockItems: (j['lowStockItems'] as List?)
                ?.whereType<Map>()
                .map((m) => LowStockItem.fromJson(Map<String, dynamic>.from(m)))
                .toList() ??
            <LowStockItem>[],
      );
}

class Product {
  final String id;
  final String name;
  final String genericName;
  final String strength;
  final String barcode;
  final String packagingType;
  final int unitsPerBox;
  final int sellingPricePiastres;
  final int partialSellingPricePiastres;
  final int stock;

  const Product({
    required this.id,
    required this.name,
    required this.genericName,
    required this.strength,
    required this.barcode,
    required this.packagingType,
    required this.unitsPerBox,
    required this.sellingPricePiastres,
    required this.partialSellingPricePiastres,
    required this.stock,
  });

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: _s(j['id']),
        name: _s(j['name']),
        genericName: _s(j['generic_name']),
        strength: _s(j['strength']),
        barcode: _s(j['barcode']),
        packagingType: _s(j['packaging_type']),
        unitsPerBox: _i(j['units_per_box']),
        sellingPricePiastres: _i(j['selling_price_piastres']),
        partialSellingPricePiastres: _i(j['partial_selling_price_piastres']),
        stock: _i(j['stock']),
      );

  /// الأسعار تُخزن بالقروش — العرض بالجنيه (100 قرش)
  String get priceEgp => (sellingPricePiastres / 100).toStringAsFixed(2);

  bool get isBoxStrip => packagingType == 'BOX_STRIP';
}
