/// ReGen Company Model
///
/// Maps exactly to MongoDB `Company` documents returned by `GET /api/company`.
class CompanyModel {
  final String id;
  final String name;
  final String? logo;
  final String? phoneNumber;
  final String? email;
  final String? category;
  final String? about;
  final String? address;
  final String? city;
  final String? state;
  final String? zip;
  final String? ownerId;
  final String? ownerName;
  final String status;
  final double? latitude;
  final double? longitude;
  final int? radius;
  final String? createdAt;
  final int? establishmentYear;
  final int? establishmentMonth;
  final String? founded;

  const CompanyModel({
    required this.id,
    required this.name,
    this.logo,
    this.phoneNumber,
    this.email,
    this.category,
    this.about,
    this.address,
    this.city,
    this.state,
    this.zip,
    this.ownerId,
    this.ownerName,
    this.status = 'active',
    this.latitude,
    this.longitude,
    this.radius,
    this.createdAt,
    this.establishmentYear,
    this.establishmentMonth,
    this.founded,
  });

  int get startingYear {
    if (establishmentYear != null && establishmentYear! > 0) return establishmentYear!;
    if (founded != null && founded!.isNotEmpty) {
      final f = int.tryParse(founded!);
      if (f != null && f > 0) return f;
      final dt = DateTime.tryParse(founded!);
      if (dt != null && dt.year >= 1970 && dt.year <= DateTime.now().year) return dt.year;
    }
    if (createdAt != null && createdAt!.isNotEmpty) {
      final dt = DateTime.tryParse(createdAt!);
      if (dt != null && dt.year >= 1970 && dt.year <= DateTime.now().year) return dt.year;
    }
    if (id.length == 24) {
      try {
        final sec = int.parse(id.substring(0, 8), radix: 16);
        final dt = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
        if (dt.year >= 2000 && dt.year <= DateTime.now().year) return dt.year;
      } catch (_) {}
    }
    return DateTime.now().year;
  }

  int get startingMonth {
    if (establishmentMonth != null && establishmentMonth! >= 1 && establishmentMonth! <= 12) {
      return establishmentMonth!;
    }
    if (founded != null && founded!.isNotEmpty) {
      final dt = DateTime.tryParse(founded!);
      if (dt != null) return dt.month;
    }
    if (createdAt != null && createdAt!.isNotEmpty) {
      final dt = DateTime.tryParse(createdAt!);
      if (dt != null) return dt.month;
    }
    if (id.length == 24) {
      try {
        final sec = int.parse(id.substring(0, 8), radix: 16);
        final dt = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
        return dt.month;
      } catch (_) {}
    }
    return 1;
  }

  factory CompanyModel.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? officeLoc;
    if (json['officeLocation'] is Map<String, dynamic>) {
      officeLoc = json['officeLocation'] as Map<String, dynamic>;
    }

    return CompanyModel(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Company').toString(),
      logo: json['logo']?.toString(),
      phoneNumber: json['phoneNumber']?.toString(),
      email: json['email']?.toString(),
      category: json['category']?.toString(),
      about: json['about']?.toString(),
      address: json['address']?.toString(),
      city: json['city']?.toString() ?? 'Chennai',
      state: json['state']?.toString(),
      zip: json['zip']?.toString(),
      ownerId: json['ownerId']?.toString(),
      ownerName: json['ownerName']?.toString(),
      status: (json['status'] ?? 'active').toString(),
      latitude: officeLoc != null && officeLoc['latitude'] != null
          ? double.tryParse(officeLoc['latitude'].toString())
          : null,
      longitude: officeLoc != null && officeLoc['longitude'] != null
          ? double.tryParse(officeLoc['longitude'].toString())
          : null,
      radius: officeLoc != null && officeLoc['radius'] != null
          ? int.tryParse(officeLoc['radius'].toString())
          : null,
      createdAt: (json['createdAt'] ?? json['created_at'])?.toString(),
      establishmentYear: json['establishmentYear'] != null
          ? int.tryParse(json['establishmentYear'].toString())
          : null,
      establishmentMonth: json['establishmentMonth'] != null
          ? int.tryParse(json['establishmentMonth'].toString())
          : null,
      founded: (json['founded'] ?? json['establishmentDate'] ?? json['startingDate'] ?? json['startDate'])?.toString(),
    );
  }

  bool get isActive => status.toLowerCase() == 'active';
  bool get isBlocked => status.toLowerCase() == 'blocked';
  bool get hasOfficeLocation => latitude != null && longitude != null;
}

