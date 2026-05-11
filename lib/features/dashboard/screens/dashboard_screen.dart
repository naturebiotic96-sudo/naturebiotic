import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';
import 'package:nature_biotic/core/theme.dart';
import 'package:nature_biotic/services/supabase_service.dart';
import 'package:nature_biotic/services/local_database_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:nature_biotic/features/auth/screens/create_executive_screen.dart';
import 'package:nature_biotic/features/auth/screens/executive_list_screen.dart';
import 'package:nature_biotic/features/attendance/screens/attendance_screen.dart';
import 'package:intl/intl.dart';
import 'package:nature_biotic/features/reports/screens/reports_list_screen.dart';
import 'package:nature_biotic/features/dashboard/screens/farm_sales_list_screen.dart';
import 'package:nature_biotic/features/auth/screens/login_logs_screen.dart';
import 'package:nature_biotic/features/profile/screens/profile_screen.dart';
import 'package:nature_biotic/features/dashboard/screens/visit_calendar_screen.dart';
import 'package:nature_biotic/features/auth/screens/login_screen.dart';
import 'package:nature_biotic/features/farmers/screens/farmer_list_screen.dart';
import 'package:nature_biotic/features/farms/screens/farm_list_screen.dart';
import 'package:nature_biotic/features/crops/screens/crop_list_screen.dart';
import 'package:nature_biotic/features/farmers/screens/farmer_detail_screen.dart';
import 'package:nature_biotic/features/farms/screens/farm_detail_screen.dart';
import 'package:nature_biotic/features/crops/screens/crop_detail_screen.dart';
import 'package:nature_biotic/features/reports/screens/report_generator_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:nature_biotic/features/expenses/widgets/trip_widgets.dart';
import 'package:nature_biotic/features/dashboard/screens/admin_edit_requests_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  bool _isAdmin = false;
  bool _isManager = false;
  bool _isExecutive = false;
  bool _isTelecaller = false;
  String _userName = 'User';
  String _avatarUrl = '';
  bool _isLoading = true;
  Map<String, dynamic>? _todayAttendance;
  double _totalSalesRevenue = 0.0;
  double _totalReturnValue = 0.0;
  int _totalItemsSold = 0;
  int _totalItemsReturned = 0;
  String _selectedPeriod = 'This Month';
  DateTimeRange? _customDateRange;
  Map<String, dynamic>? _activeTrip;
  final ImagePicker _picker = ImagePicker();

  // Stats
  int _farmerCount = 0;
  int _farmCount = 0;
  int _cropCount = 0;
  int _reportCount = 0;
  int _presentCount = 0;
  int _absentCount = 0;
  int _teamPresentCount = 0;
  int _teamAbsentCount = 0;
  double _salesTarget = 0.0;
  double _totalCollection = 0.0;
  double _totalOutstanding = 0.0;
  double _salesToAchieve = 0.0;

  // Raw Data for local filtering
  List<Map<String, dynamic>> _allTransactions = [];
  List<Map<String, dynamic>> _allFarmers = [];
  List<Map<String, dynamic>> _allFarms = [];
  List<Map<String, dynamic>> _allCrops = [];
  List<Map<String, dynamic>> _allReports = [];
  List<Map<String, dynamic>> _allProducts = [];
  List<Map<String, dynamic>> _allCollections = [];
  List<Map<String, dynamic>> _recentActivities = [];
  List<Map<String, dynamic>> _filteredTransactions = [];
  List<Map<String, dynamic>> _filteredCollections = [];
  List<Map<String, dynamic>> _reminders = [];

  // Scroll & Animation Logic
  late ScrollController _scrollController;
  double _scrollOpacity = 1.0;
  double _scrollScale = 1.0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _loadDashboardData();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final offset = _scrollController.offset;
    setState(() {
      _scrollOpacity = (1 - (offset / 200)).clamp(0.0, 1.0);
      _scrollScale = (1 - (offset / 1000)).clamp(0.8, 1.0);
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final profile = await SupabaseService.getProfile();
      SupabaseService.syncAllDropdownOptions(); // Cache all dropdowns for offline use
      final isAdmin = profile?['role'] == 'admin';
      final isManager = profile?['role'] == 'manager';
      final isExecutive = profile?['role'] == 'executive';
      final isTelecaller = profile?['role'] == 'telecaller';
      final attendance = await SupabaseService.getTodayAttendance();

      Map<String, dynamic>? activeTrip;
      if (isExecutive || isTelecaller || isManager) {
        final userId = SupabaseService.client.auth.currentUser?.id;
        if (userId != null) {
          activeTrip = await SupabaseService.getActiveExpenseForExecutive(
            userId,
          );
        }
      }

      final farmers = await SupabaseService.getFarmers();
      final farms = await SupabaseService.getFarms();
      final crops = await SupabaseService.getAllCrops();
      final reports = await SupabaseService.getReports();
      final remoteTransactions =
          await SupabaseService.getAllStockTransactions();
      final collections = await SupabaseService.getAllCollections();

      List<Map<String, dynamic>> localTransactions = [];
      if (!kIsWeb) {
        var rawLocal = await LocalDatabaseService.getData(
          'stock_transactions',
        );
        // Filter raw local data if user is restricted role to ensure multi-user device isolation
        if (isExecutive || isTelecaller) {
          final uid = SupabaseService.client.auth.currentUser?.id?.toLowerCase();
          rawLocal = rawLocal.where((t) {
            final execId = t['executive_id']?.toString().toLowerCase();
            // Keep it ONLY if it explicitly belongs to this user's ID
            return execId == uid;
          }).toList();
        }
        localTransactions = rawLocal;
      }

      // Merge transactions correctly to avoid duplicates and preserve local-only data (collected_amount)
      final Map<String, Map<String, dynamic>> mergedMap = {};

      // 1. Load remote transactions
      for (var tx in remoteTransactions) {
        mergedMap[tx['id'].toString()] = Map<String, dynamic>.from(tx);
      }

      // 2. Override/Add with local transactions
      for (var tx in localTransactions) {
        final id = tx['id'].toString();
        if (mergedMap.containsKey(id)) {
          // Merge - local data takes priority for keys like 'collected_amount'
          mergedMap[id] = {...mergedMap[id]!, ...tx};
        } else {
          mergedMap[id] = Map<String, dynamic>.from(tx);
        }
      }

      final transactions = mergedMap.values.toList();
      final products = await SupabaseService.getHierarchicalDropdownOptions(
        'product_name',
      );
      final activities = await SupabaseService.getRecentActivities();

      // Attendance Stats
      final personalStats = await SupabaseService.getPersonalMonthlyStats();
      final teamStats =
          isAdmin ? await SupabaseService.getTeamTodayStats() : null;

      if (mounted) {
        setState(() {
          _isAdmin = isAdmin;
          _isManager = isManager;
          _isExecutive = isExecutive;
          _isTelecaller = isTelecaller;
          _userName = profile?['full_name']?.split(' ')[0] ?? 'User';
          _avatarUrl = profile?['avatar_url'] ?? '';
          _todayAttendance = attendance;
          _activeTrip = activeTrip;
          _recentActivities = activities ?? [];

          _allFarmers = farmers ?? [];
          _allFarms = farms ?? [];
          _allCrops = crops ?? [];
          _allReports = reports ?? [];
          _allTransactions = transactions ?? [];
          _allCollections = collections ?? [];
          _allProducts = products ?? [];
          _salesTarget = (profile?['sales_target'] ?? 0.0).toDouble();

          _presentCount = personalStats['present'] ?? 0;
          _absentCount = personalStats['absent'] ?? 0;
          if (teamStats != null) {
            _teamPresentCount = teamStats['present'] ?? 0;
            _teamAbsentCount = teamStats['absent'] ?? 0;
          }

          _applyFilters();
        });
      }
    } catch (e) {
      debugPrint('Error loading dashboard data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dashboard Sync Error: $e'),
            backgroundColor: Colors.red.withOpacity(0.8),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'RETRY',
              textColor: Colors.white,
              onPressed: _loadDashboardData,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    final range = _getDateRangeForPeriod(_selectedPeriod);
    final startDate = range.start;
    final endDate = range.end;
    final currentUserId = SupabaseService.client.auth.currentUser?.id;

    _farmerCount =
        _allFarmers.where((i) => _isInPeriod(i, startDate, endDate)).length;
    _farmCount =
        _allFarms.where((i) => _isInPeriod(i, startDate, endDate)).length;
    _cropCount =
        _allCrops.where((i) => _isInPeriod(i, startDate, endDate)).length;
    _reportCount =
        _allReports.where((i) => _isInPeriod(i, startDate, endDate)).length;

    double revenue = 0;
    double returnValue = 0;
    double itemsSold = 0;
    double itemsReturned = 0;
    double totalCollection = 0;

    final validTransactions =
        _allTransactions.where((tx) {
          final type = tx['transaction_type']?.toString().toUpperCase();
          // Sales are now counted when stock is RECEIVED by the farm.
          // DELIVERED is just field usage (consumption) and doesn't affect billing.
          final isRelevant = type == 'RECEIVED' || type == 'RETURN';
          final periodOk = _isInPeriod(tx, startDate, endDate);
          if (_isExecutive || _isTelecaller) {
            // Robust executive check: handle strings, cases, and pending locals
            final txExecId = tx['executive_id']?.toString().toLowerCase();
            final currentId = currentUserId?.toString().toLowerCase();
            final isOwner = txExecId == currentId;
            return isRelevant && periodOk && isOwner;
          }
          return isRelevant && periodOk;
        }).toList();

    for (var tx in validTransactions) {
      final type = tx['transaction_type'];
      final itemName = tx['item_name']?.toString().trim().toLowerCase();
      final rawUnit = tx['unit']?.toString().trim().toLowerCase() ?? '';
      // Clean unit of packed metadata "{₹...}" for price matching
      final unit = rawUnit.split(' {₹')[0].trim();
      final qty = double.tryParse(tx['quantity']?.toString() ?? '0') ?? 0.0;

      final parent = _allProducts.firstWhere(
        (p) => p['label']?.toString().trim().toLowerCase() == itemName,
        orElse: () => {},
      );

      if (parent.isNotEmpty) {
        final variants = List<Map<String, dynamic>>.from(
          parent['variants'] ?? [],
        );
        final variant = variants.firstWhere(
          (v) => v['label']?.toString().trim().toLowerCase() == unit,
          orElse: () => {},
        );

        if (variant.isNotEmpty) {
          final price =
              double.tryParse(variant['offer_price']?.toString() ?? '0') ?? 0.0;
          final amount = price * qty;

          if (type == 'RECEIVED') {
            revenue += amount;
            itemsSold += qty;
          } else if (type == 'RETURN') {
            revenue -= amount;
            returnValue += amount;
            itemsReturned += qty;
            itemsSold -= qty;
          }
        }
      }
    }
    _totalSalesRevenue = revenue;
    _totalReturnValue = returnValue;
    _totalItemsSold = itemsSold.toInt();
    _totalItemsReturned = itemsReturned.toInt();

    final validCollections = _allCollections.where((c) {
      final periodOk = _isInPeriod(c, startDate, endDate);
      if (_isExecutive || _isTelecaller) {
        final creatorId = c['created_by']?.toString().toLowerCase();
        final currentId = currentUserId?.toString().toLowerCase();
        return periodOk && creatorId == currentId;
      }
      return periodOk;
    }).toList();

    _filteredCollections = validCollections;

    totalCollection = validCollections.fold(
      0.0,
      (sum, c) =>
          sum + (double.tryParse(c['amount']?.toString() ?? '0') ?? 0.0),
    );

    _totalCollection = totalCollection;
    _totalOutstanding = _totalSalesRevenue - totalCollection;

    // Target Logic for field staff (Executive, Telecaller, Manager)
    if (!_isAdmin && (_isExecutive || _isTelecaller || _isManager)) {
      final now = DateTime.now();

      // 1. Calculate working days in current month (excluding Sundays)
      int totalDaysInMonth = DateTime(now.year, now.month + 1, 0).day;
      int workingDaysInMonth = 0;
      for (int i = 1; i <= totalDaysInMonth; i++) {
        if (DateTime(now.year, now.month, i).weekday != DateTime.sunday) {
          workingDaysInMonth++;
        }
      }

      // 2. Calculate daily target base
      double dailyTarget =
          _salesTarget / (workingDaysInMonth > 0 ? workingDaysInMonth : 1);

      // 3. Determine target for the selected period
      double targetForPeriod;
      if (_selectedPeriod == 'Today') {
        targetForPeriod = dailyTarget;
      } else if (_selectedPeriod == 'This Week') {
        targetForPeriod = dailyTarget * 6; // Standard 6-day working week
      } else {
        // For 'This Month', 'This Year', or 'Customise', show the monthly target
        targetForPeriod = _salesTarget;
      }

      // 4. Calculate remaining target for the selected period
      // 'revenue' is already calculated for the selected period in the loop above
      _salesToAchieve =
          (targetForPeriod - revenue).clamp(0, double.infinity).toDouble();
    } else {
      // Admin or other: Show remaining monthly target vs selected period revenue
      _salesToAchieve =
          (_salesTarget - revenue).clamp(0, double.infinity).toDouble();
    }

    _filteredTransactions = validTransactions;

    // Process Reminders
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (_isManager) {
      // Process Unverified Items for Managers
      final List<Map<String, dynamic>> pending = [];

      for (var f in _allFarmers) {
        if (f['is_verified'] != true) {
          pending.add({
            'reminder_type': 'farmer',
            'title': f['name'] ?? 'Unknown Farmer',
            'subtitle': 'New Farmer Entry',
            'follow_up_date': f['created_at'] ?? now.toIso8601String(),
            'data': f,
          });
        }
      }

      for (var f in _allFarms) {
        if (f['is_verified'] != true) {
          pending.add({
            'reminder_type': 'farm',
            'title': f['name'] ?? 'Unknown Farm',
            'subtitle': 'New Farm Entry',
            'follow_up_date': f['created_at'] ?? now.toIso8601String(),
            'data': f,
          });
        }
      }

      for (var c in _allCrops) {
        if (c['is_verified'] != true) {
          pending.add({
            'reminder_type': 'crop',
            'title': c['name'] ?? 'Unknown Crop',
            'subtitle': 'New Crop Entry',
            'follow_up_date': c['created_at'] ?? now.toIso8601String(),
            'data': c,
          });
        }
      }

      for (var r in _allReports) {
        if (r['is_verified'] != true) {
          pending.add({
            'reminder_type': 'report',
            'title': 'Visit Report',
            'subtitle': 'Analysis Verification',
            'follow_up_date': r['created_at'] ?? now.toIso8601String(),
            'data': r,
          });
        }
      }

      // Sort by date (oldest first for verification priority)
      pending.sort(
        (a, b) =>
            (a['follow_up_date'] ?? '').compareTo(b['follow_up_date'] ?? ''),
      );
      _reminders = pending;
    } else {
      // Process Standard Reminders (Follow-up Dates from Reports) for Executives
      final reportsToProcess = _allReports ?? [];
      _reminders =
          reportsToProcess.where((report) {
            if (report['follow_up_date'] == null) return false;
            try {
              final followUp = DateTime.parse(report['follow_up_date']);
              // Show if today or in the future
              return followUp.isAfter(
                today.subtract(const Duration(seconds: 1)),
              );
            } catch (_) {
              return false;
            }
          }).toList();

      // Sort reminders by date (soonest first)
      _reminders.sort((a, b) {
        final dateA = DateTime.parse(a['follow_up_date']);
        final dateB = DateTime.parse(b['follow_up_date']);
        return dateA.compareTo(dateB);
      });
    }
  }

  DateTimeRange _getDateRangeForPeriod(String period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (period) {
      case 'Today':
        return DateTimeRange(
          start: today,
          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      case 'This Week':
        final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
        return DateTimeRange(start: startOfWeek, end: now);
      case 'This Month':
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
      case 'This Year':
        return DateTimeRange(start: DateTime(now.year, 1, 1), end: now);
      case 'Customise':
        return _customDateRange ??
            DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
      default:
        return DateTimeRange(start: DateTime(2000), end: DateTime(2100));
    }
  }

  Future<void> _showMonthYearPicker() async {
    final now = DateTime.now();
    int selectedYear = _customDateRange?.start.year ?? now.year;
    int selectedMonth = _customDateRange?.start.month ?? now.month;

    final result = await showDialog<DateTimeRange>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text(
                'Select Month & Year',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    value: selectedYear,
                    decoration: const InputDecoration(
                      labelText: 'Year',
                      filled: false,
                    ),
                    items:
                        List.generate(
                              now.year - 2020 + 1,
                              (index) => 2020 + index,
                            ).reversed
                            .map(
                              (year) => DropdownMenuItem(
                                value: year,
                                child: Text(year.toString()),
                              ),
                            )
                            .toList(),
                    onChanged:
                        (val) => setDialogState(() => selectedYear = val!),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    value: selectedMonth,
                    decoration: const InputDecoration(
                      labelText: 'Month',
                      filled: false,
                    ),
                    items:
                        List.generate(12, (index) => index + 1)
                            .map(
                              (month) => DropdownMenuItem(
                                value: month,
                                child: Text(
                                  DateFormat(
                                    'MMMM',
                                  ).format(DateTime(2022, month)),
                                ),
                              ),
                            )
                            .toList(),
                    onChanged:
                        (val) => setDialogState(() => selectedMonth = val!),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: AppColors.textGray),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    final startDate = DateTime(selectedYear, selectedMonth, 1);
                    final endDate = DateTime(
                      selectedYear,
                      selectedMonth + 1,
                      0,
                      23,
                      59,
                      59,
                    );
                    Navigator.pop(
                      context,
                      DateTimeRange(start: startDate, end: endDate),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(100, 45),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() {
        _customDateRange = result;
        _selectedPeriod = 'Customise';
        _applyFilters();
      });
    }
  }

  String _getTimeAgo(String? dateTimeStr) {
    if (dateTimeStr == null) return '';
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      final diff = DateTime.now().difference(dateTime);

      if (diff.inDays >= 365) return '${(diff.inDays / 365).floor()}y ago';
      if (diff.inDays >= 30) return '${(diff.inDays / 30).floor()}mo ago';
      if (diff.inDays >= 1) return '${diff.inDays}d ago';
      if (diff.inHours >= 1) return '${diff.inHours}h ago';
      if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
      return 'Just now';
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final bool isWide = MediaQuery.sizeOf(context).width > 1100;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: isWide ? _buildDesktopLayout() : _buildMobileLayout(),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'dashboard_fab',
        onPressed: _loadDashboardData,
        backgroundColor: AppColors.primary,
        elevation: 4,
        child: const Icon(Icons.refresh_rounded, color: Colors.white),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(24.0),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EntranceAnimation(
                delay: 0,
                child: Opacity(
                  opacity: _scrollOpacity,
                  child: Transform.scale(
                    scale: _scrollScale,
                    child: _buildPremiumHeader(),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _buildFilterBar(),
              const SizedBox(height: 20),
              EntranceAnimation(delay: 350, child: _buildSalesCard()),
              const SizedBox(height: 32),
              if (!_isAdmin) _buildRemindersSection(),
              const SizedBox(height: 40),
              _buildStatsGrid(isWide: false),
              const SizedBox(height: 32),
              if (_isAdmin) ..._buildAdminSections(isWide: false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main Content Area
        Expanded(
          flex: 7,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPremiumHeader(),
                const SizedBox(height: 32),
                const Text(
                  'Quick Overview',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textBlack,
                  ),
                ),
                const SizedBox(height: 24),
                _buildStatsGrid(isWide: true),
                const SizedBox(height: 32),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        // Sidebar Content Area
        Container(
          width: 360,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              left: BorderSide(color: Colors.grey.withOpacity(0.1)),
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dashboard Filters',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildFilterBar(),
                const SizedBox(height: 24),
                const Text(
                  'Financial Progress',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                _buildSalesCard(),
                const SizedBox(height: 44),
                if (!_isAdmin) _buildRemindersSection(),
                const SizedBox(height: 40),
                if (_isAdmin) ...[
                  const Divider(),
                  const SizedBox(height: 30),
                  const Text(
                    'Admin Management',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  ..._buildAdminSections(isWide: true),
                  const SizedBox(height: 40),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsGrid({required bool isWide}) {
    return Column(
      children: [
        // Top Line: Visits (Redirects to Reports History)
        StatCard(
          title:
              _isTelecaller ? 'Total Calls' : 'Total Visits (Analysis History)',
          value: _reportCount.toString(),
          icon: Icons.analytics_rounded,
          gradient: const [Color(0xFF673AB7), Color(0xFF4527A0)],
          onTap:
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const FarmerListScreen(),
                ),
              ),
          isHorizontal: true,
        ),
        const SizedBox(height: 16),
        // Second Line: New Farmer, New Farm, New Crop (View Only)
        LayoutBuilder(
          builder: (context, constraints) {
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: isWide ? 2.2 : 0.85,
              children: [
                StatCard(
                  title: 'Farmers',
                  value: _farmerCount.toString(),
                  icon: Icons.people_alt_rounded,
                  gradient: const [Color(0xFF4CAF50), Color(0xFF2E7D32)],
                  onTap:
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const FarmerListScreen(),
                        ),
                      ),
                  isSmall: true,
                ),
                StatCard(
                  title: 'Farms',
                  value: _farmCount.toString(),
                  icon: Icons.agriculture_rounded,
                  gradient: const [Color(0xFF8BC34A), Color(0xFF558B2F)],
                  onTap:
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const FarmListScreen(),
                        ),
                      ),
                  isSmall: true,
                ),
                StatCard(
                  title: 'Crops',
                  value: _cropCount.toString(),
                  icon: Icons.eco_rounded,
                  gradient: const [Color(0xFF009688), Color(0xFF00695C)],
                  onTap:
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CropListScreen(),
                        ),
                      ),
                  isSmall: true,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  List<Widget> _buildAdminSections({required bool isWide}) {
    return [
      _actionWrapper(
        isWide,
        delay: 400,
        child: _workActionCard(
          context,
          title: 'Team Management',
          subtitle: 'Manage team, targets & assignments',
          icon: Icons.people_alt_rounded,
          color: AppColors.primary,
          fullWidth: true,
          onTap:
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ExecutiveListScreen(),
                ),
              ),
        ),
      ),
      const SizedBox(height: 16),
      _actionWrapper(
        isWide,
        delay: 700,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primary.withOpacity(0.1)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.person_add_alt_1_rounded,
                color: AppColors.primary,
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Create Staff Account',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CreateStaffScreen(),
                      ),
                    ),
                icon: const Icon(
                  Icons.arrow_forward_rounded,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      _actionWrapper(
        isWide,
        delay: 850,
        child: _workActionCard(
          context,
          title: 'Edit Info Requests',
          subtitle: 'Review user correction proposals',
          icon: Icons.edit_note_rounded,
          color: Colors.orange,
          fullWidth: true,
          onTap:
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AdminEditRequestsScreen(),
                ),
              ),
        ),
      ),
      const SizedBox(height: 16),
      _actionWrapper(
        isWide,
        delay: 1000,
        child: _workActionCard(
          context,
          title: 'Security & Device Logs',
          subtitle: 'Monitor Hardware Usage',
          icon: Icons.security_rounded,
          color: Colors.orange,
          fullWidth: true,
          onTap:
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LoginLogsScreen(),
                ),
              ),
        ),
      ),
    ];
  }

  List<Widget> _buildUserSections({required bool isWide}) {
    return [];
  }

  Widget _actionWrapper(
    bool isWide, {
    required int delay,
    required Widget child,
  }) {
    if (isWide) return child;
    return EntranceAnimation(delay: delay, child: child);
  }

  String _getReminderLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = target.difference(today).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    return 'In $diff days';
  }

  Widget _buildRemindersSection() {
    if (_reminders.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap:
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => VisitCalendarScreen(
                        reminders: _reminders,
                        allFarms: _allFarms,
                        allCrops: _allCrops,
                        allFarmers: _allFarmers,
                      ),
                ),
              ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _isManager ? 'Verification Pending' : 'Upcoming Visits',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textBlack,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Text(
                      '${_reminders.length} Pending',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _isManager
                          ? Icons.verified_user_rounded
                          : Icons.calendar_month_rounded,
                      color: AppColors.primary,
                      size: 14,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height:
              175, // INCREASED: To prevent bottom overflow while remaining compact
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _reminders.length,
            itemBuilder: (context, index) {
              final reminder = _reminders[index];
              final date = DateTime.parse(reminder['follow_up_date']);

              String title = reminder['title'] ?? 'Unknown';
              String subtitle = reminder['subtitle'] ?? 'Action Required';
              IconData mainIcon = Icons.eco_rounded;

              if (_isManager) {
                final type = reminder['reminder_type'];
                switch (type) {
                  case 'farmer':
                    mainIcon = Icons.person_rounded;
                    break;
                  case 'farm':
                    mainIcon = Icons.agriculture_rounded;
                    break;
                  case 'crop':
                    mainIcon = Icons.eco_rounded;
                    break;
                  case 'report':
                    mainIcon = Icons.assignment_rounded;
                    break;
                }
              } else {
                final farm = _allFarms.firstWhere(
                  (f) => f['id'] == reminder['farm_id'],
                  orElse: () => <String, dynamic>{},
                );
                final crop = _allCrops.firstWhere(
                  (c) => c['id'] == reminder['crop_id'],
                  orElse: () => <String, dynamic>{},
                );
                final farmer = _allFarmers.firstWhere(
                  (f) => f['id'] == farm['farmer_id'],
                  orElse: () => <String, dynamic>{},
                );
                title = farmer['name'] ?? farm['name'] ?? 'Unknown Farmer';
                subtitle =
                    '${farm['name'] ?? 'Farm'} • ${crop['name'] ?? 'General Checkup'}';
              }

              return Container(
                width:
                    MediaQuery.sizeOf(context).width *
                    0.72, // REDUCED: 72% width creates a clear 'PEEK' for the next card
                margin: const EdgeInsets.only(right: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F8E9), // Soft Nature Tint
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.12),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // Watermark / Pattern
                    Positioned(
                      right: -20,
                      bottom: -20,
                      child: Icon(
                        mainIcon,
                        size: 120,
                        color: AppColors.primary.withOpacity(0.03),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _isManager
                                          ? Icons.pending_actions_rounded
                                          : Icons.history_toggle_off_rounded,
                                      color: AppColors.primary,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _isManager
                                          ? reminder['reminder_type']
                                              .toString()
                                              .toUpperCase()
                                          : _getReminderLabel(date),
                                      style: const TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                DateFormat('dd MMM').format(date),
                                style: TextStyle(
                                  color: AppColors.textGray.withOpacity(0.6),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            title,
                            style: const TextStyle(
                              color: AppColors.textBlack,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                _isManager
                                    ? Icons.info_outline_rounded
                                    : Icons.eco_outlined,
                                color: AppColors.accent,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  subtitle,
                                  style: TextStyle(
                                    color: AppColors.textGray.withOpacity(0.9),
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          // Compact Action Row
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 36,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF1B5E20),
                                        Color(0xFF2E7D32),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: ElevatedButton(
                                    onPressed: () {
                                      if (_isManager) {
                                        final type = reminder['reminder_type'];
                                        final data = reminder['data'];
                                        Widget target;
                                        switch (type) {
                                          case 'farmer':
                                            target = FarmerDetailScreen(
                                              farmer: data,
                                            );
                                            break;
                                          case 'farm':
                                            target = FarmDetailScreen(
                                              farm: data,
                                            );
                                            break;
                                          case 'crop':
                                            target = CropDetailScreen(
                                              crop: data,
                                            );
                                            break;
                                          case 'report':
                                            target = ReportGeneratorScreen(
                                              report: data,
                                            );
                                            break;
                                          default:
                                            return;
                                        }
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => target,
                                          ),
                                        );
                                      } else {
                                        // Executive logic for reminders (visits)
                                        // ... navigate to visit or report creation
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      foregroundColor: Colors.white,
                                      shadowColor: Colors.transparent,
                                      padding: EdgeInsets.zero,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    child: Text(
                                      _isManager
                                          ? 'Review & Verify'
                                          : 'View Details',
                                      style: GoogleFonts.outfit(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: AppColors.primary.withOpacity(0.1),
                                  ),
                                ),
                                child: IconButton(
                                  onPressed: () {},
                                  icon: const Icon(
                                    Icons.directions_outlined,
                                    color: AppColors.primary,
                                    size: 16,
                                  ),
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<String?> _captureAndUpload(String bucketId) async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 50,
    );
    if (photo != null) {
      final bytes = await photo.readAsBytes();
      final extension = photo.path.split('.').last;
      final fileName = '${const Uuid().v4()}.$extension';

      try {
        return await SupabaseService.uploadImage(bytes, fileName, bucketId);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Upload failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
    return null;
  }

  void _showStartTripDialog() {
    if (_activeTrip == null) {
      // Step 1: Create the trip record if it doesn't exist
      SupabaseService.startExecutiveTrip().then((_) => _loadDashboardData());
      return;
    }

    // Step 2: Show the odometer form
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => StartTripForm(
              expenseId: _activeTrip!['id'],
              onStarted: () {
                Navigator.pop(context);
                _loadDashboardData();
              },
              onCapture: () => _captureAndUpload('expense-documents'),
            ),
      ),
    );
  }

  void _showEndTripDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (context) => EndTripDialogContent(
            expenseId: _activeTrip!['id'],
            startOdometer:
                double.tryParse(
                  _activeTrip!['start_odometer_reading']?.toString() ?? '0',
                ) ??
                0.0,
            onEnded: _loadDashboardData,
            onCapture: () => _captureAndUpload('expense-documents'),
          ),
    );
  }

  Widget _buildPremiumHeader() {
    String greeting = 'Hi ${_userName.split(' ')[0]}';
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final bool showLabels = screenWidth > 400;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.95),
                const Color(0xFFF1F8E9).withOpacity(0.9), // Soft Mint Green
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.primary.withOpacity(0.15),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.08),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              // Profile & Greeting
              Expanded(
                child: GestureDetector(
                  onTap:
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ProfileScreen(),
                        ),
                      ).then((_) => _loadDashboardData()),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.primary,
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.2),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                          Hero(
                            tag: 'top_profile_avatar',
                            child: CircleAvatar(
                              radius: 15,
                              backgroundColor: AppColors.secondary,
                              backgroundImage:
                                  _avatarUrl.isNotEmpty
                                      ? NetworkImage(_avatarUrl)
                                      : null,
                              child:
                                  _avatarUrl.isEmpty
                                      ? const Icon(
                                        Icons.person,
                                        size: 14,
                                        color: AppColors.primary,
                                      )
                                      : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Good ${_getGreeting()}',
                              style: GoogleFonts.outfit(
                                color: AppColors.textGray.withOpacity(0.6),
                                fontSize: 8,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              greeting,
                              style: GoogleFonts.outfit(
                                color: const Color(0xFF2E3440),
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Action Hub
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _headerActionIcon(
                    icon: Icons.search_rounded,
                    backgroundColor: Colors.blueGrey.shade50.withOpacity(0.5),
                    onTap:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const FarmerListScreen(),
                          ),
                        ),
                  ),
                  const SizedBox(width: 4),
                  // Premium Attendance Button
                  GestureDetector(
                      onTap:
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const AttendanceScreen(),
                            ),
                          ).then((_) => _loadDashboardData()),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: showLabels ? 12 : 10,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF1B5E20).withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.camera_enhance_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                            if (showLabels) ...[
                              const SizedBox(width: 6),
                              Text(
                                'Check In',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  /* // Trip/Odometer Action
                  if (_isExecutive || _isTelecaller)
                    _buildTripActionButton(showLabels),
                  const SizedBox(width: 4), */
                  _headerActionIcon(
                    icon: Icons.power_settings_new_rounded,
                    color: Colors.redAccent,
                    backgroundColor: Colors.red.shade50.withOpacity(0.5),
                    onTap: _handleLogout,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTripActionButton(bool showLabels) {
    bool hasActiveTrip = _activeTrip != null;
    bool needsOdometer =
        hasActiveTrip && _activeTrip!['start_odometer_reading'] == null;
    bool tripInProgress =
        hasActiveTrip &&
        _activeTrip!['start_odometer_reading'] != null &&
        _activeTrip!['end_odometer_reading'] == null;

    IconData icon;
    String label;
    VoidCallback onTap;
    List<Color> gradientColors;

    if (!hasActiveTrip) {
      icon = Icons.play_arrow_rounded;
      label = 'Start Trip';
      onTap = () {
        if (_todayAttendance == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please Check In first to start a trip'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        _showStartTripDialog();
      };
      gradientColors = [
        const Color(0xFF1976D2),
        const Color(0xFF0D47A1),
      ]; // Blue
    } else if (needsOdometer) {
      icon = Icons.speed_rounded;
      label = 'Enter Odo';
      onTap = () {
        if (_todayAttendance == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please Check In first to enter odometer'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        _showStartTripDialog();
      };
      gradientColors = [
        const Color(0xFFFFA000),
        const Color(0xFFFF6F00),
      ]; // Orange
    } else if (tripInProgress) {
      icon = Icons.stop_rounded;
      label = 'End Trip';
      onTap = () {
        if (_todayAttendance == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please Check In first to end your trip'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        _showEndTripDialog();
      };
      gradientColors = [
        const Color(0xFFD32F2F),
        const Color(0xFFB71C1C),
      ]; // Red
    } else {
      return const SizedBox.shrink();
    }

    // Hide Start Trip/Enter Odo if not checked in (since it's now inside check-in)
    if (_todayAttendance == null && !tripInProgress) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: showLabels ? 10 : 10,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: gradientColors[1].withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 14),
            if (showLabels) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _headerActionIcon({
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
    Color? backgroundColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: color ?? AppColors.textBlack.withOpacity(0.7),
            size: 20,
          ),
        ),
      ),
    );
  }

  Future<void> _handleLogout() async {
    // Check if the user is currently checked in (has a today record but no check-out time)
    final bool isCurrentlyCheckedIn =
        _todayAttendance != null && _todayAttendance!['check_out_time'] == null;

    if (isCurrentlyCheckedIn && !_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please Check Out before logging out'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const AttendanceScreen()),
      ).then((_) => _loadDashboardData());
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Text(
              'Logout',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
            ),
            content: Text(
              'Are you sure you want to exit?',
              style: GoogleFonts.outfit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.textGray.withOpacity(0.6)),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade50,
                  foregroundColor: Colors.red,
                  elevation: 0,
                  minimumSize: const Size(100, 45),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Logout'),
              ),
            ],
          ),
    );

    if (confirm == true) {
      await SupabaseService.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  // DELETED: _buildHeroSection and _buildTopActions old implementations

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Morning';
    if (hour < 17) return 'Afternoon';
    return 'Evening';
  }

  Widget _workActionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    Widget? trailing,
    bool fullWidth = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: fullWidth ? double.infinity : null,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(color: AppColors.textGray, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (trailing != null)
              trailing
            else
              Icon(Icons.chevron_right_rounded, color: color.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSalesCard() {
    final currencyFormat = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (context) => FarmSalesListScreen(
                    initialTransactions: _filteredTransactions,
                    allProducts: _allProducts,
                    allFarms: _allFarms,
                  ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            // Elite Nature Masterpiece Background (FIXED: Added Positioned.fill)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF1A237E), // Deep Indigo
                      Color(0xFF1B5E20), // Forest Green
                      Color(0xFF2E7D32), // Nature Green
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1B5E20).withOpacity(0.4),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            // Decorative Layer: Glowing Orbs
            Positioned(
              left: -40,
              top: -40,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF3F51B5).withOpacity(0.2),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: -20,
              top: 20,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF81C784).withOpacity(0.15),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Eco-Watermark / Pattern Layer
            Positioned(
              right: -10,
              bottom: -10,
              child: Opacity(
                opacity: 0.05,
                child: Transform.rotate(
                  angle: -0.2,
                  child: const Icon(
                    Icons.eco_rounded,
                    size: 180,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            // Content Layer
            Padding(
              padding: const EdgeInsets.all(20.0),
              child:
                  _isAdmin
                      ? _buildAdminSalesContent(currencyFormat)
                      : _buildExecutiveSalesContent(currencyFormat),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminSalesContent(NumberFormat currencyFormat) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Team Sales Revenue',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  currencyFormat.format(_totalSalesRevenue),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.payments_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$_totalItemsSold Items',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'Sold',
                  style: TextStyle(color: Colors.white70, fontSize: 10),
                ),
                const SizedBox(height: 12),
                Text(
                  '$_totalItemsReturned Items',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'Returned',
                  style: TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        _indicatorLabel('Across All Regions', Icons.trending_up_rounded),
      ],
    );
  }

  Widget _buildExecutiveSalesContent(NumberFormat currencyFormat) {
    return Column(
      children: [
        Row(
          children: [
            _metricBox(
              'Sales to Achieve',
              _salesToAchieve,
              Colors.red.shade300,
              Icons.pending_actions_rounded,
              currencyFormat,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => FarmSalesListScreen(
                          initialTransactions: _filteredTransactions,
                          allProducts: _allProducts,
                          allFarms: _allFarms,
                          mode: 'SALES',
                        ),
                  ),
                );
              },
            ),
            const SizedBox(width: 16),
            _metricBox(
              'Sales Achieved',
              _totalSalesRevenue,
              Colors.green.shade300,
              Icons.check_circle_outline_rounded,
              currencyFormat,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => FarmSalesListScreen(
                          initialTransactions: _filteredTransactions,
                          initialCollections: _filteredCollections,
                          allProducts: _allProducts,
                          allFarms: _allFarms,
                          mode: 'SALES',
                        ),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _metricBox(
              'Outstanding',
              _totalOutstanding,
              Colors.orange.shade300,
              Icons.account_balance_wallet_rounded,
              currencyFormat,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => FarmSalesListScreen(
                          initialTransactions: _filteredTransactions,
                          initialCollections: _filteredCollections,
                          allProducts: _allProducts,
                          allFarms: _allFarms,
                          mode: 'OUTSTANDING',
                        ),
                  ),
                );
              },
            ),
            const SizedBox(width: 16),
            _metricBox(
              'Collection',
              _totalCollection,
              Colors.cyan.shade300,
              Icons.payments_rounded,
              currencyFormat,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => FarmSalesListScreen(
                          initialTransactions: _filteredTransactions,
                          initialCollections: _filteredCollections,
                          allProducts: _allProducts,
                          allFarms: _allFarms,
                          mode: 'COLLECTION',
                        ),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _metricBox(
    String label,
    double value,
    Color color,
    IconData icon,
    NumberFormat currencyFormat, {
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withOpacity(0.15),
                width: 1.2,
              ),
              gradient: LinearGradient(
                colors: [
                  color.withOpacity(0.15),
                  Colors.white.withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: color.withOpacity(0.3)),
                      ),
                      child: Icon(icon, size: 12, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label.toUpperCase(),
                        style: GoogleFonts.outfit(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    currencyFormat.format(value.isFinite ? value : 0.0),
                    style: GoogleFonts.outfit(
                      color: color.withOpacity(
                        0.95,
                      ), // Vibrant Color restoration
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      shadows: [
                        Shadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                        Shadow(color: color.withOpacity(0.4), blurRadius: 10),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Vibrant Glowing Pill Indicator
                Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color, color.withOpacity(0.7)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.5),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showBreakdownSheet(String type) {
    final currencyFormat = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );
    final currentUserId = SupabaseService.client.auth.currentUser?.id;

    // Calculate per-farm breakdown using the exact same logic as _applyFilters
    final Map<String, double> farmCollection = {};
    final Map<String, double> farmRevenue = {};

    final range = _getDateRangeForPeriod(_selectedPeriod);
    final startDate = range.start;
    final endDate = range.end;

    for (var tx in _allTransactions) {
      if (!_isInPeriod(tx, startDate, endDate)) continue;

      final txType = tx['transaction_type']?.toString().toUpperCase();
      final txExecId = tx['executive_id']?.toString().toLowerCase();
      final currentId = currentUserId?.toString().toLowerCase();
      final isOwner =
          _isAdmin
              ? true
              : (txExecId == currentId ||
                  (tx['status'] == 'PENDING' && txExecId == null));
      if (!isOwner) continue;

      final farmId = tx['farm_id']?.toString() ?? 'unknown';

      // 1. Process Revenue (RECEIVED = Sale, RETURN = -Sale)
      if (txType == 'RECEIVED' || txType == 'RETURN') {
        final itemName = tx['item_name']?.toString().trim().toLowerCase();
        final unit = tx['unit']?.toString().trim().toLowerCase() ?? '';
        // Clean unit for price matching
        final cleanUnit = unit.split(' {₹')[0].trim();
        final qty = double.tryParse(tx['quantity']?.toString() ?? '0') ?? 0.0;

        final parent = _allProducts.firstWhere(
          (p) => p['label']?.toString().trim().toLowerCase() == itemName,
          orElse: () => {},
        );

        if (parent.isNotEmpty) {
          final variants = List<Map<String, dynamic>>.from(
            parent['variants'] ?? [],
          );
          final variant = variants.firstWhere(
            (v) => v['label']?.toString().trim().toLowerCase() == cleanUnit,
            orElse: () => {},
          );
          if (variant.isNotEmpty) {
            final price =
                double.tryParse(variant['offer_price']?.toString() ?? '0') ??
                0.0;
            final amount = price * qty;
            if (txType == 'RECEIVED') {
              farmRevenue[farmId] = (farmRevenue[farmId] ?? 0) + amount;
            } else {
              farmRevenue[farmId] = (farmRevenue[farmId] ?? 0) - amount;
            }
          }
        }
      }

      // 2. Process Collection
      if (txType == 'RECEIVED') {
        double amt =
            double.tryParse(tx['collected_amount']?.toString() ?? '0') ?? 0.0;
        if (amt == 0 &&
            tx['unit'] != null &&
            tx['unit'].toString().contains('{₹')) {
          try {
            final unitStr = tx['unit'].toString();
            final start = unitStr.indexOf('{₹') + 2;
            final end = unitStr.indexOf('}', start);
            if (end != -1) {
              amt = double.tryParse(unitStr.substring(start, end)) ?? 0.0;
            }
          } catch (_) {}
        }
        if (amt > 0) {
          farmCollection[farmId] = (farmCollection[farmId] ?? 0) + amt;
        }
      }
    }

    // Create final list for the selected type
    final List<Map<String, dynamic>> displayList = [];
    final targetMap = type == 'Collection' ? farmCollection : {};

    // Use all farms that have some activity
    final allActiveFarmIds = {...farmCollection.keys, ...farmRevenue.keys};

    for (var fid in allActiveFarmIds) {
      final revenue = farmRevenue[fid] ?? 0.0;
      final collection = farmCollection[fid] ?? 0.0;
      final outstanding = revenue - collection;

      final farm = _allFarms.firstWhere(
        (f) => f['id'].toString() == fid,
        orElse: () => {'name': 'Unknown Farm'},
      );

      final value = type == 'Collection' ? collection : outstanding;
      if (value != 0) {
        displayList.add({
          'name': farm['name'] ?? farm['place'] ?? 'Farm #$fid',
          'place': farm['place'] ?? '',
          'amount': value,
        });
      }
    }

    // Sort by amount descending
    displayList.sort(
      (a, b) => (b['amount'] as double).abs().compareTo(
        (a['amount'] as double).abs(),
      ),
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (context) => Container(
            height: MediaQuery.of(context).size.height * 0.7,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Farm Breakdown: $type',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child:
                      displayList.isEmpty
                          ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.receipt_long_outlined,
                                  size: 64,
                                  color: Colors.grey[300],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No $type records for this period',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                          : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: displayList.length,
                            itemBuilder: (context, index) {
                              final item = displayList[index];
                              final amt = item['amount'] as double;
                              final isNegative = amt < 0;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: AppColors.secondary,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.white,
                                    child: Icon(
                                      Icons.agriculture_rounded,
                                      color:
                                          type == 'Collection'
                                              ? Colors.cyan
                                              : Colors.orange,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    item['name'],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    item['place'],
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: Text(
                                    currencyFormat.format(amt),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color:
                                          isNegative
                                              ? Colors.red
                                              : (type == 'Collection'
                                                  ? Colors.cyan
                                                  : Colors.orange),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                ),
              ],
            ),
          ),
    );
  }

  bool _isInPeriod(dynamic item, DateTime startDate, DateTime endDate) {
    if (item == null) return false;
    final createdStr =
        item['created_at']?.toString() ?? item['start_time']?.toString();
    if (createdStr == null) return false;
    final dt = DateTime.tryParse(createdStr);
    if (dt == null) return false;
    // Add generous 12h buffer for timezone shifts (UTC records vs Local filters)
    return dt.isAfter(startDate.subtract(const Duration(hours: 12))) &&
        dt.isBefore(endDate.add(const Duration(hours: 12)));
  }

  Widget _indicatorLabel(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.greenAccent, size: 16),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.arrow_forward_ios_rounded,
            color: Colors.white38,
            size: 10,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final periods = [
      'Today',
      'This Week',
      'This Month',
      'This Year',
      'Customise',
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children:
            periods.map((period) {
              final isSelected = _selectedPeriod == period;
              String label = period;
              if (period == 'Customise' && _customDateRange != null) {
                label = DateFormat('MMM yyyy').format(_customDateRange!.start);
              }

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(label),
                  selected: isSelected,
                  onSelected: (selected) async {
                    if (period == 'Customise') {
                      await _showMonthYearPicker();
                    } else if (selected) {
                      setState(() {
                        _selectedPeriod = period;
                        _applyFilters();
                      });
                    }
                  },
                  selectedColor: AppColors.primary,
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : AppColors.textGray,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  elevation: isSelected ? 4 : 0,
                  side: BorderSide(
                    color:
                        isSelected
                            ? AppColors.primary
                            : Colors.grey.withOpacity(0.2),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }
}

class EntranceAnimation extends StatelessWidget {
  final Widget child;
  final int delay;

  const EntranceAnimation({super.key, required this.child, this.delay = 0});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutQuint,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 30 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class StatCard extends StatefulWidget {
  final String title;
  final String value;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback? onTap;
  final bool isSmall;
  final bool isHorizontal;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.gradient,
    this.onTap,
    this.isSmall = false,
    this.isHorizontal = false,
  });

  @override
  State<StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<StatCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter:
          widget.onTap == null
              ? null
              : (_) => setState(() => _isHovered = true),
      onExit:
          widget.onTap == null
              ? null
              : (_) => setState(() => _isHovered = false),
      cursor:
          widget.onTap == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()..scale(_isHovered ? 1.05 : 1.0),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: widget.gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: widget.gradient.last.withOpacity(0.3),
                  blurRadius: _isHovered ? 20 : 10,
                  offset: Offset(0, _isHovered ? 10 : 6),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Decorative Background Icon
                Positioned(
                  right: -20,
                  bottom: -20,
                  child: Icon(
                    widget.icon,
                    size: widget.isHorizontal ? 140 : 110,
                    color: Colors.white.withOpacity(0.12),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(
                    widget.isSmall
                        ? (MediaQuery.sizeOf(context).width > 1100 ? 8 : 10)
                        : 20,
                  ),
                  child:
                      widget.isHorizontal
                          ? _buildHorizontalLayout()
                          : _buildVerticalLayout(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerticalLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          padding: EdgeInsets.all(widget.isSmall ? 6 : 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(widget.isSmall ? 8 : 10),
          ),
          child: Icon(
            widget.icon,
            color: Colors.white,
            size: widget.isSmall ? 18 : 24,
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.value,
              style: TextStyle(
                fontSize: widget.isSmall ? 20 : 26,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              widget.title,
              style: TextStyle(
                fontSize: widget.isSmall ? 10 : 13,
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHorizontalLayout() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(widget.icon, color: Colors.white, size: 32),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                widget.value,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
        const Icon(
          Icons.arrow_forward_ios_rounded,
          color: Colors.white54,
          size: 16,
        ),
      ],
    );
  }
}

class ActivityItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final String time;

  const ActivityItem({
    super.key,
    required this.title,
    required this.subtitle,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.secondary),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.history,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textGray,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            time,
            style: const TextStyle(color: AppColors.textGray, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
