/// ReGen Authenticated User Model
///
/// Maps exactly to the JSON response returned by `POST /api/auth/login` and `/api/users/me`.
class UserModel {
  final String id;
  final String userId;
  final String username;
  final String name;
  final String role;
  final String? companyId;
  final String? company;
  final String? avatar;
  final String? department;
  final String? designation;
  final String? email;
  final String? phone;
  final bool mustChangePassword;
  final String token;
  final String? authSource;

  const UserModel({
    required this.id,
    required this.userId,
    required this.username,
    required this.name,
    required this.role,
    this.companyId,
    this.company,
    this.avatar,
    this.department,
    this.designation,
    this.email,
    this.phone,
    this.mustChangePassword = false,
    required this.token,
    this.authSource,
  });

  /// Factory constructor to parse backend JSON response
  factory UserModel.fromJson(Map<String, dynamic> json, {String? fallbackToken}) {
    final tkn = (json['token'] ?? fallbackToken ?? '').toString();
    return UserModel(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      userId: (json['userId'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      name: (json['name'] ?? json['username'] ?? '').toString(),
      role: (json['role'] ?? 'staff').toString(),
      companyId: json['companyId']?.toString(),
      company: json['company']?.toString(),
      avatar: json['avatar']?.toString(),
      department: json['department']?.toString(),
      designation: json['designation']?.toString(),
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      mustChangePassword: json['mustChangePassword'] == true,
      token: tkn,
      authSource: json['authSource']?.toString(),
    );
  }

  /// Converts user object to Map for JSON caching
  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'userId': userId,
      'username': username,
      'name': name,
      'role': role,
      'companyId': companyId,
      'company': company,
      'avatar': avatar,
      'department': department,
      'designation': designation,
      'email': email,
      'phone': phone,
      'mustChangePassword': mustChangePassword,
      'token': token,
      'authSource': authSource,
    };
  }

  UserModel copyWith({
    String? id,
    String? userId,
    String? username,
    String? name,
    String? role,
    String? companyId,
    String? company,
    String? avatar,
    String? department,
    String? designation,
    String? email,
    String? phone,
    bool? mustChangePassword,
    String? token,
    String? authSource,
  }) {
    return UserModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      name: name ?? this.name,
      role: role ?? this.role,
      companyId: companyId ?? this.companyId,
      company: company ?? this.company,
      avatar: avatar ?? this.avatar,
      department: department ?? this.department,
      designation: designation ?? this.designation,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
      token: token ?? this.token,
      authSource: authSource ?? this.authSource,
    );
  }

  // Role resolution helpers
  bool get isSuperAdmin => role == 'param';
  bool get isCompanyAdmin => role == 'owner' || role == 'admin';
  bool get isEmployee => role == 'staff' || role == 'intern' || role == 'freelancer';

  /// Whether this user account is authorized to toggle into SuperAdmin console
  bool get canSwitchToSuperAdmin =>
      isSuperAdmin ||
      username.toLowerCase() == 'vyshwa' ||
      userId.toLowerCase() == 'vyshwa';

  String? get companyName => company;

  String get roleDisplayName {
    switch (role) {
      case 'param':
        return 'Super Administrator';
      case 'owner':
        return 'Company Owner';
      case 'admin':
        return 'Company Admin';
      case 'intern':
        return 'Intern';
      case 'freelancer':
        return 'Contractor';
      case 'staff':
      default:
        return designation?.isNotEmpty == true ? designation! : 'Employee';
    }
  }
}
