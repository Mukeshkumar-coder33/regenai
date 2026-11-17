import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../auth/data/user_model.dart';
import '../../dashboard/data/dashboard_service.dart';
import '../data/company_model.dart';

/// Full-Page Executive Employee Registration Screen
///
/// Implements the exact schema and business fields from the ReGen website
/// (UsersModule.jsx & server/controllers/userController.js):
/// - Staff ID / Principal ID (e.g. KCT-20261001)
/// - Mandatory 12-digit Aadhaar Number (with live formatting & validation)
/// - Username & Initial Password (default 1234)
/// - First Name & Last Name (concatenated into full name)
/// - Department & Designation
/// - Date of Birth (with real-time age computation)
/// - Joining Date (defaults to active registration date)
/// - Gender selection (Male, Female, Other)
/// - Contact Phone Number & Communication Address
/// - Role Assignment (Staff, Company Admin, Intern, Freelancer)
/// - Monthly Compensation / Salary
/// - Gender-aware DiceBear Profile Avatar fallback (satisfies backend mandatory avatar check)
/// - Styled with photorealistic Corporate Dark Office Background, Frosted Glass Cards,
///   Unified Dark Glass Typing Boxes, and #10B981 Emerald Action Button.
class AddEmployeeView extends StatefulWidget {
  final CompanyModel? company;
  final UserModel currentUser;
  final DashboardService? dashboardService;

  const AddEmployeeView({
    super.key,
    this.company,
    required this.currentUser,
    this.dashboardService,
  });

  @override
  State<AddEmployeeView> createState() => _AddEmployeeViewState();
}

class _AddEmployeeViewState extends State<AddEmployeeView> {
  final _formKey = GlobalKey<FormState>();
  late final DashboardService _dashboardService;

  final TextEditingController _staffIdCtrl = TextEditingController();
  final TextEditingController _aadhaarCtrl = TextEditingController();
  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _firstNameCtrl = TextEditingController();
  final TextEditingController _lastNameCtrl = TextEditingController();
  final TextEditingController _deptCtrl = TextEditingController();
  final TextEditingController _designationCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();
  final TextEditingController _salaryCtrl = TextEditingController();
  final TextEditingController _dobCtrl = TextEditingController();
  final TextEditingController _joiningDateCtrl = TextEditingController();

  String _gender = 'Male';
  String _role = 'staff';
  int? _calculatedAge;
  bool _isSubmitting = false;
  String? _customAvatarUrl;
  bool _hasUploadedProfilePic = false;

  final List<String> _departments = const [
    'Engineering',
    'Product Design',
    'Quality Assurance',
    'Human Resources',
    'Marketing',
    'Operations',
    'Finance & Accounts',
    'Management',
  ];

  @override
  void initState() {
    super.initState();
    _dashboardService = widget.dashboardService ?? DashboardService();
  }

  @override
  void dispose() {
    _staffIdCtrl.dispose();
    _aadhaarCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _deptCtrl.dispose();
    _designationCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _salaryCtrl.dispose();
    _dobCtrl.dispose();
    _joiningDateCtrl.dispose();
    super.dispose();
  }

  int _computeAge(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  String _formatAadhaar(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    final limited = digits.length > 12 ? digits.substring(0, 12) : digits;
    final buffer = StringBuffer();
    for (int i = 0; i < limited.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(limited[i]);
    }
    return buffer.toString();
  }

  bool _isValidAadhaar(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.length == 12 && !digits.startsWith('0') && !digits.startsWith('1');
  }

  Future<void> _pickDate(TextEditingController controller, {bool isDob = false}) async {
    final currentText = controller.text.trim();
    DateTime initialDate = DateTime.now();
    if (currentText.isNotEmpty) {
      try {
        initialDate = DateTime.parse(currentText);
      } catch (_) {}
    }

    final now = DateTime.now();
    final firstDate = isDob
        ? DateTime(1940, 1, 1)
        : DateTime.now().subtract(const Duration(days: 365 * 2));
    final lastDate = isDob
        ? DateTime(now.year - 18, now.month, now.day)
        : DateTime.now().add(const Duration(days: 365));

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate.isAfter(lastDate)
          ? lastDate
          : (initialDate.isBefore(firstDate) ? firstDate : initialDate),
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: CeladonColors.primary,
              onPrimary: Colors.white,
              surface: CeladonColors.cardBackground,
              onSurface: CeladonColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final formatted =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() {
        controller.text = formatted;
        if (isDob) {
          _calculatedAge = _computeAge(picked);
        }
      });
    }
  }

  Future<void> _handleSave() async {
    final staffId = _staffIdCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final aadhaar = _aadhaarCtrl.text.replaceAll(RegExp(r'\D'), '');
    final phone = _phoneCtrl.text.trim().replaceAll(RegExp(r'[\s\-]'), '');
    final dob = _dobCtrl.text.trim();
    final joiningDate = _joiningDateCtrl.text.trim();
    final dept = _deptCtrl.text.trim();
    final designation = _designationCtrl.text.trim();
    final salary = _salaryCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    final password = _passwordCtrl.text.trim();

    if (staffId.isEmpty) {
      _showError('Staff ID is required.');
      return;
    }
    if (aadhaar.length != 12 || !_isValidAadhaar(aadhaar)) {
      _showError('Please enter a valid 12-digit Aadhaar number (cannot start with 0 or 1).');
      return;
    }
    if (username.length < 3) {
      _showError('Username is required (minimum 3 characters).');
      return;
    }
    if (password.isNotEmpty && password.length < 4) {
      _showError('Password must be at least 4 characters.');
      return;
    }
    if (firstName.isEmpty) {
      _showError('First Name is required.');
      return;
    }
    if (lastName.isEmpty) {
      _showError('Last Name is required.');
      return;
    }
    if (phone.isEmpty || !RegExp(r'^\+?[0-9]{10,14}$').hasMatch(phone)) {
      _showError('Valid Contact Number is required (at least 10 digits).');
      return;
    }
    if (dob.isEmpty) {
      _showError('Date of Birth is required.');
      return;
    }
    if (_calculatedAge == null || _calculatedAge! < 18) {
      _showError('Employee must be at least 18 years of age.');
      return;
    }
    if (dept.isEmpty) {
      _showError('Department is required.');
      return;
    }
    if (designation.isEmpty) {
      _showError('Designation is required.');
      return;
    }
    if (joiningDate.isEmpty) {
      _showError('Joining Date is required.');
      return;
    }
    final num? salaryNum = num.tryParse(salary);
    if (salary.isEmpty || salaryNum == null || salaryNum <= 0) {
      _showError('Please enter a valid positive monthly salary.');
      return;
    }
    if (address.isEmpty) {
      _showError('Communication Address is required.');
      return;
    }
    if (!_hasUploadedProfilePic || _customAvatarUrl == null || _customAvatarUrl!.trim().isEmpty) {
      _showError('Profile picture is mandatory. Please upload an image or capture with camera.');
      return;
    }

    final fullName = '$firstName $lastName'.trim();
    final finalPassword = password.isNotEmpty ? password : '1234';

    setState(() => _isSubmitting = true);

    final payload = <String, dynamic>{
      'userId': staffId,
      'username': username,
      'password': finalPassword,
      'aadhaar': aadhaar,
      'firstName': firstName,
      'lastName': lastName,
      'name': fullName,
      'department': dept,
      'designation': designation,
      'role': _role,
      'gender': _gender,
      'dateOfBirth': dob,
      'joiningDate': joiningDate,
      'phone': phone,
      'address': address,
      'salary': salary,
      'avatar': _customAvatarUrl!,
      'profilePicture': _customAvatarUrl!,
      'photo': _customAvatarUrl!,
      'company': widget.company?.id ?? widget.currentUser.company ?? '',
      'companyId': widget.company?.id ?? '',
    };

    try {
      await _dashboardService.createUser(payload);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Employee "$fullName" registered successfully!',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showError('Registration failed: $e');
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CeladonColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildProfilePhotoCard(),
                      const SizedBox(height: 14),
                      _buildCredentialsCard(),
                      const SizedBox(height: 14),
                      _buildPersonalInfoCard(),
                      const SizedBox(height: 14),
                      _buildOrganizationalPlacementCard(),
                      const SizedBox(height: 22),
                      _buildSubmitButton(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      color: CeladonColors.cardBackground,
      padding: const EdgeInsets.fromLTRB(14, 8, 16, 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: CeladonColors.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          const BrandLogo(size: 26, borderRadius: 8),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'Add New Employee',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: CeladonColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  'Company Workforce Registration',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: CeladonColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CeladonColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: CeladonColors.border,
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 17, color: CeladonColors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: CeladonColors.textPrimary,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildProfilePhotoCard() {
    return _buildGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _showPhotoPickerSheet,
                child: Stack(
                  children: [
                    Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _hasUploadedProfilePic ? CeladonColors.primary : CeladonColors.warning,
                          width: 2.2,
                        ),
                        color: CeladonColors.primaryLight,
                        boxShadow: [
                          BoxShadow(
                            color: (_hasUploadedProfilePic ? CeladonColors.primary : CeladonColors.warning)
                                .withValues(alpha: 0.25),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: _hasUploadedProfilePic && _customAvatarUrl != null
                            ? _buildAvatarImagePreview(_customAvatarUrl!)
                            : Container(
                                color: CeladonColors.primaryLight,
                                child: const Icon(Icons.add_a_photo_rounded, size: 28, color: CeladonColors.primary),
                              ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: _hasUploadedProfilePic ? CeladonColors.primary : CeladonColors.warning,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.2),
                        ),
                        child: Icon(
                          _hasUploadedProfilePic ? Icons.check_rounded : Icons.camera_alt_rounded,
                          size: 11,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Text(
                          'Profile Picture',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: CeladonColors.textPrimary,
                          ),
                        ),
                        SizedBox(width: 4),
                        Text(
                          '*',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: CeladonColors.error,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _hasUploadedProfilePic
                          ? 'Profile photo verified & attached.'
                          : 'Mandatory profile image required by database.',
                      style: TextStyle(
                        fontSize: 11,
                        color: _hasUploadedProfilePic ? CeladonColors.textMuted : CeladonColors.warning,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: (_hasUploadedProfilePic ? CeladonColors.primaryLight : CeladonColors.errorLight),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: (_hasUploadedProfilePic ? CeladonColors.primary : CeladonColors.error),
                        ),
                      ),
                      child: Text(
                        _hasUploadedProfilePic ? '✓ Photo Mandatory Check Passed' : '⚠️ Photo Upload Mandatory *',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: _hasUploadedProfilePic ? CeladonColors.primary : CeladonColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _showPhotoPickerSheet,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: _hasUploadedProfilePic
                    ? CeladonColors.cardBackground
                    : CeladonColors.primary,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _hasUploadedProfilePic ? CeladonColors.border : CeladonColors.primary,
                  width: 1.0,
                ),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _hasUploadedProfilePic ? Icons.sync_rounded : Icons.upload_file_rounded,
                    size: 15,
                    color: _hasUploadedProfilePic ? CeladonColors.textPrimary : Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _hasUploadedProfilePic ? 'Change Profile Picture' : 'Upload / Select Profile Picture *',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _hasUploadedProfilePic ? CeladonColors.textPrimary : Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarImagePreview(String url) {
    if (url.startsWith('data:image')) {
      try {
        final commaIdx = url.indexOf(',');
        final base64Data = commaIdx != -1 ? url.substring(commaIdx + 1) : url;
        final bytes = base64Decode(base64Data);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            color: const Color(0xFF10B981).withValues(alpha: 0.2),
            child: const Icon(Icons.person_rounded, size: 34, color: Color(0xFF34D399)),
          ),
        );
      } catch (_) {}
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        color: const Color(0xFF10B981).withValues(alpha: 0.2),
        child: const Icon(Icons.person_rounded, size: 34, color: Color(0xFF34D399)),
      ),
    );
  }

  Future<void> _pickImageFromSource(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: source,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.front,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        final ext = file.name.split('.').last.toLowerCase();
        final mime = (ext == 'png') ? 'image/png' : 'image/jpeg';
        final base64Str = 'data:$mime;base64,${base64Encode(bytes)}';
        setState(() {
          _customAvatarUrl = base64Str;
          _hasUploadedProfilePic = true;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              content: Text(source == ImageSource.camera
                  ? '✓ Camera photo captured and uploaded successfully!'
                  : '✓ Profile picture uploaded successfully from device!'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to capture or access photo: $e');
      }
    }
  }

  void _showPhotoPickerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          decoration: const BoxDecoration(
            color: CeladonColors.cardBackground,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: CeladonColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Upload Profile Photo *',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: CeladonColors.textPrimary),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: CeladonColors.textMuted, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Upload employee photo directly from device files or gallery.',
                style: TextStyle(fontSize: 12, color: CeladonColors.textMuted),
              ),
              const SizedBox(height: 20),

              // Device Gallery Option
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImageFromSource(ImageSource.gallery);
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: CeladonColors.primaryLight,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: CeladonColors.primary),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.photo_library_rounded, color: CeladonColors.primary, size: 22),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Choose from Device Gallery',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: CeladonColors.textPrimary),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Select employee photo from device files or gallery',
                              style: TextStyle(fontSize: 11, color: CeladonColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios_rounded, color: CeladonColors.primary, size: 14),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Device Camera Option
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImageFromSource(ImageSource.camera);
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: CeladonColors.inputBackground,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: CeladonColors.border),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.camera_alt_rounded, color: CeladonColors.primary, size: 22),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Take Photo with Camera',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: CeladonColors.textPrimary),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Capture photo directly using device camera',
                              style: TextStyle(fontSize: 11, color: CeladonColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios_rounded, color: CeladonColors.textMuted, size: 14),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCredentialsCard() {
    final isAadhaarValid = _isValidAadhaar(_aadhaarCtrl.text);

    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionTitle('System Identity & Credentials', Icons.badge_outlined),
          const SizedBox(height: 14),

          // Staff ID
          _buildCompanyInputField(
            controller: _staffIdCtrl,
            labelText: 'Staff ID / Principal ID *',
            hintText: 'e.g. KCT-20261001',
            prefixIcon: Icons.badge_outlined,
          ),
          const SizedBox(height: 12),

          // Aadhaar
          _buildCompanyInputField(
            controller: _aadhaarCtrl,
            labelText: 'Aadhaar Number (12 Digits) *',
            hintText: 'XXXX XXXX XXXX',
            prefixIcon: Icons.fingerprint_rounded,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (val) {
              final formatted = _formatAadhaar(val);
              if (formatted != val) {
                _aadhaarCtrl.value = TextEditingValue(
                  text: formatted,
                  selection: TextSelection.collapsed(offset: formatted.length),
                );
              }
              setState(() {});
            },
            suffixWidget: isAadhaarValid
                ? const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: Icon(Icons.check_circle_rounded, color: Color(0xFF34D399), size: 18),
                  )
                : null,
          ),
          if (_aadhaarCtrl.text.isNotEmpty && !isAadhaarValid) ...[
            const SizedBox(height: 4),
            const Text(
              'Aadhaar must be 12 digits and cannot start with 0 or 1.',
              style: TextStyle(fontSize: 11, color: Color(0xFFF87171)),
            ),
          ],
          const SizedBox(height: 12),

          // Username & Password row
          Row(
            children: [
              Expanded(
                child: _buildCompanyInputField(
                  controller: _usernameCtrl,
                  labelText: 'Username *',
                  hintText: 'e.g. priya.s',
                  prefixIcon: Icons.person_outline_rounded,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildCompanyInputField(
                  controller: _passwordCtrl,
                  labelText: 'Password *',
                  hintText: 'Enter password (min 4 chars)',
                  prefixIcon: Icons.lock_outline_rounded,
                  obscureText: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Staff will use this password for initial login and can update it anytime.',
            style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalInfoCard() {
    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionTitle('Personal Information', Icons.person_pin_outlined),
          const SizedBox(height: 14),

          // First Name & Last Name row
          Row(
            children: [
              Expanded(
                child: _buildCompanyInputField(
                  controller: _firstNameCtrl,
                  labelText: 'First Name *',
                  hintText: 'e.g. John',
                  prefixIcon: Icons.person_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildCompanyInputField(
                  controller: _lastNameCtrl,
                  labelText: 'Last Name *',
                  hintText: 'e.g. Doe',
                  prefixIcon: Icons.person_outline_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Gender & DOB row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Gender *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: CeladonColors.textSecondary,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 46,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: CeladonColors.inputBackground,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: CeladonColors.border,
                          width: 1.0,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _gender,
                          isExpanded: true,
                          dropdownColor: CeladonColors.cardBackground,
                          icon: const Icon(Icons.arrow_drop_down_rounded, color: CeladonColors.textMuted),
                          style: const TextStyle(
                            color: CeladonColors.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Male', child: Text('Male')),
                            DropdownMenuItem(value: 'Female', child: Text('Female')),
                            DropdownMenuItem(value: 'Other', child: Text('Other')),
                          ],
                          onChanged: (v) => setState(() => _gender = v ?? 'Male'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => _pickDate(_dobCtrl, isDob: true),
                  child: AbsorbPointer(
                    child: _buildCompanyInputField(
                      controller: _dobCtrl,
                      labelText: _calculatedAge != null ? 'Date of Birth (Age: $_calculatedAge) *' : 'Date of Birth *',
                      hintText: 'YYYY-MM-DD',
                      prefixIcon: Icons.calendar_today_rounded,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Contact Phone
          _buildCompanyInputField(
            controller: _phoneCtrl,
            labelText: 'Contact Phone Number',
            hintText: 'e.g. +91 98765 43210',
            prefixIcon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),

          // Communication Address
          _buildCompanyInputField(
            controller: _addressCtrl,
            labelText: 'Communication Address *',
            hintText: 'Enter permanent residential address as per Aadhaar...',
            prefixIcon: Icons.home_outlined,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildOrganizationalPlacementCard() {
    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionTitle('Organizational Placement', Icons.business_outlined),
          const SizedBox(height: 14),

          // Department & Designation row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Department',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: CeladonColors.textSecondary,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 46,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: CeladonColors.inputBackground,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: CeladonColors.border,
                          width: 1.0,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _departments.contains(_deptCtrl.text) ? _deptCtrl.text : _departments.first,
                          isExpanded: true,
                          dropdownColor: CeladonColors.cardBackground,
                          icon: const Icon(Icons.arrow_drop_down_rounded, color: CeladonColors.textMuted),
                          style: const TextStyle(
                            color: CeladonColors.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                          items: _departments
                              .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                              .toList(),
                          onChanged: (v) => setState(() => _deptCtrl.text = v ?? 'Engineering'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildCompanyInputField(
                  controller: _designationCtrl,
                  labelText: 'Designation',
                  hintText: 'e.g. Software Developer',
                  prefixIcon: Icons.work_outline_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Role & Joining Date row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Role Permission',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: CeladonColors.textSecondary,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 46,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: CeladonColors.inputBackground,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: CeladonColors.border,
                          width: 1.0,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _role,
                          isExpanded: true,
                          dropdownColor: CeladonColors.cardBackground,
                          icon: const Icon(Icons.arrow_drop_down_rounded, color: CeladonColors.textMuted),
                          style: const TextStyle(
                            color: CeladonColors.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'staff', child: Text('Staff Member')),
                            DropdownMenuItem(value: 'admin', child: Text('Company Admin')),
                            DropdownMenuItem(value: 'intern', child: Text('Intern')),
                            DropdownMenuItem(value: 'freelancer', child: Text('Freelancer')),
                            DropdownMenuItem(value: 'owner', child: Text('Company Owner')),
                          ],
                          onChanged: (v) => setState(() => _role = v ?? 'staff'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => _pickDate(_joiningDateCtrl),
                  child: AbsorbPointer(
                    child: _buildCompanyInputField(
                      controller: _joiningDateCtrl,
                      labelText: 'Joining Date',
                      hintText: 'YYYY-MM-DD',
                      prefixIcon: Icons.event_available_rounded,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Monthly Salary
          _buildCompanyInputField(
            controller: _salaryCtrl,
            labelText: 'Monthly Salary (INR)',
            hintText: 'e.g. 45000',
            prefixIcon: Icons.currency_rupee_rounded,
            keyboardType: TextInputType.number,
          ),
        ],
      ),
    );
  }

  Widget _buildCompanyInputField({
    required TextEditingController controller,
    required String labelText,
    required String hintText,
    IconData? prefixIcon,
    Widget? suffixWidget,
    ValueChanged<String>? onChanged,
    bool obscureText = false,
    TextInputType? keyboardType,
    int maxLines = 1,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          labelText,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: CeladonColors.textSecondary,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: maxLines == 1 ? 48 : null,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: CeladonColors.inputBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: CeladonColors.border,
              width: 1.0,
            ),
          ),
          child: Row(
            children: [
              if (prefixIcon != null) ...[
                Icon(prefixIcon, size: 20, color: CeladonColors.textMuted),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  obscureText: obscureText,
                  keyboardType: keyboardType,
                  maxLines: maxLines,
                  inputFormatters: inputFormatters,
                  cursorColor: CeladonColors.primary,
                  style: const TextStyle(
                    color: CeladonColors.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    hintText: hintText,
                    hintStyle: const TextStyle(
                      color: CeladonColors.textPlaceholder,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: maxLines > 1 ? 8 : 10),
                  ),
                ),
              ),
              if (suffixWidget != null) ...[
                const SizedBox(width: 8),
                suffixWidget,
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return InkWell(
      onTap: _isSubmitting ? null : _handleSave,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: CeladonColors.primary,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: CeladonColors.primary.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: _isSubmitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 19),
                  SizedBox(width: 8),
                  Text(
                    'Register Employee',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

