import 'package:flutter/material.dart';
import 'package:nature_biotic/core/theme.dart';
import 'package:nature_biotic/services/supabase_service.dart';
import 'package:nature_biotic/features/auth/screens/login_screen.dart';
import 'package:nature_biotic/features/profile/screens/dropdown_creator_screen.dart';
import 'package:nature_biotic/features/attendance/screens/attendance_history_screen.dart';
import 'package:image_picker/image_picker.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  Map<String, int> _stats = {'farmers': 0, 'farms': 0, 'reports': 0};
  bool _isLoading = true;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _fetchProfile(),
      _fetchStats(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchProfile() async {
    try {
      final profile = await SupabaseService.getProfile();
      if (mounted) {
        setState(() {
          _profile = profile;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchStats() async {
    final stats = await SupabaseService.getUserStats();
    if (mounted) setState(() => _stats = stats);
  }

  Future<void> _updateName() async {
    final controller = TextEditingController(text: _profile?['full_name']);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Full Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != _profile?['full_name']) {
      setState(() => _isLoading = true);
      try {
        await SupabaseService.updateProfile({'full_name': newName});
        await _fetchProfile();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _changePassword() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Password'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'New Password'),
          obscureText: true,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (result != null && result.length >= 6) {
      setState(() => _isLoading = true);
      try {
        await SupabaseService.updatePassword(result);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password updated successfully'), backgroundColor: AppColors.primary),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _uploadAvatar() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (image == null) return;

    setState(() => _isLoading = true);
    try {
      final bytes = await image.readAsBytes();
      final fileName = 'avatar_${SupabaseService.client.auth.currentUser!.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final url = await SupabaseService.uploadImage(bytes, fileName, 'profiles');
      
      await SupabaseService.updateProfile({'avatar_url': url});
      await _fetchProfile();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadSignature() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (image == null) return;

    setState(() => _isLoading = true);
    try {
      final bytes = await image.readAsBytes();
      final fileName = 'signature_${SupabaseService.client.auth.currentUser!.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final url = await SupabaseService.uploadImage(bytes, fileName, 'profiles');
      
      await SupabaseService.updateProfile({'signature_url': url});
      await _fetchProfile();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final String fullName = _profile?['full_name'] ?? 'Nature Biotic User';
    final user = SupabaseService.client.auth.currentUser;
    final String identity = _profile?['role'] == 'admin' 
      ? (user?.email ?? 'admin@naturebiotic.com')
      : (_profile?['username'] ?? 'Executive');
      
    final String role = _profile?['role']?.toString().toUpperCase() ?? 'EXECUTIVE';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(onPressed: _fetchData, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
            child: Column(
              children: [
                Center(
                  child: Stack(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.secondary, width: 2),
                        ),
                        child: Hero(
                          tag: 'profile_avatar',
                          child: CircleAvatar(
                            radius: 50,
                            backgroundColor: const Color(0xFFE8F5E9),
                            backgroundImage: _profile?['avatar_url'] != null 
                              ? NetworkImage(_profile!['avatar_url']) 
                              : null,
                            child: _profile?['avatar_url'] == null 
                              ? const Icon(Icons.person, size: 50, color: AppColors.primary)
                              : null,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _uploadAvatar,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  fullName,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                Text(
                  identity,
                  style: const TextStyle(color: AppColors.textGray, fontSize: 14),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F4F1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    role,
                    style: const TextStyle(
                      fontSize: 12, 
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      color: AppColors.textGray,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                // Statistics Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.shadow.withOpacity(0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: _profile?['role'] == 'store' 
                      ? [
                        _statItem(_stats['stock']?.toString() ?? '0', 'Stock Items'),
                        _divider(),
                        _statItem(_stats['trans']?.toString() ?? '0', 'Total Trans'),
                        _divider(),
                        _statItem(_stats['pending']?.toString() ?? '0', 'Pending'),
                      ]
                      : [
                        _statItem(_stats['farmers']?.toString() ?? '0', 'Farmers'),
                        _divider(),
                        _statItem(_stats['farms']?.toString() ?? '0', 'Farms'),
                        _divider(),
                        _statItem(_stats['reports']?.toString() ?? '0', 'Reports'),
                      ],
                  ),
                ),
                const SizedBox(height: 32),
                _profileOption(Icons.person_outline, 'Account Settings', onTap: _updateName),
                _profileOption(Icons.lock_outline_rounded, 'Change Password', onTap: _changePassword),
                _profileOption(Icons.calendar_month_rounded, 'Attendance History', onTap: () {
                  Navigator.push(
                    context, 
                    MaterialPageRoute(builder: (context) => const AttendanceHistoryScreen())
                  );
                }),
                _profileOption(Icons.sync_rounded, 'Sync Offline Data', onTap: () async {
                  setState(() => _isLoading = true);
                  await SupabaseService.syncAllDropdownOptions();
                  if (mounted) {
                    setState(() => _isLoading = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Offline data synchronized successfully'),
                        backgroundColor: AppColors.primary,
                      ),
                    );
                  }
                }),
                _profileOption(
                  Icons.gesture_rounded,
                  'Signature',
                  onTap: _uploadSignature,
                  trailing: _profile?['signature_url'] != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            color: const Color(0xFFF1F4F1),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Image.network(
                              _profile!['signature_url'],
                              width: 60,
                              height: 30,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) => const Icon(
                                Icons.broken_image_rounded,
                                color: Colors.red,
                                size: 20,
                              ),
                            ),
                          ),
                        )
                      : const Text(
                          'Not Uploaded',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
                _profileOption(Icons.help_outline_rounded, 'Help & Support', onTap: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    builder: (context) => _supportSheet(),
                  );
                }),
                if (_profile?['role'] == 'admin')
                  _profileOption(
                    Icons.settings_suggest_rounded, 
                    'Drop down Creator', 
                    onTap: () => Navigator.push(
                      context, 
                      MaterialPageRoute(builder: (context) => const DropdownCreatorScreen())
                    )
                  ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () async {
                    await SupabaseService.signOut();
                    if (mounted) {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (context) => const LoginScreen()),
                        (route) => false,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFF5F5),
                    foregroundColor: Colors.red,
                    elevation: 0,
                    side: const BorderSide(color: Color(0xFFFFDADA)),
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.logout_rounded, size: 20),
                      SizedBox(width: 12),
                      Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statItem(String count, String label) {
    return Column(
      children: [
        Text(
          count,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primary),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textGray),
        ),
      ],
    );
  }

  Widget _divider() {
    return Container(
      height: 30,
      width: 1,
      color: AppColors.secondary,
    );
  }

  Widget _supportSheet() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(32), topRight: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Help & Support', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          _supportItem(Icons.email_outlined, 'support@naturebiotic.com'),
          const SizedBox(height: 16),
          _supportItem(Icons.phone_outlined, '+91 98765 43210'),
          const SizedBox(height: 16),
          _supportItem(Icons.location_on_outlined, 'Nature Biotic HQ, Bangalore'),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _supportItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 16),
        Text(text, style: const TextStyle(fontSize: 15)),
      ],
    );
  }

  Widget _profileOption(IconData icon, String title, {VoidCallback? onTap, Widget? trailing}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 16),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const Spacer(),
            if (trailing != null) ...[
              trailing,
              const SizedBox(width: 12),
            ],
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textGray),
          ],
        ),
      ),
    );
  }
}
