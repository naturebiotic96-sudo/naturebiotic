import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nature_biotic/core/theme.dart';
import 'package:nature_biotic/features/dashboard/screens/dashboard_screen.dart';
import 'package:nature_biotic/features/calls/screens/executive_dialer_screen.dart';
import 'package:nature_biotic/features/reports/screens/farm_pdf_folder_screen.dart';
import 'package:nature_biotic/features/inventory/screens/store_stock_screen.dart';
import 'package:nature_biotic/features/profile/screens/profile_screen.dart';
import 'package:nature_biotic/services/supabase_service.dart';
import 'package:nature_biotic/features/expenses/screens/executive_expenses_screen.dart';
import 'package:nature_biotic/features/expenses/screens/manager_expenses_screen.dart';
import 'package:nature_biotic/core/widgets/offline_banner.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class BottomNav extends StatefulWidget {
  const BottomNav({super.key});

  @override
  State<BottomNav> createState() => _BottomNavState();
}

class _BottomNavState extends State<BottomNav> {
  int _currentIndex = 0;
  String _userRole = 'executive';
  bool _isLoading = true;

  // Added Navigator keys for each tab to enable persistent bottom bar
  final Map<int, GlobalKey<NavigatorState>> _navigatorKeys = {
    0: GlobalKey<NavigatorState>(),
    1: GlobalKey<NavigatorState>(),
    2: GlobalKey<NavigatorState>(),
    3: GlobalKey<NavigatorState>(),
    4: GlobalKey<NavigatorState>(),
  };

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    try {
      final profile = await SupabaseService.getProfile();
      if (mounted) {
        setState(() {
          _userRole = profile?['role'] ?? 'executive';
          _isLoading = false;
        });
      }
      if (!kIsWeb) _prefetchCriticalData();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _prefetchCriticalData() async {
    try {
      await Future.wait([
        SupabaseService.getFarmers(),
        SupabaseService.getFarms(),
        SupabaseService.getAllCrops(),
        SupabaseService.getReports(),
        SupabaseService.getHierarchicalDropdownOptions('product_name'),
        SupabaseService.getHierarchicalDropdownOptions('product_vendor_map'),
        SupabaseService.getAllStockTransactions(),
        SupabaseService.getMasterCrops(),
        SupabaseService.syncAllDropdownOptions(),
      ]);
    } catch (_) {}
  }

  List<Widget> _getScreens() {
    if (_userRole == 'store') {
      return [const StoreStockScreen(), const ProfileScreen()];
    }

    return [
      const DashboardScreen(),
      const ExecutiveDialerScreen(),
      const StoreStockScreen(),
      (_userRole == 'admin')
          ? const ManagerExpenseControl()
          : const ExecutiveExpenseDashboard(),
      const FarmPdfFolderScreen(),
    ];
  }

  // Helper to build a navigator for each tab
  Widget _buildTabNavigator(int index, Widget screen) {
    return Navigator(
      key: _navigatorKeys[index],
      onGenerateRoute: (routeSettings) {
        return MaterialPageRoute(builder: (context) => screen);
      },
    );
  }

  List<BottomNavigationBarItem> _getNavItems() {
    if (_userRole == 'store') {
      return const [
        BottomNavigationBarItem(
          icon: Icon(Icons.inventory_2_rounded),
          label: 'Stock',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_rounded),
          label: 'Profile',
        ),
      ];
    }

    return const [
      BottomNavigationBarItem(
        icon: Icon(Icons.dashboard_rounded),
        label: 'Dashboard',
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.call_rounded),
        label: 'Nature Biotic',
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.inventory_2_rounded),
        label: 'Stock',
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.payments_rounded),
        label: 'Expenses',
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.folder_shared_rounded),
        label: 'Reports',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final screens = _getScreens();
    final bool isWide = MediaQuery.sizeOf(context).width > 1100;
    final int safeIndex = screens.isEmpty ? 0 : _currentIndex.clamp(0, screens.length - 1);

    // Build the tab contents with navigators
    final List<Widget> tabNavigators = [];
    for (int i = 0; i < screens.length; i++) {
      tabNavigators.add(_buildTabNavigator(i, screens[i]));
    }

    if (isWide) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: OfflineAwareBanner(
          child: Row(
            children: [
              _buildDesktopSidebar(screens),
              Expanded(
                child: IndexedStack(
                  index: safeIndex,
                  children: tabNavigators,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        
        final NavigatorState? currentNavigator = _navigatorKeys[_currentIndex]?.currentState;
        if (currentNavigator != null && currentNavigator.canPop()) {
          currentNavigator.pop();
        } else if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
        } else {
          // If at home and can't pop nested, allow app to exit or use default back behavior
          // This might need more logic depending on how the app should exit
        }
      },
      child: Scaffold(
        body: OfflineAwareBanner(
          child: IndexedStack(
            index: safeIndex,
            children: tabNavigators,
          ),
        ),
        bottomNavigationBar: screens.length <= 1
            ? null
            : Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 20,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: BottomNavigationBar(
                  currentIndex: safeIndex,
                  onTap: (index) {
                    if (_currentIndex == index) {
                      // Pop to root if the same tab is tapped again
                      _navigatorKeys[index]?.currentState?.popUntil((route) => route.isFirst);
                    } else {
                      setState(() {
                        _currentIndex = index;
                      });
                    }
                  },
                  type: BottomNavigationBarType.fixed,
                  backgroundColor: Colors.white,
                  selectedItemColor: AppColors.primary,
                  unselectedItemColor: AppColors.textGray.withOpacity(0.4),
                  selectedLabelStyle: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  unselectedLabelStyle: GoogleFonts.outfit(
                    fontWeight: FontWeight.w500,
                    fontSize: 11,
                  ),
                  elevation: 0,
                  items: _getNavItems(),
                ),
              ),
      ),
    );
  }

  Widget _buildDesktopSidebar(List<Widget> screens) {
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(5, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Branding Header
          Container(
            padding: const EdgeInsets.all(32),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.eco_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'NATURE',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: AppColors.textBlack,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      'BIOTIC',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: AppColors.primary,
                        letterSpacing: 4,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Nav Items
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: _userRole == 'store'
                    ? [
                        _sidebarItem(0, Icons.inventory_2_rounded, 'Stock'),
                        _sidebarItem(1, Icons.person_rounded, 'Profile'),
                      ]
                    : [
                        _sidebarItem(0, Icons.dashboard_rounded, 'Dashboard'),
                        _sidebarItem(1, Icons.call_rounded, 'Nature Biotic'),
                        _sidebarItem(2, Icons.inventory_2_rounded, 'Stock'),
                        _sidebarItem(3, Icons.payments_rounded, 'Expenses'),
                        _sidebarItem(4, Icons.folder_shared_rounded, 'Reports'),
                      ],
              ),
            ),
          ),
          // Footer
          const Divider(indent: 24, endIndent: 24),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: AppColors.secondary,
                  child: Icon(
                    Icons.admin_panel_settings_rounded,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Management',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        'System Console',
                        style: TextStyle(
                          color: AppColors.textGray.withOpacity(0.7),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarItem(int index, IconData icon, String label) {
    final bool isSelected = _currentIndex == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (_currentIndex == index) {
              _navigatorKeys[index]?.currentState?.popUntil((route) => route.isFirst);
            } else {
              setState(() => _currentIndex = index);
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary.withOpacity(0.08) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isSelected ? AppColors.primary : AppColors.textGray.withOpacity(0.5),
                  size: 22,
                ),
                const SizedBox(width: 16),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? AppColors.primary : AppColors.textGray.withOpacity(0.7),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                if (isSelected) ...[
                  const Spacer(),
                  Container(
                    width: 4,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildComingSoonScreen(String title) {
    return Container(
      color: AppColors.background,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.construction_rounded,
                size: 80,
                color: AppColors.primary.withOpacity(0.2),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textBlack,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'COMING SOON',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Text(
                'We are building a comprehensive expense tracking module for your team. Stay tuned!',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: AppColors.textGray,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
