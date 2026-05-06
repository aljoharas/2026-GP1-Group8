import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../home/home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isRegister = false;
  bool _showSplash = true;
  XFile? _profileImage;

  static const bg = Color(0xFF0E0E12);
  static const surface = Color(0x99222228);
  static const accent = Color(0xFFE8533A);
  static const muted = Color(0xFF8A8A9A);
  static const cardBorder = Color(0x33FFFFFF);
  static const green = Color(0xFF4ADE80);

  static const List<String> _gameImages = [
    'assets/images/ACO.jpg',
    'assets/images/BAK.jpg',
    'assets/images/COD.jpg',
    'assets/images/DBD5.jpg',
    'assets/images/ER.jpg',
    'assets/images/GoW.jpg',
    'assets/images/HKL.jpg',
    'assets/images/ITT.jpg',
    'assets/images/LN2.jpg',
    'assets/images/MK.jpg',
    'assets/images/RDR2.jpg',
    'assets/images/RE2.jpg',
    'assets/images/SF.jpg',
    'assets/images/SH2.jpg',
    'assets/images/Stray.jpg',
    'assets/images/TLOU.jpg',
    'assets/images/Uncharted.jpg',
  ];

  // ── Password checks ───────────────────────────────────────────────────────
  String get _pw => _passwordCtrl.text;
  bool get _hasMin => _pw.length >= 8;
  bool get _hasUpper => _pw.contains(RegExp(r'[A-Z]'));
  bool get _hasLower => _pw.contains(RegExp(r'[a-z]'));
  bool get _hasNumber => _pw.contains(RegExp(r'[0-9]'));
  bool get _hasMatch => _pw == _confirmCtrl.text && _pw.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _passwordCtrl.addListener(() => setState(() {}));
    _confirmCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  // ── Image picker ──────────────────────────────────────────────────────────
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16161E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(
                color: muted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: Colors.white,
              ),
              title: const Text(
                'Choose from library',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                final picked = await picker.pickImage(
                  source: ImageSource.gallery,
                  maxWidth: 512,
                  maxHeight: 512,
                  imageQuality: 85,
                );
                if (picked != null) setState(() => _profileImage = picked);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.camera_alt_outlined,
                color: Colors.white,
              ),
              title: const Text(
                'Take a photo',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                final picked = await picker.pickImage(
                  source: ImageSource.camera,
                  maxWidth: 512,
                  maxHeight: 512,
                  imageQuality: 85,
                );
                if (picked != null) setState(() => _profileImage = picked);
              },
            ),
            if (_profileImage != null)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFFF87171),
                ),
                title: const Text(
                  'Remove photo',
                  style: TextStyle(color: Color(0xFFF87171)),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _profileImage = null);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Submit ────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    auth.clearError();

    bool success;
    if (_isRegister) {
      success = await auth.register(
        _emailCtrl.text.trim(),
        _passwordCtrl.text.trim(),
        _usernameCtrl.text.trim(),
        bio: _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
        profileImagePath: _profileImage?.path,
      );
    } else {
      success = await auth.login(
        _emailCtrl.text.trim(),
        _passwordCtrl.text.trim(),
      );
    }

    if (success && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  // ── Forgot password bottom sheet ──────────────────────────────────────────
  void _showForgotPassword(BuildContext context) {
    final emailCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16161E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF8A8A9A).withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'Reset Password',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Enter your email and we'll send you a reset link.",
              style: TextStyle(color: Color(0xFF8A8A9A), fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'your@email.com',
                hintStyle: const TextStyle(color: Color(0xFF8A8A9A)),
                prefixIcon: const Icon(
                  Icons.email_outlined,
                  color: Color(0xFF8A8A9A),
                  size: 20,
                ),
                filled: true,
                fillColor: const Color(0x99222228),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0x33FFFFFF)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0x33FFFFFF)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: accent, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  if (emailCtrl.text.trim().isEmpty) return;
                  Navigator.pop(ctx);
                  final auth = context.read<AuthProvider>();
                  final success = await auth.sendPasswordReset(
                    emailCtrl.text.trim(),
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          success
                              ? 'Reset link sent! Check your email 📧'
                              : auth.errorMessage,
                        ),
                        backgroundColor: success
                            ? const Color(0xFF4ADE80)
                            : const Color(0xFFF87171),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Send Reset Link',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Background grid ───────────────────────────────────────────────────────
  Widget _buildBackground() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Transform.rotate(
          angle: -0.18,
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 1.4,
              height: MediaQuery.of(context).size.height * 1.4,
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.7,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                ),
                itemCount: _gameImages.length,
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(_gameImages[i], fit: BoxFit.cover),
                ),
              ),
            ),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x66000000), Color(0xCC000000), Color(0xF5000000)],
              stops: [0.0, 0.5, 0.85],
            ),
          ),
        ),
      ],
    );
  }

  // ── Splash ────────────────────────────────────────────────────────────────
  Widget _buildSplashScreen() {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildBackground(),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Welcome to\nloadout',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your ultimate gaming companion.',
                  style: TextStyle(color: muted, fontSize: 15),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () => setState(() => _showSplash = false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Get Started',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Password requirement row ──────────────────────────────────────────────
  Widget _reqRow(String label, bool met) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: met ? green : Colors.transparent,
              border: Border.all(color: met ? green : muted, width: 1.5),
            ),
            child: met
                ? const Icon(Icons.check, size: 10, color: Colors.black)
                : null,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: met ? green : muted,
              fontWeight: met ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordRequirements() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x33222228),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _reqRow('Minimum 8 characters', _hasMin),
          _reqRow('Includes an uppercase', _hasUpper),
          _reqRow('Includes a lowercase', _hasLower),
          _reqRow('Includes a number', _hasNumber),
        ],
      ),
    );
  }

  // ── Bio field ─────────────────────────────────────────────────────────────
  Widget _buildBioField() {
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 14, top: 16),
            child: Icon(Icons.edit_outlined, color: muted, size: 20),
          ),
          Expanded(
            child: TextFormField(
              controller: _bioCtrl,
              maxLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              validator: (_) => null,
              decoration: const InputDecoration(
                hintText: 'Bio (optional)',
                hintStyle: TextStyle(color: muted, fontSize: 14),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Auth screen ───────────────────────────────────────────────────────────
  Widget _buildAuthScreen() {
    final auth = context.watch<AuthProvider>();

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildBackground(),
        SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 280),

                    Text(
                      _isRegister ? 'Sign Up' : 'Login',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isRegister
                          ? 'Create an account to continue.'
                          : 'Please log in to continue.',
                      style: const TextStyle(color: muted, fontSize: 14),
                    ),
                    const SizedBox(height: 28),

                    // Error message
                    if (auth.status == AuthStatus.error) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0x1AF87171),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0x44F87171)),
                        ),
                        child: Text(
                          auth.errorMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFF87171),
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Register-only fields
                    if (_isRegister) ...[
                      // Profile picture
                      GestureDetector(
                        onTap: _pickImage,
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            CircleAvatar(
                              radius: 48,
                              backgroundColor: const Color(0xFF16161E),
                              backgroundImage: _profileImage != null
                                  ? FileImage(File(_profileImage!.path))
                                  : null,
                              child: _profileImage == null
                                  ? const Icon(
                                      Icons.person_outline,
                                      size: 40,
                                      color: muted,
                                    )
                                  : null,
                            ),
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: accent,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Profile picture (optional)',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                      const SizedBox(height: 20),

                      // Username
                      _buildField(
                        controller: _usernameCtrl,
                        hint: 'Username',
                        icon: Icons.person_outline,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty)
                            return 'Username is required';
                          if (v.trim().length < 3)
                            return 'At least 3 characters';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Bio
                      _buildBioField(),
                      const SizedBox(height: 4),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'You can always update this later.',
                          style: TextStyle(color: muted, fontSize: 11),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Email
                    _buildField(
                      controller: _emailCtrl,
                      hint: 'Email',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty)
                          return 'Email is required';
                        if (!v.contains('@')) return 'Enter a valid email';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // Password
                    _buildField(
                      controller: _passwordCtrl,
                      hint: 'Password',
                      icon: Icons.lock_outline,
                      obscure: _obscurePassword,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: muted,
                          size: 20,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty)
                          return 'Password is required';
                        if (_isRegister) {
                          if (!_hasMin) return 'At least 8 characters';
                          if (!_hasUpper) return 'Add an uppercase letter';
                          if (!_hasLower) return 'Add a lowercase letter';
                          if (!_hasNumber) return 'Add a number';
                        } else {
                          if (v.length < 6) return 'At least 6 characters';
                        }
                        return null;
                      },
                    ),

                    // Requirements box + confirm (register only)
                    if (_isRegister) ...[
                      const SizedBox(height: 10),
                      _buildPasswordRequirements(),
                      const SizedBox(height: 12),

                      _buildField(
                        controller: _confirmCtrl,
                        hint: 'Confirm Password',
                        icon: Icons.lock_outline,
                        obscure: _obscureConfirm,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirm
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: muted,
                            size: 20,
                          ),
                          onPressed: () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty)
                            return 'Please confirm password';
                          if (v != _passwordCtrl.text)
                            return 'Passwords do not match';
                          return null;
                        },
                      ),

                      if (_confirmCtrl.text.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _reqRow('Confirmation password must match', _hasMatch),
                      ],
                    ],

                    // Forgot password (login only)
                    if (!_isRegister) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () => _showForgotPassword(context),
                          child: const Text(
                            'Forgot Password?',
                            style: TextStyle(
                              color: accent,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Submit button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: auth.isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 0,
                        ),
                        child: auth.isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _isRegister ? 'Sign Up' : 'Login',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Toggle login/register
                    GestureDetector(
                      onTap: () {
                        setState(() => _isRegister = !_isRegister);
                        context.read<AuthProvider>().clearError();
                      },
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 13, color: muted),
                          children: [
                            TextSpan(
                              text: _isRegister
                                  ? 'Already have an account? Go to the '
                                  : "Don't have an account? Please ",
                            ),
                            TextSpan(
                              text: _isRegister ? 'Login Page.' : 'Sign Up',
                              style: const TextStyle(
                                color: accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (!_isRegister) const TextSpan(text: ' first.'),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: _showSplash ? _buildSplashScreen() : _buildAuthScreen(),
    );
  }

  // ── Field builder ─────────────────────────────────────────────────────────
  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscure = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: muted, fontSize: 14),
        prefixIcon: Icon(icon, color: muted, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFF87171)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFF87171)),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }
}
