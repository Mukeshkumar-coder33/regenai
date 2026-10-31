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
  });

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
    );
  }

  bool get isActive => status.toLowerCase() == 'active';
  bool get isBlocked => status.toLowerCase() == 'blocked';
  bool get hasOfficeLocation => latitude != null && longitude != null;
}

