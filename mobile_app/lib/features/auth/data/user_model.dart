/// ReGen Authenticated User Model
///
/// Maps exactly to the JSON response returned by `POST /api/auth/login`.
class UserModel {
  final String id;
  final String userId;
  final String username;
  final String name;
  final String role;
  final String? companyId;
  final String? company;
  final String? avatar;
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
    this.mustChangePassword = false,
    required this.token,
    this.authSource,
  });

  /// Factory constructor to parse backend JSON response
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      userId: (json['userId'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      name: (json['name'] ?? json['username'] ?? '').toString(),
      role: (json['role'] ?? 'staff').toString(),
      companyId: json['companyId']?.toString(),
      company: json['company']?.toString(),
      avatar: json['avatar']?.toString(),
      mustChangePassword: json['mustChangePassword'] == true,
      token: (json['token'] ?? '').toString(),
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
      'mustChangePassword': mustChangePassword,
      'token': token,
      'authSource': authSource,
    };
  }

  // Role resolution helpers
  bool get isSuperAdmin => role == 'param';
  bool get isCompanyAdmin => role == 'owner' || role == 'admin';
  bool get isEmployee => role == 'staff' || role == 'intern';

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
      case 'staff':
      default:
        return 'Employee';
    }
  }
}

