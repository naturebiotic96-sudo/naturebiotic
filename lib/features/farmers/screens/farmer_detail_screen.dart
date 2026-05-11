import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nature_biotic/core/theme.dart';
import 'package:nature_biotic/services/supabase_service.dart';
import 'package:nature_biotic/features/farmers/screens/add_farmer_screen.dart';
import 'package:nature_biotic/features/farms/screens/add_farm_screen.dart';
import 'package:nature_biotic/features/farms/screens/farm_detail_screen.dart';

import 'package:nature_biotic/core/call_tracker.dart';
import 'package:nature_biotic/services/local_database_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:nature_biotic/features/profile/screens/edit_request_dialog.dart';

class FarmerDetailScreen extends StatefulWidget {
  final Map<String, dynamic> farmer;

  const FarmerDetailScreen({super.key, required this.farmer});

  @override
  State<FarmerDetailScreen> createState() => _FarmerDetailScreenState();
}

class _FarmerDetailScreenState extends State<FarmerDetailScreen>
    with WidgetsBindingObserver {
  late Map<String, dynamic> _farmer;
  List<Map<String, dynamic>> _farms = [];
  String? _userRole;
  bool _isLoading = true;

  // Tracking
  DateTime? _callStartTime;
  String? _dialedNumber;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _farmer = widget.farmer;
    _loadFarms();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _callStartTime != null &&
        _dialedNumber != null) {
      final startTime = _callStartTime!;
      final dialedNumber = _dialedNumber!;

      _callStartTime = null;
      _dialedNumber = null;

      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          CallTracker.processCallResult(
            context,
            dialedNumber,
            startTime,
            farmerId: _farmer['id'].toString(),
          );
        }
      });
    }
  }

  void _initiateCall() {
    final number = _farmer['mobile']?.toString();
    if (number == null || number.isEmpty) return;

    _callStartTime = DateTime.now();
    _dialedNumber = number;
    CallTracker.makeCall(context, number, farmerId: _farmer['id'].toString());
  }

  Future<void> _loadFarms() async {
    try {
      final profile = await SupabaseService.getProfile();
      final farms = await SupabaseService.getFarmsByFarmer(_farmer['id']);
      if (mounted) {
        setState(() {
          _userRole = profile?['role'];
          _farms = farms;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Farmer'),
            content: Text(
              'Are you sure you want to delete ${_farmer['name']}? This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        debugPrint(
          'Attempting to delete farmer with ID: ${_farmer['id']} (type: ${_farmer['id'].runtimeType})',
        );
        await SupabaseService.deleteFarmer(_farmer['id'].toString());

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Farmer Deleted Successfully'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true); // Return true to refresh list
        }
      } catch (e) {
        debugPrint('Delete error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Delete failed: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleEdit() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AddFarmerScreen(farmer: _farmer)),
    );

    if (result != null && result is Map) {
      // The edit screen returned the updated data directly — apply it immediately
      if (mounted) {
        setState(() {
          // Merge the returned data into existing farmer, preserving any fields
          // not included in the edit form (e.g. is_verified, assigned_to)
          _farmer = {..._farmer, ...Map<String, dynamic>.from(result)};
        });
      }
    } else if (result == true) {
      // Fallback: if only 'true' was returned, do a network re-fetch
      _refreshFarmer();
    }
  }

  Future<void> _refreshFarmer() async {
    setState(() => _isLoading = true);
    try {
      final farmerId = _farmer['id'].toString();
      
      // Fetch fresh data
      Map<String, dynamic>? updatedFarmer;
      
      if (kIsWeb) {
        // On web, fetch from remote
        final remote = await SupabaseService.getFarmerDetail(farmerId);
        if (remote != null) updatedFarmer = remote;
      } else {
        // On mobile, try local first then remote
        final local = await LocalDatabaseService.getDataById('farmers', farmerId);
        if (local != null) {
          updatedFarmer = local;
        } else {
          final remote = await SupabaseService.getFarmerDetail(farmerId);
          if (remote != null) updatedFarmer = remote;
        }
      }

      if (mounted && updatedFarmer != null) {
        setState(() {
          _farmer = updatedFarmer!;
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error refreshing farmer: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleVerify() async {
    setState(() => _isLoading = true);
    try {
      await SupabaseService.verifyItem(
        'farmers',
        _farmer['id'],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Farmer Verified Successfully'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _farmer['is_verified'] = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final width = MediaQuery.sizeOf(context).width;
    final bool isWide = width > 1100;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Farmer Details',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        actions: [
          // Show edit/delete buttons only for non-managers if not verified
          // Admins can always edit (assuming admin role exists and is allowed)
          if ((_userRole == 'admin') || (_userRole != 'manager' && _farmer['is_verified'] != true)) ...[
            IconButton(
              icon: const Icon(Icons.edit_rounded, color: AppColors.primary),
              onPressed: _isLoading ? null : _handleEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              onPressed: _isLoading ? null : _handleDelete,
            ),
          ],
          if (_userRole == 'manager' && _farmer['is_verified'] != true)
            IconButton(
              icon: const Icon(Icons.verified_user_rounded, color: Colors.green),
              onPressed: _isLoading ? null : _handleVerify,
            ),const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isWide ? 1200 : 800),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 8.0,
            ),
            child: isWide ? _buildWideLayout() : _buildMobileLayout(),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProfileHeader(),
        const SizedBox(height: 32),
        _buildInformationCard(isWide: false),
        const SizedBox(height: 32),
        _buildFarmsSection(),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildWideLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildWideHeader(),
        const SizedBox(height: 32),
        _buildInformationCard(isWide: true),
        const SizedBox(height: 32),
        _buildFarmsSection(),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildWideHeader() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(color: Colors.black.withOpacity(0.02)),
      ),
      child: Row(
        children: [
          _buildAvatar(size: 100),
          const SizedBox(width: 32),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _farmer['name'] ?? 'N/A',
                      style: GoogleFonts.outfit(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textBlack,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (_farmer['is_verified'] == true) _buildVerifiedBadge(),
                  ],
                ),
                const SizedBox(height: 8),
                if (_farmer['is_verified'] == true) ...[
                  _buildRiseTokenButton(),
                  const SizedBox(height: 8),
                ],
                _buildCategoryBadge(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInformationCard({required bool isWide}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Information',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textBlack,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
            border: Border.all(color: Colors.black.withOpacity(0.02)),
          ),
          child: isWide ? _buildWideInfoContent() : _buildMobileInfoContent(),
        ),
      ],
    );
  }

  Widget _buildMobileInfoContent() {
    return Column(
      children: [
        _phoneNumberSection(),
        const Divider(height: 32, thickness: 0.5),
        _infoSection(
          Icons.location_on_rounded,
          'Village',
          _farmer['village'] ?? 'N/A',
        ),
        ..._buildDetailedAddressSections(),
      ],
    );
  }

  Widget _buildWideInfoContent() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildInfoTile(
                icon: Icons.phone_rounded,
                label: 'Mobile Number',
                value: _farmer['mobile'] ?? 'N/A',
                onAction:
                    (_farmer['mobile'] != null &&
                            _farmer['mobile'].toString().isNotEmpty)
                        ? _initiateCall
                        : null,
                actionIcon: Icons.call_rounded,
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: _buildInfoTile(
                icon: Icons.location_on_rounded,
                label: 'Village',
                value: _farmer['village'] ?? 'N/A',
                iconColor: Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        ..._buildDetailedAddressSections(isWide: true),
      ],
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onAction,
    IconData? actionIcon,
    Color? iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.background.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (iconColor ?? AppColors.primary).withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              color: iconColor ?? AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.outfit(
                    color: AppColors.textGray.withOpacity(0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textBlack,
                  ),
                ),
              ],
            ),
          ),
          if (onAction != null)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onAction,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withOpacity(0.2)),
                  ),
                  child: Icon(
                    actionIcon ?? Icons.call_rounded,
                    color: Colors.green,
                    size: 20,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWideProfileCard() {
    // Kept for potential future use or backward compatibility if needed, 
    // but the single column wide layout is now primary.
    return _buildWideHeader();
  }

  Widget _buildAvatar({double size = 120}) {
    return Hero(
      tag: 'farmer_icon_${_farmer['id']}',
      child: Container(
        height: size,
        width: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _getCategoryColor(_farmer['category']).withOpacity(0.8),
              _getCategoryColor(_farmer['category']),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(size * 0.25),
          boxShadow: [
            BoxShadow(
              color: _getCategoryColor(_farmer['category']).withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Center(
          child: Text(
            _getInitials(_farmer['name'] ?? 'F'),
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.33,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryBadge({bool isSmall = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmall ? 8 : 10,
        vertical: isSmall ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: _getCategoryColor(_farmer['category']).withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _farmer['category'].toString().toUpperCase(),
        style: TextStyle(
          color: _getCategoryColor(_farmer['category']),
          fontSize: isSmall ? 9 : 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildVerifiedBadge() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.verified_rounded, color: Colors.blue, size: 24),
    );
  }

  Widget _buildRiseTokenButton() {
    return TextButton.icon(
      onPressed: () {
        EditRequestDialog.show(
          context,
          entityType: 'farmers',
          entityId: _farmer['id'].toString(),
          currentData: _farmer,
          fieldMap: {
            'name': 'Full Name',
            'mobile': 'Mobile Number',
            'village': 'Village',
            'taluk': 'Taluk',
            'district': 'District',
            'landmark': 'Landmark',
            'category': 'Category',
          },
        );
      },
      icon: const Icon(Icons.add_alert_rounded, size: 16, color: Colors.orange),
      label: const Text(
        'Rise Token',
        style: TextStyle(
          color: Colors.orange,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
      style: TextButton.styleFrom(
        backgroundColor: Colors.orange.withOpacity(0.1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Column(
      children: [
        Center(
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              _buildAvatar(size: 120),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: _buildCategoryBadge(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _farmer['name'] ?? 'N/A',
                  style: GoogleFonts.outfit(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textBlack,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_farmer['is_verified'] == true) ...[
                const SizedBox(width: 8),
                _buildVerifiedBadge(),
              ],
            ],
          ),
        ),
        if (_farmer['is_verified'] == true) ...[
          const SizedBox(height: 12),
          Center(child: _buildRiseTokenButton()),
        ],
      ],
    );
  }



  Widget _buildFarmsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Farms & Crops',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textBlack,
          ),
        ),
        const SizedBox(height: 16),
        if (_farms.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.secondary),
            ),
            child: const Row(
              children: [
                Icon(Icons.agriculture_rounded, color: AppColors.primary),
                SizedBox(width: 16),
                Text('No farms added yet'),
              ],
            ),
          )
        else
          Column(children: _farms.map((farm) => _farmItem(farm)).toList()),
        _buildActionButtons(),
      ],
    );
  }

  Widget _buildActionButtons() {
    if (_userRole != 'manager') {
      return Column(
        children: [
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => AddFarmScreen(farmerId: _farmer['id']),
                ),
              );
              _loadFarms();
            },
            icon: const Icon(Icons.add_location_alt_rounded),
            label: const Text('Add New Farm'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary.withOpacity(0.5)),
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 0,
            ),
          ),
        ],
      );
    } else if (_farmer['is_verified'] != true) {
      return Column(
        children: [
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _handleVerify,
            icon: const Icon(Icons.verified_rounded),
            label: const Text('Verify Entry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 8,
              shadowColor: AppColors.primary.withOpacity(0.3),
            ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _farmItem(Map<String, dynamic> farm) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withOpacity(0.03)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FarmDetailScreen(farm: farm),
              ),
            );
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.agriculture_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        farm['name'] ?? farm['place'] ?? 'N/A',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppColors.textBlack,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${farm['area'] ?? '0'} Acres • ${farm['place'] ?? ''}',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: AppColors.textGray.withOpacity(0.8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: AppColors.textGray,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _phoneNumberSection() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.phone_rounded,
            color: AppColors.primary,
            size: 22,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mobile Number',
                style: GoogleFonts.outfit(
                  color: AppColors.textGray.withOpacity(0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _farmer['mobile'] ?? 'N/A',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textBlack,
                ),
              ),
            ],
          ),
        ),
        if (_farmer['mobile'] != null &&
            _farmer['mobile'].toString().isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: IconButton(
              onPressed: _initiateCall,
              icon: const Icon(
                Icons.call_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildDetailedAddressSections({bool isWide = false}) {
    final String addr = _farmer['address'] ?? '';
    final List<String> parts = addr.split('\n');
    
    if (parts.length >= 3) {
      if (isWide) {
        return [
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildInfoTile(
                  icon: Icons.map_rounded,
                  label: 'Taluk',
                  value: parts[0].isEmpty ? 'N/A' : parts[0],
                  iconColor: Colors.teal,
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _buildInfoTile(
                  icon: Icons.domain_rounded,
                  label: 'District',
                  value: parts[1].isEmpty ? 'N/A' : parts[1],
                  iconColor: Colors.indigo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildInfoTile(
            icon: Icons.add_location_alt_rounded,
            label: 'Landmark',
            value: parts[2].isEmpty ? 'N/A' : parts[2],
            iconColor: Colors.pink,
          ),
        ];
      } else {
        return [
          const Divider(height: 32, thickness: 0.5),
          _infoSection(Icons.map_rounded, 'Taluk', parts[0].isEmpty ? 'N/A' : parts[0]),
          const Divider(height: 32, thickness: 0.5),
          _infoSection(Icons.domain_rounded, 'District', parts[1].isEmpty ? 'N/A' : parts[1]),
          const Divider(height: 32, thickness: 0.5),
          _infoSection(Icons.add_location_alt_rounded, 'Landmark', parts[2].isEmpty ? 'N/A' : parts[2]),
        ];
      }
    } else {
      // Fallback for old records
      if (isWide) {
        return [
          const SizedBox(height: 24),
          _buildInfoTile(
            icon: Icons.home_work_rounded,
            label: 'Address',
            value: addr.isEmpty ? 'N/A' : addr,
            iconColor: Colors.blue,
          ),
        ];
      } else {
        return [
          const Divider(height: 32, thickness: 0.5),
          _infoSection(Icons.home_work_rounded, 'Address', addr.isEmpty ? 'N/A' : addr),
        ];
      }
    }
  }

  Widget _infoSection(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.background.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: AppColors.textGray.withOpacity(0.7),
            size: 22,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.outfit(
                  color: AppColors.textGray.withOpacity(0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textBlack,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return 'F';
    final parts = name.trim().split(' ');
    if (parts.length > 1) {
      return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
    } else if (parts[0].length > 1) {
      return parts[0].substring(0, 2).toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  Color _getCategoryColor(String? category) {
    switch (category) {
      case 'Hot':
        return AppColors.hot;
      case 'Warm':
        return AppColors.warm;
      case 'Cold':
        return AppColors.cold;
      default:
        return AppColors.warm;
    }
  }
}
