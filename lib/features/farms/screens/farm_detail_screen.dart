import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import 'package:intl/intl.dart';
import 'package:nature_biotic/core/theme.dart';
import 'package:nature_biotic/services/supabase_service.dart';
import 'package:nature_biotic/features/crops/screens/add_crop_screen.dart';
import 'package:nature_biotic/features/crops/screens/crop_detail_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nature_biotic/services/local_database_service.dart';
import 'package:nature_biotic/features/farms/screens/stock_management_screen.dart';
import 'package:nature_biotic/features/farms/screens/collection_history_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:nature_biotic/core/call_tracker.dart';
import 'dart:convert';
import 'package:nature_biotic/features/profile/screens/edit_request_dialog.dart';

class FarmDetailScreen extends StatefulWidget {
  final Map<String, dynamic> farm;

  const FarmDetailScreen({super.key, required this.farm});

  @override
  State<FarmDetailScreen> createState() => _FarmDetailScreenState();
}

class _FarmDetailScreenState extends State<FarmDetailScreen> with WidgetsBindingObserver {
  late Map<String, dynamic> _farm;
  List<Map<String, dynamic>> _crops = [];
  Map<String, dynamic>? _farmer;
  bool _isAdmin = false;
  bool _isManager = false;
  bool _isLoading = true;

  // Tracking
  DateTime? _callStartTime;
  String? _dialedNumber;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _farm = widget.farm;
    _checkAdminStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _callStartTime != null && _dialedNumber != null) {
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
            farmerId: _farm['farmer_id'].toString()
          );
        }
      });
    }
  }

  void _initiateCall() {
    final number = _farmer?['mobile']?.toString();
    if (number == null || number.isEmpty) return;

    _callStartTime = DateTime.now();
    _dialedNumber = number;
    CallTracker.makeCall(context, number, farmerId: _farm['farmer_id'].toString());
  }

  void _callAdditionalContact(String name, String number) {
    if (number.isEmpty) return;
    _callStartTime = DateTime.now();
    _dialedNumber = number;
    CallTracker.makeCall(context, number, farmerId: _farm['farmer_id'].toString());
  }

  List<Map<String, dynamic>> _getContacts() {
    final dynamic contactsData = _farm['contacts'];
    if (contactsData == null) return [];
    
    try {
      if (contactsData is String) {
        return List<Map<String, dynamic>>.from(jsonDecode(contactsData));
      } else if (contactsData is List) {
        return List<Map<String, dynamic>>.from(contactsData);
      }
    } catch (e) {
      debugPrint('Error parsing contacts in detail screen: $e');
    }
    return [];
  }

  Future<void> _checkAdminStatus() async {
    final profile = await SupabaseService.getProfile();
    if (mounted) {
      setState(() {
        _isAdmin = profile?['role'] == 'admin';
        _isManager = profile?['role'] == 'manager';
        _isLoading = false;
      });
      _loadAssignedExecutive();
      _loadCrops();
      _loadFarmer();
    }
  }

  Future<void> _loadFarmer() async {
    if (_farm['farmer_id'] != null) {
      try {
        final response = await SupabaseService.client
            .from('farmers')
            .select()
            .eq('id', _farm['farmer_id'])
            .maybeSingle();
        if (mounted) {
          setState(() {
            _farmer = response;
          });
        }
      } catch (e) {
        debugPrint('Error loading farmer: $e');
      }
    }
  }

  Future<void> _loadCrops() async {
    try {
      final remoteCrops = await SupabaseService.getCrops(_farm['id']);
      List<Map<String, dynamic>> localCrops = [];
      
      if (!kIsWeb) {
        localCrops = await LocalDatabaseService.getData(
          'crops', 
          where: 'farm_id = ?', 
          whereArgs: [_farm['id'].toString()]
        );
      }

      if (mounted) {
        setState(() {
          // Merge and De-duplicate
          final Map<String, Map<String, dynamic>> combinedMap = {};
          
          for (var crop in remoteCrops) {
            combinedMap[crop['id'].toString()] = crop;
          }
          for (var crop in localCrops) {
            combinedMap[crop['id'].toString()] = crop;
          }

          _crops = combinedMap.values.toList();
          _crops.sort((a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));
        });
      }
    } catch (e) {
      debugPrint('Error loading crops: $e');
    }
  }

  Future<void> _loadAssignedExecutive() async {
    if (_farm['assigned_to'] != null && _farm['assigned_executive'] == null) {
      final executive = await SupabaseService.getProfileById(_farm['assigned_to']);
      if (mounted) {
        setState(() {
          _farm['assigned_executive'] = executive;
        });
      }
    }
  }

  Future<void> _showAssignDialog() async {
    showDialog(
      context: context,
      builder: (context) => _AssignExecutiveDialog(
        currentAssignedId: _farm['assigned_to'],
        onAssign: (executive) async {
          await SupabaseService.assignFarm(_farm['id'], executive?['id']);
          // Refresh local state
          setState(() {
            _farm['assigned_to'] = executive?['id'];
            _farm['assigned_executive'] = executive;
          });
          if (mounted) Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final assignedExecutive = _farm['assigned_executive'];
    final executiveName = assignedExecutive?['full_name'] ?? 'Not Assigned';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Farm Details',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Summary Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, Color(0xFF2E7D32)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(Icons.agriculture_rounded, size: 36, color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _farm['name'] ?? 'Farm Record',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 22,
                                      letterSpacing: -0.5,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (_farm['is_verified'] == true) 
                                  const Icon(
                                    Icons.verified_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                              ],
                            ),
                            if (_farm['is_verified'] == true) ...[
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: _buildRiseTokenButton(),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              'Registered: ${_formatDate(_farm['created_at'])}',
                              style: GoogleFonts.outfit(
                                color: Colors.white.withOpacity(0.85),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                if (_isManager && _farm['is_verified'] != true) ...[
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () async {
                            setState(() => _isLoading = true);
                            try {
                              await SupabaseService.verifyItem(
                                'farms',
                                _farm['id'],
                              );
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Farm Verified Successfully'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                                setState(() {
                                  _farm['is_verified'] = true;
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
                          },
                    icon: const Icon(Icons.verified_rounded),
                    label: const Text('Verify Farm Entry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 64),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      elevation: 8,
                      shadowColor: AppColors.primary.withOpacity(0.3),
                    ),
                  ),
                ],
                
                if (_isAdmin) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                      border: Border.all(color: Colors.black.withOpacity(0.02)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.admin_panel_settings_rounded, color: AppColors.primary, size: 20),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Assigned Executive', 
                                style: GoogleFonts.outfit(
                                  color: AppColors.textGray.withOpacity(0.6), 
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                )
                              ),
                              Text(
                                executiveName, 
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w700, 
                                  fontSize: 15,
                                  color: AppColors.textBlack,
                                )
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _showAssignDialog,
                          style: TextButton.styleFrom(
                            backgroundColor: AppColors.primary.withOpacity(0.05),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text(
                            'Change', 
                            style: GoogleFonts.outfit(
                              fontSize: 12, 
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            )
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
    
                if (_farmer != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                      border: Border.all(color: Colors.black.withOpacity(0.02)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.person_rounded, color: Colors.blue, size: 20),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Farm Owner (Farmer)', 
                                style: GoogleFonts.outfit(
                                  color: AppColors.textGray.withOpacity(0.6), 
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                )
                              ),
                              Row(
                                children: [
                                  Text(
                                    _farmer?['name'] ?? 'N/A', 
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.w700, 
                                      fontSize: 15,
                                      color: AppColors.textBlack,
                                    )
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.verified_rounded, size: 14, color: Colors.blue),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (_farmer?['mobile'] != null)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: IconButton(
                              onPressed: _initiateCall,
                              icon: const Icon(Icons.call_rounded, color: Colors.white, size: 18),
                              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
    
                const SizedBox(height: 32),
                Text(
                  'Farm Information', 
                  style: GoogleFonts.outfit(
                    fontSize: 20, 
                    fontWeight: FontWeight.w800, 
                    color: AppColors.textBlack,
                    letterSpacing: -0.5,
                  )
                ),
                const SizedBox(height: 16),
                
                // Grid of Info Cards
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 600;
                    return GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: isWide ? 3 : 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: isWide ? 2.5 : 1.8,
                      children: [
                        _infoCard(Icons.location_on_rounded, 'Place', _farm['place'] ?? 'N/A'),
                        _infoCard(Icons.straighten_rounded, 'Area', '${_farm['area'] ?? '0'} Acres'),
                        _infoCard(Icons.grain_rounded, 'Soil', _farm['soil_type'] ?? 'N/A'),
                        _infoCard(Icons.water_rounded, 'Irrigation', _farm['irrigation_type'] ?? 'N/A'),
                        _infoCard(Icons.waves_rounded, 'Source', _farm['water_source'] ?? 'N/A'),
                        _infoCard(Icons.inventory_2_rounded, 'Qty', _farm['water_quantity'] ?? 'N/A'),
                        _infoCard(Icons.bolt_rounded, 'Power', _farm['power_source'] ?? 'N/A'),
                        _infoCard(
                          Icons.layers_rounded, 
                          'Strategy', 
                          (_farm['intercrop']?.toString() == 'Yes' 
                              ? 'Intercrop' 
                              : _farm['intercrop']?.toString() == 'No' 
                                  ? 'Normal' 
                                  : (_farm['intercrop'] ?? 'Normal'))
                        ),
                        if (_farm['report_url'] != null && _farm['report_url'].toString().isNotEmpty)
                          GestureDetector(
                            onTap: () async {
                              final uri = Uri.parse(_farm['report_url']);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            },
                            child: _infoCard(
                              Icons.assignment_rounded, 
                              'Report', 
                              'View Report',
                              isLink: true,
                            ),
                          ),
                      ],
                    );
                  }
                ),
                
                const SizedBox(height: 24),
                
                if (_getContacts().isNotEmpty) ...[
                  const SizedBox(height: 32),
                  Text(
                    'Additional Contacts', 
                    style: GoogleFonts.outfit(
                      fontSize: 18, 
                      fontWeight: FontWeight.w800, 
                      color: AppColors.textBlack,
                    )
                  ),
                  const SizedBox(height: 16),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _getContacts().length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final contact = _getContacts()[index];
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                          border: Border.all(color: Colors.black.withOpacity(0.02)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.secondary.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.contact_phone_rounded, color: AppColors.primary, size: 20),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    contact['name'] ?? 'Additional Contact', 
                                    style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 14)
                                  ),
                                  Text(
                                    contact['phone'] ?? 'No number', 
                                    style: GoogleFonts.outfit(color: AppColors.textGray.withOpacity(0.6), fontSize: 12, fontWeight: FontWeight.w500)
                                  ),
                                ],
                              ),
                            ),
                            if (contact['phone'] != null && contact['phone'].toString().isNotEmpty)
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: IconButton(
                                  onPressed: () => _callAdditionalContact(contact['name'] ?? 'Contact', contact['phone'].toString()),
                                  icon: const Icon(Icons.call_rounded, color: Colors.white, size: 18),
                                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                ],

                const SizedBox(height: 32),
                Text(
                  'Crops in this Farm', 
                  style: GoogleFonts.outfit(
                    fontSize: 20, 
                    fontWeight: FontWeight.w800, 
                    color: AppColors.textBlack,
                    letterSpacing: -0.5,
                  )
                ),
                const SizedBox(height: 16),
                if (_crops.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.black.withOpacity(0.02)),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.eco_rounded, size: 48, color: AppColors.primary.withOpacity(0.1)),
                        const SizedBox(height: 12),
                        Text(
                          'No crops added yet', 
                          style: GoogleFonts.outfit(
                            color: AppColors.textGray, 
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          )
                        ),
                      ],
                    ),
                  )
                else
                  SizedBox(
                    height: 200,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: _crops.length,
                      itemBuilder: (context, index) {
                        final crop = _crops[index];
                        return _cropCard(crop);
                      },
                    ),
                  ),
                
                if (!_isManager) ...[
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AddCropScreen(farmId: _farm['id']),
                        ),
                      );
                      if (result == true) {
                        _loadCrops();
                      }
                    },
                    icon: const Icon(Icons.add_task_rounded),
                    label: const Text('Add New Crop'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary.withOpacity(0.5)),
                      minimumSize: const Size(double.infinity, 64),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      elevation: 0,
                    ),
                  ),
                ],
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cropCard(Map<String, dynamic> crop) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CropDetailScreen(
              crop: crop,
              farmName: _farm['name'],
              farmerName: _farmer?['name'],
            ),
          ),
        );
      },
      child: Container(
        width: 200,
        margin: const EdgeInsets.only(right: 16, bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
          border: Border.all(color: Colors.black.withOpacity(0.02)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.eco_rounded, color: Colors.green, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    crop['name'] ?? 'N/A',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w800, 
                      fontSize: 16,
                      color: AppColors.textBlack,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (crop['is_verified'] == true)
                  const Icon(Icons.verified_rounded, color: Colors.blue, size: 16),
              ],
            ),
            if (crop['is_verified'] != true) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange.withOpacity(0.2)),
                ),
                child: const Text(
                  'PENDING',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Variety: ${crop['variety'] ?? 'N/A'}', 
              style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textGray.withOpacity(0.6), fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              'Area: ${crop['acre'] ?? 'N/A'} Acre', 
              style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textGray.withOpacity(0.6), fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${crop['count'] ?? 'N/A'} Nos', 
                      style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary)
                    ),
                    Text(
                      crop['age'] ?? 'N/A', 
                      style: GoogleFonts.outfit(fontSize: 10, color: AppColors.textGray.withOpacity(0.5), fontWeight: FontWeight.w700)
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.primary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(IconData icon, String label, String value, {bool isLink = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isLink ? AppColors.primary.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isLink ? AppColors.primary.withOpacity(0.2) : Colors.black.withOpacity(0.01),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isLink ? AppColors.primary.withOpacity(0.1) : AppColors.background.withOpacity(0.8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label, 
                  style: GoogleFonts.outfit(
                    color: AppColors.textGray.withOpacity(0.6), 
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  )
                ),
                const SizedBox(height: 2),
                Text(
                  value, 
                  style: GoogleFonts.outfit(
                    fontSize: 14, 
                    fontWeight: FontWeight.w700,
                    color: isLink ? AppColors.primary : AppColors.textBlack,
                    decoration: isLink ? TextDecoration.underline : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic dateStr) {
    if (dateStr == null || dateStr.toString().isEmpty) return 'N/A';
    try {
      final date = DateTime.parse(dateStr.toString());
      return DateFormat('MMMM dd, yyyy').format(date);
    } catch (_) {
      return dateStr.toString();
    }
  }

  Widget _buildRiseTokenButton() {
    return TextButton.icon(
      onPressed: () {
        EditRequestDialog.show(
          context,
          entityType: 'farms',
          entityId: _farm['id'].toString(),
          currentData: _farm,
          fieldMap: {
            'name': 'Farm Name',
            'area': 'Area (Acres)',
            'soil_type': 'Soil Type',
            'irrigation_type': 'Irrigation Type',
            'water_source': 'Water Source',
            'water_quantity': 'Water Quantity',
            'power_source': 'Power Source',
            'landmark': 'Landmark',
            'intercrop': 'Intercrop Strategy',
          },
        );
      },
      icon: const Icon(
        Icons.add_alert_rounded,
        size: 14,
        color: Colors.orangeAccent,
      ),
      label: const Text(
        'Rise Token',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
      style: TextButton.styleFrom(
        backgroundColor: Colors.orange.withOpacity(0.2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.orange.withOpacity(0.5)),
        ),
      ),
    );
  }
}

class _AssignExecutiveDialog extends StatefulWidget {
  final String? currentAssignedId;
  final Function(Map<String, dynamic>?) onAssign;

  const _AssignExecutiveDialog({this.currentAssignedId, required this.onAssign});

  @override
  State<_AssignExecutiveDialog> createState() => _AssignExecutiveDialogState();
}

class _AssignExecutiveDialogState extends State<_AssignExecutiveDialog> {
  List<Map<String, dynamic>> _executives = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadExecutives();
  }

  Future<void> _loadExecutives() async {
    final data = await SupabaseService.getExecutives();
    if (mounted) {
      setState(() {
        _executives = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Assign Executive'),
      content: _isLoading 
        ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
        : SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _executives.length + 1, // +1 for "Unassign"
              itemBuilder: (context, index) {
                if (index == 0) {
                  return ListTile(
                    leading: const Icon(Icons.person_off_rounded),
                    title: const Text('Unassign'),
                    onTap: () => widget.onAssign(null),
                  );
                }
                final executive = _executives[index - 1];
                final isSelected = widget.currentAssignedId == executive['id'];
                
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.secondary,
                    child: Text(executive['full_name']?[0] ?? 'E'),
                  ),
                  title: Text(executive['full_name'] ?? 'N/A'),
                  subtitle: Text('@${executive['username']}'),
                  trailing: isSelected ? const Icon(Icons.check_circle, color: AppColors.primary) : null,
                  onTap: () => widget.onAssign(executive),
                );
              },
            ),
          ),
    );
  }
}
