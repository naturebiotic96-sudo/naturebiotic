import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nature_biotic/core/theme.dart';
import 'package:nature_biotic/services/supabase_service.dart';
import 'package:nature_biotic/services/local_database_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:nature_biotic/features/reports/screens/report_generator_screen.dart';
import 'package:intl/intl.dart';
import 'package:nature_biotic/features/crops/screens/add_crop_screen.dart';
import 'package:nature_biotic/features/reports/screens/create_report_screen.dart';
import 'package:nature_biotic/features/profile/screens/edit_request_dialog.dart';

class CropDetailScreen extends StatefulWidget {
  final Map<String, dynamic> crop;
  final String? farmName;
  final String? farmerName;

  const CropDetailScreen({
    super.key,
    required this.crop,
    this.farmName,
    this.farmerName,
  });

  @override
  State<CropDetailScreen> createState() => _CropDetailScreenState();
}

class __CropDetailScreenState extends State<CropDetailScreen> {
  List<Map<String, dynamic>> _reports = [];
  String? _userRole;
  bool _isLoadingReports = true;
  late Map<String, dynamic> _crop;

  @override
  void initState() {
    super.initState();
    _crop = widget.crop;
    _loadUserRole();
    _loadReports();
  }

  Future<void> _loadUserRole() async {
    final profile = await SupabaseService.getProfile();
    if (mounted) {
      setState(() {
        _userRole = profile?['role'];
      });
    }
  }

  Future<void> _loadReports() async {
    try {
      final farmId = widget.crop['farm_id']?.toString();
      final remoteReports = await SupabaseService.getReportsForCrop(
        widget.crop['id'].toString(),
        cropName: widget.crop['name'],
        farmId: farmId,
      );
      List<Map<String, dynamic>> localReports = [];

      if (!kIsWeb) {
        final cropName = widget.crop['name'] ?? '';
        localReports = await LocalDatabaseService.getData(
          'reports',
          where: 'farm_id = ? AND (crop_id = ? OR problem LIKE ?)',
          whereArgs: [farmId ?? '', widget.crop['id'].toString(), '%--- Crop: $cropName ---%'],
          columns: [
            'id',
            'farm_id',
            'crop_id',
            'problem',
            'previous_inputs',
            'recommendations',
            'estimated_cost',
            'signature_url',
            'created_by',
            'created_at',
          ],
        );
      }

      if (mounted) {
        setState(() {
          // Merge and De-duplicate
          final Map<String, Map<String, dynamic>> combinedMap = {};

          for (var report in localReports) {
            combinedMap[report['id'].toString()] = report;
          }
          for (var report in remoteReports) {
            combinedMap[report['id'].toString()] = report;
          }

          _reports = combinedMap.values.toList();
          _reports.sort(
            (a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''),
          );
          _isLoadingReports = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingReports = false);
    }
  }

  @override
  Widget build(BuildContext context) {

    final width = MediaQuery.sizeOf(context).width;
    final bool isWide = width > 1100;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.crop['name'] ?? 'Crop Details'),
        actions: [
          if (_userRole == 'admin' || (_userRole != 'manager' && _crop['is_verified'] != true))
            IconButton(
              icon: const Icon(Icons.edit_rounded),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => AddCropScreen(
                          crop: _crop,
                          farmId: _crop['farm_id']?.toString(),
                        ),
                  ),
                ).then((value) {
                  if (value == true) {
                    Navigator.pop(context, true);
                  }
                });
              },
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Info
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.eco_rounded,
                          size: 28,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _crop['variety'] ?? 'Unknown Variety',
                              style: const TextStyle(
                                color: AppColors.textGray,
                                fontSize: 11,
                              ),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _crop['name'] ?? 'N/A',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (_crop['is_verified'] == true)
                                  const Icon(Icons.verified_rounded, color: Colors.blue, size: 18),
                              ],
                            ),
                            if (_crop['is_verified'] == true) ...[
                              const SizedBox(height: 6),
                              _buildRiseTokenButton(),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                if (_userRole == 'manager' && _crop['is_verified'] != true) ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          await SupabaseService.verifyItem('crops', _crop['id']);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Crop Verified Successfully'), backgroundColor: Colors.green),
                            );
                            setState(() => _crop['is_verified'] = true);
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Verification failed: $e'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.verified_user_rounded),
                      label: const Text('Verify Crop Entry', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                const Text(
                  'Crop Metrics',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textBlack,
                  ),
                ),
                const SizedBox(height: 16),

                // Grid for Growth and Scale
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isGridWide = constraints.maxWidth > 600;
                    return GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: isGridWide ? 4 : 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: isGridWide ? 1.5 : 2.2,
                      children: [
                        _infoCard(
                          Icons.history_rounded,
                          'Current Age',
                          widget.crop['age'] ?? 'N/A',
                        ),
                        _infoCard(
                          Icons.timer_rounded,
                          'Total Life',
                          widget.crop['life'] ?? 'N/A',
                        ),
                        _infoCard(
                          Icons.straighten_rounded,
                          'Acres',
                          widget.crop['acre'] ?? 'N/A',
                        ),
                        _infoCard(
                          Icons.numbers_rounded,
                          'Count',
                          widget.crop['count'] ?? 'N/A',
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 24),
                const Text(
                  'Yield Expectations',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textBlack,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.shadow.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.show_chart_rounded,
                        color: AppColors.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Expected Yield',
                            style: TextStyle(
                              color: AppColors.textGray,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            widget.crop['expected_yield'] ?? 'N/A',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                if (_userRole != 'manager')
                  const SizedBox(height: 32),
                if (_userRole != 'manager')
                  Center(
                    child: SizedBox(
                      width: isWide ? 400 : double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => CreateReportScreen(
                                    preSelectedFarmId:
                                        _crop['farm_id']?.toString(),
                                    preSelectedCropId:
                                        _crop['id']?.toString(),
                                  ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.add_task_rounded),
                        label: const Text(
                          'Add New Visit (Analysis Report)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 2,
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 48),
                Center(
                  child: Text(
                    'Report History',
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textBlack,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _buildReportHistoryTable(isWide: isWide),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReportHistoryTable({bool isWide = false}) {
    if (_isLoadingReports) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_reports.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.secondary.withOpacity(0.3),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Column(
          children: [
            Icon(
              Icons.assignment_outlined,
              size: 40,
              color: AppColors.textGray,
            ),
            SizedBox(height: 12),
            Text(
              'No report history available',
              style: TextStyle(color: AppColors.textGray),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: isWide ? 860 : 0),
            child: DataTable(
              horizontalMargin: isWide ? 24 : 16,
              columnSpacing: isWide ? 48 : 24,
              headingRowColor: WidgetStateProperty.all(
                AppColors.secondary.withOpacity(0.5),
              ),
              columns: [
                const DataColumn(
                  label: Text(
                    'Date',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const DataColumn(
                  label: Text(
                    'Problem Identified',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (isWide)
                  const DataColumn(
                    label: Text(
                      'Recommendations',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                const DataColumn(
                  label: Text('', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
              rows:
                  _reports.map((report) {
                    final date = DateTime.parse(report['created_at']);
    
                    // Clean up problem text (remove image metadata if present)
                    String problemDisplay = report['problem'] ?? 'N/A';
                    if (problemDisplay.contains('{img:')) {
                      problemDisplay = problemDisplay.split('{img:')[0].trim();
                    }
    
                    return DataRow(
                      cells: [
                        DataCell(
                          Text(
                            DateFormat('MMM dd, yyyy').format(date),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        DataCell(
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: isWide ? 220 : 180),
                            child: Text(
                              problemDisplay,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                        if (isWide)
                          DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 300),
                              child: Text(
                                report['recommendations'] ?? 'N/A',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                        DataCell(
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (context) => ReportGeneratorScreen(
                                        report: report,
                                        farmName: widget.farmName,
                                        cropName: widget.crop['name'],
                                        farmerName: widget.farmerName,
                                      ),
                                ),
                              );
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'View More',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoCard(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textGray,
                    fontSize: 9,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiseTokenButton() {
    return TextButton.icon(
      onPressed: () {
        EditRequestDialog.show(
          context,
          entityType: 'crops',
          entityId: _crop['id'].toString(),
          currentData: _crop,
          fieldMap: {
            'name': 'Crop Name',
            'variety': 'Variety',
            'age': 'Current Age',
            'life': 'Total Life',
            'acre': 'Acres',
            'count': 'Count / Trees',
            'expected_yield': 'Expected Yield',
          },
        );
      },
      icon: const Icon(
        Icons.add_alert_rounded,
        size: 14,
        color: Colors.orange,
      ),
      label: const Text(
        'Rise Token',
        style: TextStyle(
          color: Colors.orange,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
      style: TextButton.styleFrom(
        backgroundColor: Colors.orange.withOpacity(0.1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

class _CropDetailScreenState extends __CropDetailScreenState {}
