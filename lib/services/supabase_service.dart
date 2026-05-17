import 'dart:io';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nature_biotic/services/device_service.dart';
import 'package:flutter/foundation.dart';
import 'package:nature_biotic/services/local_database_service.dart';
import 'package:nature_biotic/services/sync_manager.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class SupabaseService {
  static Future<bool> isOffline() async {
    if (kIsWeb) return false;
    try {
      final res = await Connectivity().checkConnectivity();
      return res.every((r) => r == ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  static const String _supabaseUrl = 'https://utujkxrobmzlvudpvapc.supabase.co';
  static const String _supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV0dWpreHJvYm16bHZ1ZHB2YXBjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ5MzA2NjQsImV4cCI6MjA5MDUwNjY2NH0.REckx5fsLJMEJFnQVJdjyfNHC0seokVfPYkhOr5fxCw';
  
  static final client = Supabase.instance.client;

  // Helper to sign up via direct HTTP to avoid SDK session management issues/switching
  static Future<String> _signUpDirect(String email, String password, Map<String, dynamic> metadata) async {
    final response = await http.post(
      Uri.parse('$_supabaseUrl/auth/v1/signup'),
      headers: {
        'apikey': _supabaseAnonKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': email,
        'password': password,
        'data': metadata,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw data['msg'] ?? data['error_description'] ?? 'Failed to create account: ${response.body}';
    }

    String? id = data['id'];
    if (id == null && data['user'] != null) {
      id = data['user']['id'];
    }

    if (id == null) {
      debugPrint('SIGNUP ERROR: ID not found. Response: ${response.body}');
      throw 'User ID not found in signup response';
    }

    return id;
  }

  // Sign in logic
  // For Admin: uses email (naturebiotic96@gmail.com)
  // For Executive: uses username (converts to username@naturebiotic.local internally)
  static Future<AuthResponse> signIn({
    required String identifier,
    required String password,
    bool isAdmin = false,
  }) async {
    String email = identifier;
    // Auto-detect: if no @ is present, it's a username
    if (!identifier.contains('@')) {
      email = '$identifier@naturebiotic.local';
    }
    
    _cachedProfile = null; // Clear any previous user's profile cache
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  // Create Executive Account (Admin only)
  static Future<void> createExecutive({
    required String username,
    required String password,
    required String fullName,
  }) async {
    final email = '$username@naturebiotic.local';
    
    // Create auth user via HTTP to avoid session switching
    final userId = await _signUpDirect(email, password, {
      'username': username,
      'full_name': fullName,
      'role': 'executive',
    });

    if (userId.isEmpty) {
      throw 'Failed to create executive account';
    }

    // Explicitly create profile record
    await client.from('profiles').insert({
      'id': userId,
      'full_name': fullName,
      'username': username,
      'role': 'executive',
    });
  }

  // Create Store Account (Admin only)
  static Future<void> createStoreAccount({
    required String username,
    required String password,
    required String fullName,
  }) async {
    final email = '$username@naturebiotic.local';
    
    // Create auth user
    final userId = await _signUpDirect(email, password, {
      'username': username,
      'full_name': fullName,
      'role': 'store',
    });

    if (userId.isEmpty) {
      throw 'Failed to create store account';
    }

    // Create profile record
    await client.from('profiles').insert({
      'id': userId,
      'full_name': fullName,
      'username': username,
      'role': 'store',
    });
  }

  // Create Manager Account (Admin only)
  static Future<void> createManagerAccount({
    required String username,
    required String password,
    required String fullName,
  }) async {
    final email = '$username@naturebiotic.local';

    // Create auth user
    final userId = await _signUpDirect(email, password, {
      'username': username,
      'full_name': fullName,
      'role': 'manager',
    });

    if (userId.isEmpty) {
      throw 'Failed to create manager account';
    }

    // Create profile record
    await client.from('profiles').insert({
      'id': userId,
      'full_name': fullName,
      'username': username,
      'role': 'manager',
    });
  }

  // Create Telecaller Account (Admin only)
  static Future<void> createTelecallerAccount({
    required String username,
    required String password,
    required String fullName,
  }) async {
    final email = '$username@naturebiotic.local';

    // Create auth user
    final userId = await _signUpDirect(email, password, {
      'username': username,
      'full_name': fullName,
      'role': 'telecaller',
    });

    if (userId.isEmpty) {
      throw 'Failed to create telecaller account';
    }

    // Create profile record
    await client.from('profiles').insert({
      'id': userId,
      'full_name': fullName,
      'username': username,
      'role': 'telecaller',
    });
  }

  static Map<String, dynamic>? _cachedProfile;

  // Get current user profile
  static Future<Map<String, dynamic>?> getProfile() async {
    try {
      final user = client.auth.currentUser;
      if (user == null) return null;

      if (_cachedProfile != null && _cachedProfile!['id'] == user.id) {
        return _cachedProfile;
      }

      final response = await client
          .from('profiles')
          .select('*, registered_device_id') // Ensure we fetch this
          .eq('id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 3));
      
      if (response != null) {
        _cachedProfile = response;
        if (!kIsWeb) await LocalDatabaseService.saveCache('user_profile_${user.id}', [response]);
      }
      return response;
    } catch (e) {
      final user = client.auth.currentUser;
      if (user != null && !kIsWeb) {
        final cached = await LocalDatabaseService.getCache('user_profile_${user.id}');
        if (cached != null && cached.isNotEmpty) {
          _cachedProfile = cached.first;
          return _cachedProfile;
        }
      }
      return null;
    }
  }

  static Future<void> updateRegisteredDevice(String deviceId) async {
    final user = client.auth.currentUser;
    if (user == null) return;
    
    await client.from('profiles').update({
      'registered_device_id': deviceId,
    }).eq('id', user.id);
  }

  static Future<void> resetUserDevice(String userId) async {
    await client.from('profiles').update({
      'registered_device_id': null,
    }).eq('id', userId);
  }

  static Future<List<Map<String, dynamic>>> getExecutives() async {
    try {
      final response = await client
          .from('profiles')
          .select('id, username, full_name, sales_target, role')
          .eq('role', 'executive')
          .order('full_name');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error in getExecutives: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getAllStaff() async {
    try {
      final response = await client
          .from('profiles')
          .select('id, username, full_name, sales_target, role')
          .inFilter('role', ['executive', 'manager', 'telecaller', 'store'])
          .order('full_name');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error in getAllStaff: $e');
      return [];
    }
  }

  static Future<Map<String, double>> getTeamSalesStats() async {
    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1).toIso8601String();
      
      // Fetch all relevant transactions for this month
      final txResponse = await client.from('stock_transactions')
          .select('executive_id, transaction_type, quantity, item_name, unit')
          .gte('created_at', startOfMonth)
          .inFilter('transaction_type', ['RECEIVED', 'RETURN']);

      if (txResponse == null) return {};
      
      // Fetch products for pricing
      final products = await getHierarchicalDropdownOptions('product_name');
      
      final Map<String, double> stats = {};
      final List<Map<String, dynamic>> transactions = List<Map<String, dynamic>>.from(txResponse);

      for (var tx in transactions) {
        final execId = tx['executive_id']?.toString();
        if (execId == null) continue;

        final type = tx['transaction_type'];
        final itemName = tx['item_name']?.toString().trim().toLowerCase();
        final rawUnit = tx['unit']?.toString().trim().toLowerCase() ?? '';
        final unit = rawUnit.split(' {₹')[0].trim();
        final qty = double.tryParse(tx['quantity']?.toString() ?? '0') ?? 0.0;

        // Find price
        final product = products.firstWhere(
          (p) => p['label']?.toString().trim().toLowerCase() == itemName,
          orElse: () => {},
        );

        if (product.isNotEmpty) {
          final variants = List<Map<String, dynamic>>.from(product['variants'] ?? []);
          final variant = variants.firstWhere(
            (v) => v['label']?.toString().trim().toLowerCase() == unit,
            orElse: () => {},
          );

          if (variant.isNotEmpty) {
            final price = double.tryParse(variant['offer_price']?.toString() ?? '0') ?? 0.0;
            final amount = price * qty;

            stats[execId] = (stats[execId] ?? 0.0) + (type == 'RECEIVED' ? amount : -amount);
          }
        }
      }
      return stats;
    } catch (e) {
      debugPrint('Error in getTeamSalesStats: $e');
      return {};
    }
  }

  static Future<List<Map<String, dynamic>>> getTeamMembers() async {
    try {
      final user = client.auth.currentUser;
      var query = client
          .from('profiles')
          .select('id, username, full_name, sales_target, role, avatar_url, staff_number');
      
      if (user != null) {
        query = query.neq('id', user.id);
      }
      
      final response = await query.order('full_name');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error in getTeamMembers: $e');
      return [];
    }
  }

  static Future<bool> isDeviceAuthorized() async {
    final user = client.auth.currentUser;
    if (user == null) return false;

    try {
      final profile = await getProfile();
      // Admin bypass - If no profile found or if the role is admin, they can login from anywhere
      if (profile == null || profile['role'] == 'admin') return true;

      final registeredId = profile['registered_device_id'];
      if (registeredId == null || registeredId.isEmpty) return true;

      final deviceInfo = await DeviceService.getDeviceInfo();
      return registeredId == deviceInfo['id'];
    } catch (_) {
      return false;
    }
  }

  static Future<void> logLoginActivity({
    required String deviceId,
    required String deviceName,
    required String osVersion,
    required String status,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) return;

    await client.from('login_logs').insert({
      'user_id': user.id,
      'device_id': deviceId,
      'device_name': deviceName,
      'os_version': osVersion,
      'status': status,
    });
  }

  static Future<List<Map<String, dynamic>>> getLoginLogs() async {
    try {
      final response = await client
          .from('login_logs')
          .select('*, profiles:user_id(full_name, username)')
          .order('created_at', ascending: false);
      
      print('DEBUG: Fetched ${response.length} login logs');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('DEBUG: Error fetching login logs: $e');
      rethrow;
    }
  }

  // Farmer CRUD
  static Future<Map<String, dynamic>?> getFarmerDetail(String id) async {
    try {
      final response = await client.from('farmers').select().eq('id', id).single();
      return response as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Error in getFarmerDetail: $e');
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> getFarmers() async {
    try {
      if (await isOffline()) throw 'Offline';
      final profile = await getProfile();
      var query = client.from('farmers').select();
      
      final role = profile?['role'];
      if (role == 'executive' || role == 'telecaller') {
        query = query.eq('created_by', client.auth.currentUser!.id);
      }
      
      final data = List<Map<String, dynamic>>.from(await query.order('created_at').timeout(const Duration(seconds: 4)));
      // Cache on success
      if (!kIsWeb) await LocalDatabaseService.saveCache('farmers_${role ?? 'all'}', data);
      return LocalDatabaseService.mergeWithPending('farmers', data);
    } catch (e) {
      debugPrint('Error in getFarmers: $e');
      // Fallback to cache
      if (!kIsWeb) {
        final profile = await getProfile().catchError((_) => null);
        final role = profile?['role'];
        final cached = await LocalDatabaseService.getCache('farmers_${role ?? 'all'}');
        if (cached != null) return LocalDatabaseService.mergeWithPending('farmers', cached);
      }
      return [];
    }
  }

  static Future<void> addFarmer(Map<String, dynamic> farmerData) async {
    final cleanData = _cleanPayload(farmerData);
    final userId = client.auth.currentUser?.id;
    
    // Ensure created_by is set if not already present
    if (cleanData['created_by'] == null && userId != null) {
      cleanData['created_by'] = userId;
    }

    debugPrint('SUPABASE: Adding farmer: ${cleanData['name']} (ID: ${cleanData['id']})');
    
    try {
      await client.from('farmers').insert(cleanData);
      debugPrint('SUPABASE: Farmer added successfully');
    } catch (e) {
      debugPrint('SUPABASE ERROR: Failed to add farmer: $e');
      rethrow;
    }
  }

  static Future<void> addFarmersBulk(List<Map<String, dynamic>> farmersData) async {
    final userId = client.auth.currentUser?.id;
    final farmersWithCreatedBy = farmersData.map((farmer) {
      final clean = _cleanPayload(farmer);
      if (clean['created_by'] == null && userId != null) {
        clean['created_by'] = userId;
      }
      return clean;
    }).toList();
    
    debugPrint('SUPABASE: Adding ${farmersWithCreatedBy.length} farmers in bulk');
    await client.from('farmers').insert(farmersWithCreatedBy);
  }

  static Future<void> updateFarmer(String id, Map<String, dynamic> farmerData) async {
    final cleanData = _cleanPayload(farmerData);
    // Remove ID and created_at/by from update payload to avoid issues
    cleanData.remove('id');
    cleanData.remove('created_at');
    cleanData.remove('created_by');

    debugPrint('SUPABASE: Updating farmer: $id');
    await client.from('farmers').update(cleanData).eq('id', id);
  }

  static Future<void> deleteFarmer(String id) async {
    final hasInternet = await Connectivity().checkConnectivity().then((res) => !res.every((r) => r == ConnectivityResult.none));
    
    if (!kIsWeb && !hasInternet) {
      await LocalDatabaseService.deleteAndQueue(tableName: 'farmers', id: id);
      SyncManager().sync();
    } else {
      await deleteRecord('farmers', id);
      if (!kIsWeb) {
        // Also clean up local db immediately if it was stored
        await LocalDatabaseService.database.then((db) {
          db?.delete('farmers', where: 'id = ?', whereArgs: [id]);
        });
      }
    }
  }

  // Generic Verify Record
  static Future<void> updateReport(String id, Map<String, dynamic> data) async {
    await client.from('reports').update(data).eq('id', id);
  }

  static Future<void> verifyItem(String tableName, String id) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw 'User not authenticated';

    await client.from(tableName).update({
      'is_verified': true,
      'verified_by': userId,
      'verified_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  static Future<Map<String, dynamic>?> getFarmAndFarmerInfo(String farmId) async {
    try {
      final response = await client
          .from('farms')
          .select('*, farmers(*)')
          .eq('id', farmId)
          .maybeSingle();
      return response;
    } catch (e) {
      debugPrint('Error in getFarmAndFarmerInfo: $e');
      return null;
    }
  }

  // Farm CRUD
  static Future<List<Map<String, dynamic>>> getFarms() async {
    try {
      if (await isOffline()) throw 'Offline';
      final user = client.auth.currentUser;
      final profile = await getProfile();
      var query = client.from('farms').select('*, farmers(name)');

      final role = profile?['role'];
      if (role == 'executive' || role == 'telecaller') {
        final userId = user!.id;
        query = query.eq('assigned_to', userId);
      }

      final data = List<Map<String, dynamic>>.from(await query.order('created_at').timeout(const Duration(seconds: 4)));
      // Cache on success
      if (!kIsWeb) await LocalDatabaseService.saveCache('farms_${role ?? 'all'}', data);
      return LocalDatabaseService.mergeWithPending('farms', data);
    } catch (e) {
      debugPrint('Error in getFarms: $e');
      // Fallback to cache
      if (!kIsWeb) {
        final profile = await getProfile().catchError((_) => null);
        final role = profile?['role'];
        final cached = await LocalDatabaseService.getCache('farms_${role ?? 'all'}');
        if (cached != null) return LocalDatabaseService.mergeWithPending('farms', cached);
      }
      return [];
    }
  }

  static Future<void> addFarm(Map<String, dynamic> farmData) async {
    await client.from('farms').insert({
      ..._cleanPayload(farmData),
      'created_by': client.auth.currentUser?.id,
    });
  }

  static Future<void> updateFarm(String id, Map<String, dynamic> farmData) async {
    await client.from('farms').update(_cleanPayload(farmData)).eq('id', id);
  }

  static Future<void> deleteFarm(dynamic id) async {
    final hasInternet = await Connectivity().checkConnectivity().then((res) => !res.every((r) => r == ConnectivityResult.none));
    
    if (!kIsWeb && !hasInternet) {
      await LocalDatabaseService.deleteAndQueue(tableName: 'farms', id: id.toString());
      SyncManager().sync();
    } else {
      await client.from('farms').delete().eq('id', id);
      if (!kIsWeb) {
        await LocalDatabaseService.database.then((db) {
          db?.delete('farms', where: 'id = ?', whereArgs: [id.toString()]);
        });
      }
    }
  }

  static Future<List<Map<String, dynamic>>> getFarmsByFarmer(dynamic farmerId) async {
    try {
      if (await isOffline()) throw 'Offline';
      final response = await client
          .from('farms')
          .select()
          .eq('farmer_id', farmerId)
          .order('created_at');
      final data = List<Map<String, dynamic>>.from(response);
      
      if (!kIsWeb) await LocalDatabaseService.saveCache('farms_by_farmer_$farmerId', data);
      
      final merged = await LocalDatabaseService.mergeWithPending('farms', data);
      return merged.where((f) => f['farmer_id'].toString() == farmerId.toString()).toList();
    } catch (e) {
      debugPrint('Error in getFarmsByFarmer: $e');
      if (!kIsWeb) {
        var cached = await LocalDatabaseService.getCache('farms_by_farmer_$farmerId');
        if (cached == null || cached.isEmpty) {
          final roles = ['all', 'executive', 'admin', 'manager', 'telecaller'];
          for (final role in roles) {
            final global = await LocalDatabaseService.getCache('farms_$role');
            if (global != null && global.isNotEmpty) {
              cached = global.where((f) => f['farmer_id'].toString() == farmerId.toString()).toList();
              break;
            }
          }
        }
        final baseData = cached ?? [];
        final merged = await LocalDatabaseService.mergeWithPending('farms', baseData);
        return merged.where((f) => f['farmer_id'].toString() == farmerId.toString()).toList();
      }
      return [];
    }
  }

  // Assign farm to executive
  static Future<void> assignFarm(String farmId, String? executiveId) async {
    await client
        .from('farms')
        .update({'assigned_to': executiveId})
        .eq('id', farmId);
  }

  // Update sales target for executive
  static Future<void> updateSalesTarget(String userId, double target) async {
    await client
        .from('profiles')
        .update({'sales_target': target})
        .eq('id', userId);
  }

  // Get profile by ID
  static Future<Map<String, dynamic>?> getProfileById(String id) async {
    try {
      return await client.from('profiles').select().eq('id', id).maybeSingle();
    } catch (e) {
      return null;
    }
  }

  // Crop CRUD
  static Future<List<Map<String, dynamic>>> getCrops(dynamic farmId) async {
    try {
      if (await isOffline()) throw 'Offline';
      final response = await client
          .from('crops')
          .select()
          .eq('farm_id', farmId)
          .order('created_at', ascending: false);
      final data = List<Map<String, dynamic>>.from(response);

      if (!kIsWeb) await LocalDatabaseService.saveCache('crops_by_farm_$farmId', data);

      final merged = await LocalDatabaseService.mergeWithPending('crops', data);
      return merged.where((c) => c['farm_id'].toString() == farmId.toString()).toList();
    } catch (e) {
      debugPrint('Error in getCrops: $e');
      if (!kIsWeb) {
        var cached = await LocalDatabaseService.getCache('crops_by_farm_$farmId');
        if (cached == null || cached.isEmpty) {
          final roles = ['all', 'executive', 'admin', 'manager', 'telecaller'];
          for (final role in roles) {
            final global = await LocalDatabaseService.getCache('crops_$role');
            if (global != null && global.isNotEmpty) {
              cached = global.where((c) => c['farm_id'].toString() == farmId.toString()).toList();
              break;
            }
          }
        }
        final baseData = cached ?? [];
        final merged = await LocalDatabaseService.mergeWithPending('crops', baseData);
        return merged.where((c) => c['farm_id'].toString() == farmId.toString()).toList();
      }
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getAllCrops() async {
    try {
      final user = client.auth.currentUser;
      final profile = await getProfile();
      final role = profile?['role'];
      List<Map<String, dynamic>> data;

      if ((role == 'executive' || role == 'telecaller') && user != null) {
        final response = await client
            .from('crops')
            .select('*, farms!inner(name, assigned_to, farmers(name))')
            .eq('farms.assigned_to', user.id)
            .order('created_at', ascending: false)
            .timeout(const Duration(seconds: 4));
        data = List<Map<String, dynamic>>.from(response);
      } else {
        final response = await client
            .from('crops')
            .select('*, farms(name, farmers(name))')
            .order('created_at', ascending: false)
            .timeout(const Duration(seconds: 4));
        data = List<Map<String, dynamic>>.from(response);
      }
      // Cache on success
      if (!kIsWeb) await LocalDatabaseService.saveCache('crops_${role ?? 'all'}', data);
      return LocalDatabaseService.mergeWithPending('crops', data);
    } catch (e) {
      debugPrint('Error in getAllCrops: $e');
      // Fallback to cache
      if (!kIsWeb) {
        final profile = await getProfile().catchError((_) => null);
        final role = profile?['role'];
        final cached = await LocalDatabaseService.getCache('crops_${role ?? 'all'}');
        if (cached != null) return LocalDatabaseService.mergeWithPending('crops', cached);
        // Last resort: SQLite local table
        return await LocalDatabaseService.getData('crops');
      }
      return [];
    }
  }

  static Future<void> addCrop(Map<String, dynamic> cropData) async {
    await client.from('crops').insert(_cleanPayload(cropData));
  }

  static Future<void> updateCrop(String id, Map<String, dynamic> cropData) async {
    await client.from('crops').update(_cleanPayload(cropData)).eq('id', id);
  }

  // Stock Transaction Methods
  static Future<void> addStockTransaction(Map<String, dynamic> data) async {
    await client.from('stock_transactions').insert({
      ..._cleanPayload(data),
      'executive_id': client.auth.currentUser?.id,
    });
  }

  static Future<List<Map<String, dynamic>>> getStockTransactions(String farmId) async {
    try {
      final profile = await getProfile().catchError((_) => null);
      final role = profile?['role']?.toString().toLowerCase();
      final userId = client.auth.currentUser?.id;

      if (await isOffline()) throw 'Offline';
      
      var query = client
          .from('stock_transactions')
          .select()
          .eq('farm_id', farmId);

      // Security lockdown inside details screen
      if ((role == 'executive' || role == 'telecaller') && userId != null) {
        query = query.eq('executive_id', userId);
      }

      final response = await query.order('created_at', ascending: false);
      final data = List<Map<String, dynamic>>.from(response);
      
      final roleSuffix = role ?? 'all';
      if (!kIsWeb) await LocalDatabaseService.saveCache('stock_transactions_farm_${farmId}_$roleSuffix', data);
      
      final merged = await LocalDatabaseService.mergeWithPending('stock_transactions', data);
      var finalData = merged.where((t) => t['farm_id'].toString() == farmId.toString()).toList();
      
      // Final safeguard
      if ((role == 'executive' || role == 'telecaller') && userId != null) {
        finalData = finalData.where((t) => t['executive_id']?.toString().toLowerCase() == userId.toLowerCase()).toList();
      }
      return finalData;
    } catch (e) {
      debugPrint('Error in getStockTransactions: $e');
      if (!kIsWeb) {
        final profile = await getProfile().catchError((_) => null);
        final role = profile?['role']?.toString().toLowerCase();
        final userId = client.auth.currentUser?.id?.toLowerCase();
        final roleSuffix = role ?? 'all';

        var cached = await LocalDatabaseService.getCache('stock_transactions_farm_${farmId}_$roleSuffix');
        if (cached == null || cached.isEmpty) {
          final globalCacheKey = 'all_stock_transactions_$roleSuffix';
          final global = await LocalDatabaseService.getCache(globalCacheKey);
          if (global != null && global.isNotEmpty) {
            cached = global.where((t) => t['farm_id'].toString() == farmId.toString()).toList();
          }
        }
        final baseData = cached ?? [];
        final merged = await LocalDatabaseService.mergeWithPending('stock_transactions', baseData);
        var finalData = merged.where((t) => t['farm_id'].toString() == farmId.toString()).toList();

        if ((role == 'executive' || role == 'telecaller') && userId != null) {
          finalData = finalData.where((t) => t['executive_id']?.toString().toLowerCase() == userId).toList();
        }
        return finalData;
      }
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getAllStockTransactions() async {
    try {
      final profile = await getProfile();
      final role = profile?['role'];
      final userId = client.auth.currentUser?.id;

      var query = client
          .from('stock_transactions')
          .select('*, farms(name)');

      // Restrict to current executive's data if they are not admin/manager/store
      if ((role == 'executive' || role == 'telecaller') && userId != null) {
        query = query.eq('executive_id', userId);
      }

      final response = await query
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 4));
      
      final data = List<Map<String, dynamic>>.from(response);
      for (var item in data) {
        if (item['unit'] != null && item['unit'].toString().contains('{₹')) {
          item['unit'] = item['unit'].toString().split('{₹')[0].trim();
        }
      }
      
      final cacheKey = 'all_stock_transactions_${role ?? 'all'}';
      // Cache on success
      if (!kIsWeb) await LocalDatabaseService.saveCache(cacheKey, data);
      return LocalDatabaseService.mergeWithPending('stock_transactions', data);
    } catch (e) {
      debugPrint('Error in getAllStockTransactions: $e');
      // Fallback to cache
      if (!kIsWeb) {
        final profile = await getProfile().catchError((_) => null);
        final role = profile?['role'];
        final cacheKey = 'all_stock_transactions_${role ?? 'all'}';
        
        final userId = client.auth.currentUser?.id?.toLowerCase();
        
        final cached = await LocalDatabaseService.getCache(cacheKey);
        List<Map<String, dynamic>> rawList = [];
        if (cached != null) {
          rawList = await LocalDatabaseService.mergeWithPending('stock_transactions', cached);
        } else {
          rawList = await LocalDatabaseService.getData('stock_transactions');
        }

        // Enforce final role check safeguard on SQLite results
        if ((role == 'executive' || role == 'telecaller') && userId != null) {
          rawList = rawList.where((t) => t['executive_id']?.toString().toLowerCase() == userId).toList();
        }
        return rawList;
      }
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getStoreTransactions() async {
    try {
      final response = await client.from('store_transactions')
          .select('*, profiles!store_transactions_executive_id_fkey(full_name)')
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 4));
      
      if (response == null) return [];
      final data = List<Map<String, dynamic>>.from(response);
      for (var item in data) {
        if (item['unit'] != null && item['unit'].toString().contains('{₹')) {
          item['unit'] = item['unit'].toString().split('{₹')[0].trim();
        }
      }
      // Cache on success
      if (!kIsWeb) await LocalDatabaseService.saveCache('store_transactions', data);
      return LocalDatabaseService.mergeWithPending('store_transactions', data);
    } catch (e) {
      debugPrint('Error in getStoreTransactions: $e');
      // Fallback to cache
      if (!kIsWeb) {
        final cached = await LocalDatabaseService.getCache('store_transactions');
        if (cached != null) return LocalDatabaseService.mergeWithPending('store_transactions', cached);
        return await LocalDatabaseService.getData('store_transactions');
      }
      return [];
    }
  }

  static Future<void> addReport(Map<String, dynamic> reportData) async {
    debugPrint('DEBUG: addReport - Inserting report with ID: ${reportData['id']}');
    try {
      await client.from('reports').insert({
        ..._cleanPayload(reportData),
        'created_by': client.auth.currentUser?.id,
      });
      debugPrint('DEBUG: addReport - Successfully inserted report with ID: ${reportData['id']}');
    } catch (e) {
      debugPrint('DEBUG: addReport - ERROR inserting report: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>?> getLastReportForCrop(String farmId, String cropId) async {
    try {
      final response = await client
          .from('reports')
          .select()
          .eq('farm_id', farmId)
          .eq('crop_id', cropId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return response;
    } catch (e) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> getReportsForCrop(
    String cropId, {
    String? cropName,
    String? farmId,
  }) async {
    try {
      List<Map<String, dynamic>> data;
      if (cropName != null && cropName.isNotEmpty && farmId != null) {
        final response = await client
            .from('reports')
            .select()
            .eq('farm_id', farmId)
            .or('crop_id.eq.$cropId,problem.ilike.%--- Crop: $cropName ---%')
            .order('created_at', ascending: false)
            .timeout(const Duration(seconds: 4));
        data = List<Map<String, dynamic>>.from(response);
      } else {
        final response = await client
            .from('reports')
            .select()
            .eq('crop_id', cropId)
            .order('created_at', ascending: false)
            .timeout(const Duration(seconds: 4));
        data = List<Map<String, dynamic>>.from(response);
      }
      
      if (!kIsWeb) await LocalDatabaseService.saveCache('reports_crop_$cropId', data);
      final merged = await LocalDatabaseService.mergeWithPending('reports', data);
      if (farmId != null) {
        return merged.where((r) => r['crop_id'].toString() == cropId.toString() || r['farm_id'].toString() == farmId.toString()).toList();
      }
      return merged.where((r) => r['crop_id'].toString() == cropId.toString()).toList();
    } catch (e) {
      debugPrint('Error in getReportsForCrop: $e');
      if (!kIsWeb) {
        final cached = await LocalDatabaseService.getCache('reports_crop_$cropId');
        final baseData = cached ?? [];
        final merged = await LocalDatabaseService.mergeWithPending('reports', baseData);
        if (farmId != null) {
          return merged.where((r) => r['crop_id'].toString() == cropId.toString() || r['farm_id'].toString() == farmId.toString()).toList();
        }
        return merged.where((r) => r['crop_id'].toString() == cropId.toString()).toList();
      }
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getReportsForFarm(String farmId) async {
    try {
      if (await isOffline()) throw 'Offline';
      final response = await client
          .from('reports')
          .select()
          .eq('farm_id', farmId)
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 4));
      final data = List<Map<String, dynamic>>.from(response);
      if (!kIsWeb) await LocalDatabaseService.saveCache('reports_farm_$farmId', data);
      final merged = await LocalDatabaseService.mergeWithPending('reports', data);
      return merged.where((r) => r['farm_id'].toString() == farmId.toString()).toList();
    } catch (e) {
      debugPrint('Error in getReportsForFarm: $e');
      if (!kIsWeb) {
        var cached = await LocalDatabaseService.getCache('reports_farm_$farmId');
        if (cached == null || cached.isEmpty) {
          final roles = ['admin', 'executive', 'manager', 'telecaller'];
          for (final role in roles) {
            final global = await LocalDatabaseService.getCache('all_reports_$role');
            if (global != null && global.isNotEmpty) {
              cached = global.where((r) => r['farm_id'].toString() == farmId.toString()).toList();
              break;
            }
          }
        }
        final baseData = cached ?? [];
        final merged = await LocalDatabaseService.mergeWithPending('reports', baseData);
        return merged.where((r) => r['farm_id'].toString() == farmId.toString()).toList();
      }
      return [];
    }
  }

  // ── Farm Collections ─────────────────────────────────────────────────────

  /// Insert a new amount-collection entry for a farm.
  static Future<void> addFarmCollection(Map<String, dynamic> data) async {
    await client.from('farm_collections').insert({
      ..._cleanPayload(data),
      'created_by': client.auth.currentUser?.id,
    });
  }

  /// Fetch all collection entries for all farms, newest first.
  static Future<List<Map<String, dynamic>>> getAllCollections() async {
    try {
      if (await isOffline()) throw 'Offline';
      
      final profile = await getProfile();
      final role = profile?['role'];
      final userId = client.auth.currentUser?.id;

      var query = client.from('farm_collections').select();
      
      if ((role == 'executive' || role == 'telecaller') && userId != null) {
        query = query.eq('created_by', userId);
      }

      final response = await query.order('created_at', ascending: false);
      final data = List<Map<String, dynamic>>.from(response);

      final cacheKey = 'all_collections_${role ?? 'all'}';
      if (!kIsWeb) await LocalDatabaseService.saveCache(cacheKey, data);

      return await LocalDatabaseService.mergeWithPending('farm_collections', data);
    } catch (e) {
      debugPrint('Error in getAllCollections: $e');
      if (!kIsWeb) {
        final profile = await getProfile().catchError((_) => null);
        final role = profile?['role'];
        final cacheKey = 'all_collections_${role ?? 'all'}';

        final userId = client.auth.currentUser?.id?.toLowerCase();

        final cached = await LocalDatabaseService.getCache(cacheKey);
        final baseData = cached ?? [];
        var rawList = await LocalDatabaseService.mergeWithPending('farm_collections', baseData);

        // Enforce final role check safeguard on SQLite results
        if ((role == 'executive' || role == 'telecaller') && userId != null) {
          rawList = rawList.where((t) => t['created_by']?.toString().toLowerCase() == userId).toList();
        }
        return rawList;
      }
      return [];
    }
  }

  /// Fetch all collection entries for a specific farm, newest first.
  static Future<List<Map<String, dynamic>>> getFarmCollections(String farmId) async {
    try {
      final profile = await getProfile().catchError((_) => null);
      final role = profile?['role']?.toString().toLowerCase();
      final userId = client.auth.currentUser?.id;

      if (await isOffline()) throw 'Offline';

      var query = client
          .from('farm_collections')
          .select()
          .eq('farm_id', farmId);

      // Security lockdown inside details screen
      if ((role == 'executive' || role == 'telecaller') && userId != null) {
        query = query.eq('created_by', userId);
      }

      final response = await query.order('created_at', ascending: false);
      final data = List<Map<String, dynamic>>.from(response);

      final roleSuffix = role ?? 'all';
      if (!kIsWeb) await LocalDatabaseService.saveCache('collections_farm_${farmId}_$roleSuffix', data);

      final merged = await LocalDatabaseService.mergeWithPending('farm_collections', data);
      var finalData = merged.where((c) => c['farm_id'].toString() == farmId.toString()).toList();

      // Final safeguard
      if ((role == 'executive' || role == 'telecaller') && userId != null) {
        finalData = finalData.where((c) => c['created_by']?.toString().toLowerCase() == userId.toLowerCase()).toList();
      }
      return finalData;
    } catch (e) {
      debugPrint('Error in getFarmCollections: $e');
      if (!kIsWeb) {
        final profile = await getProfile().catchError((_) => null);
        final role = profile?['role']?.toString().toLowerCase();
        final userId = client.auth.currentUser?.id?.toLowerCase();
        final roleSuffix = role ?? 'all';

        final cached = await LocalDatabaseService.getCache('collections_farm_${farmId}_$roleSuffix');
        final baseData = cached ?? [];
        final merged = await LocalDatabaseService.mergeWithPending('farm_collections', baseData);
        var finalData = merged.where((c) => c['farm_id'].toString() == farmId.toString()).toList();

        if ((role == 'executive' || role == 'telecaller') && userId != null) {
          finalData = finalData.where((c) => c['created_by']?.toString().toLowerCase() == userId).toList();
        }
        return finalData;
      }
      return [];
    }
  }

  /// Return the sum of all collected amounts for a farm.
  static Future<double> getTotalCollectedForFarm(String farmId) async {
    final collections = await getFarmCollections(farmId);
    return collections.fold<double>(
      0.0,
      (double sum, c) => sum + (double.tryParse(c['amount'].toString()) ?? 0.0),
    );
  }

  static Future<List<Map<String, dynamic>>> getReports({String? columns}) async {
    try {
      final user = client.auth.currentUser;
      final profile = await getProfile();
      
      final role = profile?['role'];
      if ((role == 'executive' || role == 'telecaller') && user != null) {
        // Executives/Telecallers only see reports for farms assigned to them
        // Fallback: Just get all reports created by this user
        final response = await client
            .from('reports')
            .select(columns ?? '*, farms(name, assigned_to, farmers(name)), crops(name)')
            .eq('created_by', user.id)
            .order('created_at', ascending: false)
            .timeout(const Duration(seconds: 4));
        
        final reportsList = List<Map<String, dynamic>>.from(response);
        debugPrint('DEBUG: getReports - FALLBACK fetch by created_by returned ${reportsList.length} reports');
        if (!kIsWeb) await LocalDatabaseService.saveCache('all_reports_${role}', reportsList);
        return LocalDatabaseService.mergeWithPending('reports', reportsList);
      } else {
        // Admins see all reports
        final response = await client
            .from('reports')
            .select(columns ?? '*, farms(name, farmers(name)), crops(name)')
            .order('created_at', ascending: false)
            .timeout(const Duration(seconds: 4));
        final reportsList = List<Map<String, dynamic>>.from(response);
        if (!kIsWeb) await LocalDatabaseService.saveCache('all_reports_admin', reportsList);
        return LocalDatabaseService.mergeWithPending('reports', reportsList);
      }
    } catch (e) {
      debugPrint('Error in getReports: $e');
      if (!kIsWeb) {
        final profile = await getProfile().catchError((_) => null);
        final role = profile?['role'];
        final cacheKey = (role == 'executive' || role == 'telecaller') ? 'all_reports_${role}' : 'all_reports_admin';
        final cached = await LocalDatabaseService.getCache(cacheKey);
        if (cached != null) return LocalDatabaseService.mergeWithPending('reports', cached);
      }
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getReportsByExecutive(
    String userId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      var query = client
          .from('reports')
          .select('*, farms!inner(name, assigned_to, farmers(name)), crops(name)')
        .eq('created_by', userId);

    if (startDate != null) {
      query = query.gte('created_at', startDate.toIso8601String());
    }
    if (endDate != null) {
      query = query.lte('created_at', endDate.toIso8601String());
    }

    final response = await query.order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error in getReportsByExecutive: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getRecentActivities() async {
    try {
      // Combine 5 latest farmers and 5 latest reports
      final farmers = await getFarmers();
      final reports = await getReports();
      
      List<Map<String, dynamic>> activities = [];
      
      for (var f in farmers.take(5)) {
        activities.add({
          'type': 'new_farmer',
          'title': 'Farmer Added',
          'subtitle': '${f['name']} was added',
          'created_at': f['created_at'],
        });
      }
      
      for (var r in reports.take(5)) {
        final farmName = r['farms']?['name'] ?? 'Unknown Farm';
        activities.add({
          'type': 'report_generated',
          'title': 'Report Generated',
          'subtitle': 'Analysis for $farmName',
          'created_at': r['created_at'],
        });
      }
      
      // Sort combined activities by created_at descending
      activities.sort((a, b) => 
          DateTime.parse(b['created_at'].toString()).compareTo(
          DateTime.parse(a['created_at'].toString())));
          
      return activities.take(5).toList();
    } catch (e) {
      debugPrint('Error in getRecentActivities: $e');
      return [];
    }
  }

  static Future<String> uploadImage(Uint8List bytes, String fileName, String bucketId) async {
    try {
      await client.storage.from(bucketId).uploadBinary(fileName, bytes);
    } catch (e) {
      if (e.toString().contains('Bucket not found') || 
          e.toString().contains('404')) {
        try {
          // Attempt to create the bucket with public access
          await client.storage.createBucket(
            bucketId, 
            const BucketOptions(public: true)
          );
          // Retry upload
          await client.storage.from(bucketId).uploadBinary(fileName, bytes);
        } catch (_) {
          // If creation fails, rethrow the original error
          rethrow;
        }
      } else {
        rethrow;
      }
    }
    return client.storage.from(bucketId).getPublicUrl(fileName);
  }

  // Get User statistics
  static Future<Map<String, int>> getUserStats() async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return {'farmers': 0, 'farms': 0, 'reports': 0};

    final profile = await getProfile();
    final role = profile?['role'];

    if (role == 'store') {
      final stock = await getStoreStock();
      final transResponse = await client.from('store_transactions').select('id').eq('status', 'ACCEPTED').count(CountOption.exact);
      final pendingResponse = await client.from('store_transactions').select('id').eq('status', 'PENDING').count(CountOption.exact);
      
      return {
        'stock': stock.length,
        'trans': transResponse.count ?? 0,
        'pending': pendingResponse.count ?? 0,
      };
    }

    // Farmers count
    var farmersQuery = client.from('farmers').select('id');
    if (role == 'executive' || role == 'telecaller') farmersQuery = farmersQuery.eq('created_by', userId);
    final farmersRes = await farmersQuery.count(CountOption.exact);

    // Farms count
    var farmsQuery = client.from('farms').select('id');
    if (role == 'executive' || role == 'telecaller') farmsQuery = farmsQuery.eq('assigned_to', userId);
    final farmsRes = await farmsQuery.count(CountOption.exact);

    // Reports count
    var reportsQuery = client.from('reports').select('id');
    if (role == 'executive' || role == 'telecaller') {
      reportsQuery = reportsQuery.eq('created_by', userId);
    }
    final reportsRes = await reportsQuery.count(CountOption.exact);

    return {
      'farmers': farmersRes.count ?? 0,
      'farms': farmsRes.count ?? 0,
      'reports': reportsRes.count ?? 0,
    };
  }

  // Update profile
  static Future<void> updateProfile(Map<String, dynamic> data) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    await client.from('profiles').update(_cleanPayload(data)).eq('id', userId);
    _cachedProfile = null;
  }

  // Update password
  static Future<void> updatePassword(String newPassword) async {
    await client.auth.updateUser(UserAttributes(password: newPassword));
  }

  // Send password reset email
  static Future<void> resetPasswordForEmail(String email) async {
    await client.auth.resetPasswordForEmail(
      email,
      redirectTo: 'io.supabase.naturebiotic://login-callback/',
    );
  }

  // Dropdown Options CRUD
  static Future<List<Map<String, dynamic>>> getDropdownOptions(String type, {int? parentId}) async {
    try {
      if (await isOffline()) throw 'Offline';
      var query = client.from('dropdown_options').select().eq('type', type);
      if (parentId != null) {
        query = query.eq('parent_id', parentId);
      }
      
      final response = await query.order('label').timeout(const Duration(seconds: 4));
      final List<Map<String, dynamic>> options = List<Map<String, dynamic>>.from(response);

      // Reorder to keep 'Others' or 'Other' at the last
      final otherIndex = options.indexWhere((opt) {
        final label = opt['label'].toString().toLowerCase();
        return label == 'others' || label == 'other';
      });

      if (otherIndex != -1) {
        final otherItem = options.removeAt(otherIndex);
        options.add(otherItem);
      }

      if (!kIsWeb) await LocalDatabaseService.saveCache('dropdown_options_${type}_${parentId ?? "none"}', options);
      return options;
    } catch (e) {
      debugPrint('Error in getDropdownOptions ($type): $e');
      if (!kIsWeb) {
        final cached = await LocalDatabaseService.getCache('dropdown_options_${type}_${parentId ?? "none"}');
        if (cached != null && cached.isNotEmpty) return cached;

        // Secondary fallback to global dropdown cache
        final allOptions = await LocalDatabaseService.getCache('all_dropdown_options');
        if (allOptions != null) {
          var filtered = allOptions.where((o) => o['type'] == type).toList();
          if (parentId != null) {
            filtered = filtered.where((o) => o['parent_id'] == parentId).toList();
          }
          
          if (filtered.isNotEmpty) {
            // Reorder to keep 'Others' or 'Other' at the last
            final otherIndex = filtered.indexWhere((opt) {
              final label = opt['label'].toString().toLowerCase();
              return label == 'others' || label == 'other';
            });

            if (otherIndex != -1) {
              final otherItem = filtered.removeAt(otherIndex);
              filtered.add(otherItem);
            }
            return filtered;
          }
        }
      }
      return [];
    }
  }

  // --- Store Management Methods ---

  static Future<void> addStoreTransaction(Map<String, dynamic> data) async {
    final cleanData = _cleanPayload(data);
    // Ensure nested profiles mapping isn't sent in raw insert if it's there
    cleanData.remove('profiles');
    await client.from('store_transactions').insert({
      ...cleanData,
      'created_by': client.auth.currentUser?.id,
    });
  }

  static Future<void> updateStoreTransaction(String id, Map<String, dynamic> data) async {
    final cleanData = _cleanPayload(data);
    cleanData.remove('profiles');
    await client.from('store_transactions').update(cleanData).eq('id', id);
  }

  static Future<List<Map<String, dynamic>>> getPendingStoreTransactions() async {
    try {
      final user = client.auth.currentUser;
      if (user == null) return [];
      
      final profile = await getProfile();
      final role = profile?['role'];

      var query = client.from('store_transactions').select('*, profiles:executive_id(full_name)').eq('status', 'PENDING');

      if (role == 'executive' || role == 'telecaller') {
        // Executive/Telecaller only sees pending deliveries sent TO them
        query = query.eq('executive_id', user.id).eq('transaction_type', 'DELIVERY');
      } else if (role == 'store') {
        // Store sees pending returns sent TO the store AND product requests
        query = query.inFilter('transaction_type', ['RETURN', 'REQUEST']);
      } else {
        // Admin sees all pending deliveries, returns, and requests
      }

      final response = await query.order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error in getPendingStoreTransactions: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getRejectedStoreTransactions() async {
    try {
      final user = client.auth.currentUser;
      if (user == null) return [];
      
      final profile = await getProfile();
      final role = profile?['role'];

      // Only Admin and Store workers care about rejected deliveries they sent
      if (role != 'admin' && role != 'store' && role != 'executive' && role != 'telecaller') return [];
      
      if (role == 'admin' || role == 'store') {
        final response = await client.from('store_transactions')
            .select('*, profiles:executive_id(full_name)')
            .eq('status', 'REJECTED')
            .eq('transaction_type', 'DELIVERY')
            .order('created_at', ascending: false);

        return List<Map<String, dynamic>>.from(response);
      } else {
        final userId = user.id;
        final response = await client.from('store_transactions')
            .select('*, profiles:executive_id(full_name)')
            .eq('executive_id', userId)
            .eq('status', 'REJECTED')
            .eq('transaction_type', 'DELIVERY')
            .order('created_at', ascending: false);

        return List<Map<String, dynamic>>.from(response);
      }
    } catch (e) {
      debugPrint('Error in getRejectedStoreTransactions: $e');
      return [];
    }
  }

  static Future<void> acknowledgeRejectedTransaction(String transactionId) async {
    try {
      await client.from('store_transactions').update({
        'status': 'REJECTED_ACKNOWLEDGED',
      }).eq('id', transactionId);
    } catch (e) {
      debugPrint('Error in acknowledgeRejectedTransaction: $e');
      rethrow;
    }
  }

  static Future<void> updateStoreTransactionStatus(String id, String status) async {
    await client.from('store_transactions').update({
      'status': status,
      'accepted_at': status == 'ACCEPTED' ? DateTime.now().toIso8601String() : null,
    }).eq('id', id);
  }

  static Future<void> approveProductRequest(String id) async {
    // When a request is approved, it turns into a PENDING DELIVERY
    await client.from('store_transactions').update({
      'transaction_type': 'DELIVERY',
      'status': 'PENDING',
    }).eq('id', id);
  }

  static Future<void> deleteStoreTransaction(String id) async {
    await client.from('store_transactions').delete().eq('id', id);
  }

  static Future<Map<String, double>> getStoreStock() async {
    try {
      final transactions = await getStoreTransactions();
      return _calculateStock(transactions);
    } catch (e) {
      debugPrint('Error in getStoreStock: $e');
      return {};
    }
  }

  static Future<Map<String, double>> getUnifiedStoreStock() async {
    try {
      final transactions = await getUnifiedStoreTransactions();
      final result = _calculateStock(transactions);
      // Cache the flattened result for offline use
      if (!kIsWeb) {
        final serializable = result.entries
            .map((e) => {'item': e.key, 'qty': e.value})
            .toList();
        await LocalDatabaseService.saveCache('unified_store_stock', serializable);
      }
      return result;
    } catch (e) {
      debugPrint('Error in getUnifiedStoreStock: $e');
      // Fallback to cached stock
      if (!kIsWeb) {
        final cached = await LocalDatabaseService.getCache('unified_store_stock');
        if (cached != null) {
          return Map.fromEntries(
            cached.map((e) => MapEntry(e['item'].toString(), (e['qty'] as num).toDouble())),
          );
        }
      }
      return await getStoreStock();
    }
  }

  static Future<Map<String, Map<String, double>>> getDetailedStoreStock() async {
    try {
      final transactions = await getUnifiedStoreTransactions();
      final result = _calculateDetailedStock(transactions);
      // Cache the nested result — serialized as flat list
      if (!kIsWeb) {
        final serializable = result.entries.expand((outer) {
          return outer.value.entries.map((inner) => {
            'item': outer.key,
            'unit': inner.key,
            'qty': inner.value,
          });
        }).toList();
        await LocalDatabaseService.saveCache('detailed_store_stock', serializable);
      }
      return result;
    } catch (e) {
      debugPrint('Error in getDetailedStoreStock: $e');
      // Fallback to cached detailed stock
      if (!kIsWeb) {
        final cached = await LocalDatabaseService.getCache('detailed_store_stock');
        if (cached != null) {
          final Map<String, Map<String, double>> rebuilt = {};
          for (var row in cached) {
            final item = row['item'].toString();
            final unit = row['unit'].toString();
            final qty = (row['qty'] as num).toDouble();
            rebuilt.putIfAbsent(item, () => {})[unit] = qty;
          }
          return rebuilt;
        }
      }
      return {};
    }
  }

  static Future<List<Map<String, dynamic>>> getUnifiedStoreTransactions() async {
    // 1. Get remote transactions
    final remote = await getStoreTransactions();
    
    // 2. Get local transactions (if not web)
    List<Map<String, dynamic>> local = [];
    if (!kIsWeb) {
      local = await LocalDatabaseService.getData('store_transactions');
    }

    // 3. Merge (prefer remote if same ID)
    final Map<String, Map<String, dynamic>> merged = {};
    
    for (var tx in local) {
      merged[tx['id'].toString()] = tx;
    }
    
    for (var tx in remote) {
      merged[tx['id'].toString()] = tx;
    }

    return merged.values.toList();
  }

  static Map<String, Map<String, double>> _calculateDetailedStock(List<Map<String, dynamic>>? transactions) {
    Map<String, Map<String, double>> stock = {};
    if (transactions == null) return stock;

    for (var tx in transactions.where((t) => t['status'] == 'ACCEPTED' || t['transaction_type'] == 'PURCHASE')) {
      final item = (tx['item_name']?.toString() ?? 'Unknown').trim();
      final qty = double.tryParse(tx['quantity']?.toString() ?? '0') ?? 0.0;
      final type = tx['transaction_type']?.toString();
      final rawUnit = tx['unit']?.toString() ?? 'Units';
      final unit = rawUnit.split(' {₹')[0].trim();

      if (!stock.containsKey(item)) stock[item] = {};

      if (type == 'PURCHASE' || type == 'RETURN') {
        stock[item]![unit] = (stock[item]![unit] ?? 0.0) + qty;
      } else if (type == 'DELIVERY') {
        stock[item]![unit] = (stock[item]![unit] ?? 0.0) - qty;
      }
    }
    return stock;
  }

  static Map<String, double> _calculateStock(List<Map<String, dynamic>>? transactions) {
    Map<String, double> stock = {};
    if (transactions == null) return stock;

    for (var tx in transactions.where((t) => t['status'] == 'ACCEPTED' || t['transaction_type'] == 'PURCHASE')) {
      final item = tx['item_name']?.toString() ?? 'Unknown';
      final qty = double.tryParse(tx['quantity']?.toString() ?? '0') ?? 0.0;
      final type = tx['transaction_type']?.toString();

      if (type == 'PURCHASE' || type == 'RETURN') {
        stock[item] = (stock[item] ?? 0.0) + qty;
      } else if (type == 'DELIVERY') {
        stock[item] = (stock[item] ?? 0.0) - qty;
      }
    }
    return stock;
  }

  static Future<Map<String, dynamic>> addDropdownOption(String type, String label, {int? parentId, double? mrp, double? offerPrice, String? imageUrl}) async {
    final data = {
      'type': type,
      'label': label,
      'parent_id': parentId,
      'mrp': mrp,
      'offer_price': offerPrice,
      'image_url': imageUrl,
    };
    final response = await client.from('dropdown_options').insert(_cleanPayload(data)).select().single();
    return response;
  }

  static Future<void> updateDropdownOption(int id, String label, {double? mrp, double? offerPrice, String? imageUrl}) async {
    await client.from('dropdown_options').update({
      'label': label,
      'mrp': mrp,
      'offer_price': offerPrice,
      'image_url': imageUrl,
    }).eq('id', id);
  }

  static Future<void> deleteDropdownOption(int id) async {
    await client.from('dropdown_options').delete().eq('id', id);
  }

  static Future<List<Map<String, dynamic>>> getHierarchicalDropdownOptions(String type) async {
    try {
      if (await isOffline()) throw 'Offline';
      final response = await client
          .from('dropdown_options')
          .select('*, variants:dropdown_options(*)')
          .eq('type', type)
          .filter('parent_id', 'is', null)
          .order('label')
          .timeout(const Duration(seconds: 4));
      final data = List<Map<String, dynamic>>.from(response);
      // Cache — this is critical for offline report creation
      if (!kIsWeb) await LocalDatabaseService.saveCache('dropdown_$type', data);
      return data;
    } catch (e) {
      debugPrint('Error in getHierarchicalDropdownOptions ($type): $e');
      // Fallback to cache
      if (!kIsWeb) {
        final cached = await LocalDatabaseService.getCache('dropdown_$type');
        if (cached != null && cached.isNotEmpty) return cached;

        // Secondary fallback to global dropdown cache
        final allOptions = await LocalDatabaseService.getCache('all_dropdown_options');
        if (allOptions != null) {
          final filtered = allOptions
              .where((o) => o['type'] == type && o['parent_id'] == null)
              .toList();
          
          if (filtered.isNotEmpty) {
            for (var item in filtered) {
              item['variants'] = allOptions
                  .where((o) => o['parent_id'] == item['id'])
                  .toList();
            }
            return filtered;
          }
        }
      }
      return [];
    }
  }

  static Future<void> syncAllDropdownOptions() async {
    try {
      if (await isOffline()) return;
      
      // Fetch all dropdown options
      final dropResponse = await client.from('dropdown_options').select().order('label');
      final dropData = List<Map<String, dynamic>>.from(dropResponse);
      if (!kIsWeb) await LocalDatabaseService.saveCache('all_dropdown_options', dropData);

      // Fetch all crop-problem mappings
      final mapResponse = await client.from('crop_problem_mapping').select('*, dropdown_options(*)');
      final mapData = List<Map<String, dynamic>>.from(mapResponse);
      if (!kIsWeb) await LocalDatabaseService.saveCache('all_crop_problem_mappings', mapData);
      
      debugPrint('SYNC: All dropdowns and mappings cached.');
    } catch (e) {
      debugPrint('Error syncing all dropdown options: $e');
    }
  }

  // Master Crop CRUD
  static Future<List<Map<String, dynamic>>> getMasterCrops() async {
    try {
      if (await isOffline()) throw 'Offline';
      final response = await client
          .from('master_crops')
          .select('*, master_crop_varieties(*)')
          .order('name')
          .timeout(const Duration(seconds: 4));
      final data = List<Map<String, dynamic>>.from(response);
      if (!kIsWeb) await LocalDatabaseService.saveCache('master_crops', data);
      return data;
    } catch (e) {
      debugPrint('Error in getMasterCrops: $e');
      if (!kIsWeb) {
        final cached = await LocalDatabaseService.getCache('master_crops');
        if (cached != null) return cached;
      }
      return [];
    }
  }

  static Future<void> addMasterCrop(String name) async {
    await client.from('master_crops').insert({'name': name});
  }

  static Future<void> addMasterVariety(int cropId, String variety, String life) async {
    await client.from('master_crop_varieties').insert({
      'crop_id': cropId,
      'variety_name': variety,
      'life': life,
    });
  }

  static Future<void> updateMasterVariety(int id, String variety, String life) async {
    await client.from('master_crop_varieties').update({
      'variety_name': variety,
      'life': life,
    }).eq('id', id);
  }

  static Future<void> deleteMasterCrop(int id) async {
    await client.from('master_crops').delete().eq('id', id);
  }

  static Future<void> deleteMasterVariety(int id) async {
    await client.from('master_crop_varieties').delete().eq('id', id);
  }

  // Crop-Problem Mapping Methods
  static Future<List<Map<String, dynamic>>> getCropProblemMappings(int problemId) async {
    final response = await client
        .from('crop_problem_mapping')
        .select('*, master_crops(*)')
        .eq('problem_id', problemId);
    return List<Map<String, dynamic>>.from(response);
  }

  static Future<List<Map<String, dynamic>>> getProblemsByCrop(int cropId) async {
    try {
      if (await isOffline()) throw 'Offline';
      final response = await client
          .from('crop_problem_mapping')
          .select('*, dropdown_options(*)')
          .eq('crop_id', cropId)
          .timeout(const Duration(seconds: 4));
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error in getProblemsByCrop: $e');
      if (!kIsWeb) {
        final cached = await LocalDatabaseService.getCache('all_crop_problem_mappings');
        if (cached != null) {
          return cached.where((m) => m['crop_id'] == cropId).toList();
        }
      }
      return [];
    }
  }

  static Future<void> updateCropProblemMappings(int problemId, List<int> cropIds) async {
    // 1. Delete existing mappings for this problem
    await client.from('crop_problem_mapping').delete().eq('problem_id', problemId);
    
    // 2. Insert new mappings
    if (cropIds.isNotEmpty) {
      final List<Map<String, dynamic>> inserts = cropIds.map((cropId) => {
        'problem_id': problemId,
        'crop_id': cropId,
      }).toList();
      await client.from('crop_problem_mapping').insert(inserts);
    }
  }

  // Attendance Methods
  static Future<Map<String, dynamic>?> getTodayAttendance({String? userId}) async {
    final targetUserId = userId ?? client.auth.currentUser?.id;
    if (targetUserId == null) return null;

    final startOfDay = DateTime.now().copyWith(hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);
    
    try {
      final response = await client
          .from('attendance')
          .select()
          .eq('user_id', targetUserId)
          .gte('created_at', startOfDay.toIso8601String())
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return response;
    } catch (e) {
      return null;
    }
  }

  static Future<void> checkIn(Map<String, dynamic> data) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw 'User not authenticated';

    await client.from('attendance').insert({
      ..._cleanPayload(data),
      'user_id': userId,
      'status': 'present',
    });
  }

  static Future<void> checkOut(String attendanceId, Map<String, dynamic> data) async {
    await client.from('attendance').update(_cleanPayload(data)).eq('id', attendanceId);
  }

  static Future<List<Map<String, dynamic>>> getAttendanceLogs({String? userId}) async {
    final targetUserId = userId ?? client.auth.currentUser?.id;
    if (targetUserId == null) return [];

    final response = await client
        .from('attendance')
        .select()
        .eq('user_id', targetUserId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  static Future<void> requestLeave(Map<String, dynamic> leaveData) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw 'User not authenticated';

    await client.from('leaves').insert({
      ..._cleanPayload(leaveData),
      'user_id': userId,
      'status': 'Pending',
    });
  }

  // --- Attendance Analytics ---

  static Future<Map<String, int>> getPersonalMonthlyStats() async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return {'present': 0, 'absent': 0};

    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    
    // 1. Get present days (distinct days with check-ins)
    final response = await client
        .from('attendance')
        .select('created_at')
        .eq('user_id', userId)
        .gte('created_at', startOfMonth.toIso8601String());
    
    final List<Map<String, dynamic>> logs = List<Map<String, dynamic>>.from(response);
    final Set<String> distinctDays = logs.map((log) {
      final date = DateTime.parse(log['created_at']);
      return '${date.year}-${date.month}-${date.day}';
    }).toSet();
    
    final presentCount = distinctDays.length;

    // 2. Calculate working days passed in month (excluding Sundays)
    int workingDaysPassed = 0;
    for (int i = 1; i <= now.day; i++) {
        final day = DateTime(now.year, now.month, i);
        if (day.weekday != DateTime.sunday) {
            workingDaysPassed++;
        }
    }

    return {
      'present': presentCount,
      'absent': (workingDaysPassed - presentCount).clamp(0, workingDaysPassed),
    };
  }

  static Future<Map<String, int>> getTeamTodayStats() async {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    
    // 1. Get total field staff (Executives and Telecallers)
    final execResponse = await client
        .from('profiles')
        .select('id')
        .inFilter('role', ['executive', 'telecaller']);
    final totalExecutives = (execResponse as List).length;

    if (totalExecutives == 0) return {'present': 0, 'absent': 0};

    // 2. Get distinct users who checked in today
    final attendanceResponse = await client
        .from('attendance')
        .select('user_id')
        .gte('created_at', startOfToday.toIso8601String());
    
    final List<Map<String, dynamic>> logs = List<Map<String, dynamic>>.from(attendanceResponse);
    final Set<String> distinctUserIds = logs.map((log) => log['user_id'].toString()).toSet();
    
    final presentToday = distinctUserIds.length;

    return {
      'present': presentToday,
      'absent': (totalExecutives - presentToday).clamp(0, totalExecutives),
    };
  }

  static Future<List<Map<String, dynamic>>> getMyLeaves({String? userId}) async {
    final targetUserId = userId ?? client.auth.currentUser?.id;
    if (targetUserId == null) return [];

    final response = await client
        .from('leaves')
        .select()
        .eq('user_id', targetUserId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  static Future<List<Map<String, dynamic>>> getAllLeaves() async {
    try {
      // 1. Fetch all leaves
      final leavesResponse = await client
          .from('leaves')
          .select()
          .order('created_at', ascending: false);
      
      final List<Map<String, dynamic>> leaves = List<Map<String, dynamic>>.from(leavesResponse);
      if (leaves.isEmpty) return [];

      // 2. Fetch profiles for these leaves to avoid join errors
      final userIds = leaves.map((l) => l['user_id']).toSet().toList();
      final profilesResponse = await client
          .from('profiles')
          .select('id, full_name')
          .inFilter('id', userIds);
      
      final Map<String, dynamic> profilesMap = {
        for (var p in profilesResponse) p['id']: p
      };

      // 3. Manually join them
      return leaves.map((leave) {
        return {
          ...leave,
          'profiles': profilesMap[leave['user_id']] ?? {'full_name': 'Unknown Executive'}
        };
      }).toList();
    } catch (e) {
      print('Error in getAllLeaves: $e');
      rethrow;
    }
  }

  static Future<void> updateLeaveStatus(String id, String status) async {
    await client.from('leaves').update({'status': status}).eq('id', id);
  }

  // Call Log Methods
  static Future<void> addCallLog(Map<String, dynamic> logData) async {
    // Convert 'null' string or empty string to actual null for farmer_id
    final farmerId = (logData['farmer_id'] == null || logData['farmer_id'].toString().isEmpty || logData['farmer_id'] == 'null')
      ? null 
      : logData['farmer_id'];

    await client.from('call_logs').insert({
      ..._cleanPayload(logData),
      'farmer_id': farmerId,
      'executive_id': client.auth.currentUser?.id,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> getCallLogs({
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final profile = await getProfile();
    var query = client.from('call_logs').select('*, profiles(full_name), farmers(name)');
    
    if (userId != null) {
      query = query.eq('executive_id', userId);
    } else if (profile?['role'] == 'executive' || profile?['role'] == 'telecaller') {
      query = query.eq('executive_id', client.auth.currentUser!.id);
    }

    if (startDate != null) {
      final startOfDate = DateTime(startDate.year, startDate.month, startDate.day);
      query = query.gte('start_time', startOfDate.toIso8601String());
    }
    if (endDate != null) {
      // End of the selected day
      final endOfDate = endDate.copyWith(hour: 23, minute: 59, second: 59);
      query = query.lte('start_time', endOfDate.toIso8601String());
    }
    
    final response = await query.order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  // Sign out
  static Future<void> signOut() async {
    _cachedProfile = null; // Clear cached profile on sign out
    await client.auth.signOut();
  }

  // --- Individual Executive Stock Logic ---

  static Future<Map<String, Map<String, double>>> getDetailedExecutiveStock({String? userId}) async {
    try {
      final targetUserId = userId ?? client.auth.currentUser?.id;
      if (targetUserId == null) return {};

      final storeTxsResponse = await client.from('store_transactions').select().eq('executive_id', targetUserId);
      final usageResponse = await client.from('stock_transactions').select().eq('executive_id', targetUserId);

      final txs = List<Map<String, dynamic>>.from(storeTxsResponse);
      final usage = List<Map<String, dynamic>>.from(usageResponse);

      Map<String, Map<String, double>> stock = {};

      void updateStock(String item, String unit, double qty) {
        if (!stock.containsKey(item)) stock[item] = {};
        stock[item]![unit] = (stock[item]![unit] ?? 0.0) + qty;
      }

      // 1. Add accepted deliveries
      for (var tx in txs.where((t) => t['transaction_type'] == 'DELIVERY' && t['status'] == 'ACCEPTED')) {
        final item = (tx['item_name']?.toString() ?? 'Unknown').trim();
        final rawUnit = tx['unit']?.toString() ?? 'Units';
        final unit = rawUnit.split(' {₹')[0].trim();
        
        updateStock(
          item,
          unit,
          double.tryParse(tx['quantity']?.toString() ?? '0') ?? 0.0
        );
      }

      // 2. Subtract accepted returns
      for (var tx in txs.where((t) => t['transaction_type'] == 'RETURN' && t['status'] == 'ACCEPTED')) {
        final item = (tx['item_name']?.toString() ?? 'Unknown').trim();
        final rawUnit = tx['unit']?.toString() ?? 'Units';
        final unit = rawUnit.split(' {₹')[0].trim();

        updateStock(
          item,
          unit,
          -(double.tryParse(tx['quantity']?.toString() ?? '0') ?? 0.0)
        );
      }

      // 3. Subtract field usage (Farm stock transactions)
      for (var u in usage) {
        final type = u['transaction_type']?.toString().toUpperCase();
        final qty = double.tryParse(u['quantity']?.toString() ?? '0') ?? 0.0;
        
        // Clean unit of packed metadata "{₹...}" for matching with store stock
        final rawUnit = u['unit']?.toString() ?? 'Units';
        final unit = rawUnit.split(' {₹')[0].trim();

        if (type == 'RECEIVED' || type == 'DELIVERED') {
          // Executive gave to farm -> Reduce executive stock
          updateStock(
            (u['item_name']?.toString() ?? 'Unknown').trim(),
            unit,
            -qty
          );
        } else if (type == 'RETURN') {
          // Farm returned to executive -> Increase executive stock
          updateStock(
            (u['item_name']?.toString() ?? 'Unknown').trim(),
            unit,
            qty
          );
        }
      }

      return stock;
    } catch (e) {
      debugPrint('Error in getDetailedExecutiveStock: $e');
      return {};
    }
  }

  static Future<Map<String, Map<String, double>>> getPendingDetailedStock({String? userId}) async {
    try {
      final targetUserId = userId ?? client.auth.currentUser?.id;
      if (targetUserId == null) return {};

      final response = await client.from('store_transactions')
          .select()
          .eq('executive_id', targetUserId)
          .eq('transaction_type', 'DELIVERY')
          .eq('status', 'PENDING');

      final txs = List<Map<String, dynamic>>.from(response);
      Map<String, Map<String, double>> pendingStock = {};

      for (var tx in txs) {
        final item = (tx['item_name']?.toString() ?? 'Unknown').trim();
        final rawUnit = tx['unit']?.toString() ?? 'Units';
        final unit = rawUnit.split(' {₹')[0].trim();
        final qty = double.tryParse(tx['quantity']?.toString() ?? '0') ?? 0.0;

        if (!pendingStock.containsKey(item)) pendingStock[item] = {};
        pendingStock[item]![unit] = (pendingStock[item]![unit] ?? 0.0) + qty;
      }

      return pendingStock;
    } catch (e) {
      debugPrint('Error in getPendingDetailedStock: $e');
      return {};
    }
  }

  static Future<Map<String, double>> getExecutiveStock({String? userId}) async {
    try {
      final targetUserId = userId ?? client.auth.currentUser?.id;
      if (targetUserId == null) return {};

      // 1. Get deliveries TO executive and returns FROM executive (all statuses)
      final storeTxsResponse = await client.from('store_transactions')
          .select()
          .eq('executive_id', targetUserId);
      
      // 2. Get field usage
      final usageResponse = await client.from('stock_transactions')
          .select()
          .eq('executive_id', targetUserId);

      if (storeTxsResponse == null || usageResponse == null) return {};

      final txs = List<Map<String, dynamic>>.from(storeTxsResponse);
      final usage = List<Map<String, dynamic>>.from(usageResponse);

      Map<String, double> stock = {};

      // Add accepted deliveries (ignoring pending/rejected deliveries)
      for (var tx in txs.where((t) => t['transaction_type'] == 'DELIVERY' && t['status'] == 'ACCEPTED')) {
        final item = tx['item_name']?.toString() ?? 'Unknown';
        final qty = double.tryParse(tx['quantity']?.toString() ?? '0') ?? 0.0;
        stock[item] = (stock[item] ?? 0.0) + qty;
      }

      // Subtract accepted returns (stock officially handed back to store)
      for (var tx in txs.where((t) => t['transaction_type'] == 'RETURN' && t['status'] == 'ACCEPTED')) {
        final item = tx['item_name']?.toString() ?? 'Unknown';
        final qty = double.tryParse(tx['quantity']?.toString() ?? '0') ?? 0.0;
        stock[item] = (stock[item] ?? 0.0) - qty;
      }

      // 3. Subtract field usage (Farm stock transactions)
      for (var u in usage) {
        final type = u['transaction_type']?.toString().toUpperCase();
        final itemName = u['item_name']?.toString() ?? 'Unknown';
        final qty = double.tryParse(u['quantity']?.toString() ?? '0') ?? 0.0;

        if (type == 'RECEIVED' || type == 'DELIVERED') {
          stock[itemName] = (stock[itemName] ?? 0.0) - qty;
        } else if (type == 'RETURN') {
          stock[itemName] = (stock[itemName] ?? 0.0) + qty;
        }
      }

      return stock;
    } catch (e) {
      debugPrint('Error in getExecutiveStock: $e');
      return {};
    }
  }

  static Future<List<Map<String, dynamic>>> getExecutiveTransactions(String userId) async {
    try {
      // Get all store transactions and stock transactions related to this executive
      final storeTxsResponse = await client.from('store_transactions')
          .select('*, profiles!store_transactions_executive_id_fkey(full_name)')
          .eq('executive_id', userId)
          .order('created_at', ascending: false);

      final usageResponse = await client.from('stock_transactions')
          .select('*, farms(name)')
          .eq('executive_id', userId)
          .order('created_at', ascending: false);

      final List<Map<String, dynamic>> combined = [];
      
      final txs = storeTxsResponse != null ? List<Map<String, dynamic>>.from(storeTxsResponse) : [];
      final usage = usageResponse != null ? List<Map<String, dynamic>>.from(usageResponse) : [];
      
      for (var tx in txs) {
        combined.add({
          ...tx,
          '_source': 'store', // To distinguish between warehouse and field transactions
        });
      }

      for (var u in usage) {
        // Clean unit field
        if (u['unit'] != null && u['unit'].toString().contains('{₹')) {
          u['unit'] = u['unit'].toString().split('{₹')[0].trim();
        }
        
        combined.add({
          ...u,
          '_source': 'field',
        });
      }

      // Sort by date
      combined.sort((a, b) => 
          DateTime.parse(b['created_at']?.toString() ?? DateTime.now().toIso8601String()).compareTo(
          DateTime.parse(a['created_at']?.toString() ?? DateTime.now().toIso8601String())));

      return combined;
    } catch (e) {
      debugPrint('Error in getExecutiveTransactions: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getExecutiveStockUsage() async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return [];

    final response = await client.from('stock_transactions')
        .select('*, farms(name)')
        .eq('executive_id', userId)
        .order('created_at', ascending: false)
        .limit(20);
        
    return List<Map<String, dynamic>>.from(response);
  }

  // --- Expense Management Logic ---

  static Future<void> allotExpenseFunds(String executiveId, double amount) async {
    await client.from('expenses').insert({
      'executive_id': executiveId,
      'amount_allotted': amount,
      'allotment_status': 'PENDING',
      'status': 'ACTIVE',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<String?> startExecutiveTrip() async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return null;

    // Check if there's already an active trip
    final existing = await getActiveExpenseForExecutive(userId);
    if (existing != null) return existing['id']?.toString();

    final response = await client.from('expenses').insert({
      'executive_id': userId,
      'status': 'APPROVED',
      'allotment_status': 'RECEIVED',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    }).select().single();

    return response['id']?.toString();
  }

  static Future<void> receiveExpenseFunds(String expenseId) async {
    await client.from('expenses').update({
      'allotment_status': 'RECEIVED',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', expenseId);
  }

  static Future<void> updateTripStart({
    required String expenseId,
    required String vehicleType,
    required String ownership,
    required double odometer,
    String? photoUrl,
  }) async {
    await client.from('expenses').update({
      'vehicle_type': vehicleType,
      'vehicle_ownership': ownership,
      'start_odometer_reading': odometer,
      'start_odometer_photo': photoUrl,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', expenseId);
  }

  static Future<void> addExpenseItem({
    required String expenseId,
    required String category,
    required double amount,
    String? courierName,
    String? photoUrl,
    String? notes,
  }) async {
    await client.from('expense_items').insert({
      'expense_id': expenseId,
      'category': category,
      'amount': amount,
      'courier_name': courierName,
      'bill_photo': photoUrl,
      'notes': notes,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> updateTripEnd({
    required String expenseId,
    required double odometer,
    String? photoUrl,
  }) async {
    await client.from('expenses').update({
      'end_odometer_reading': odometer,
      'end_odometer_photo': photoUrl,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', expenseId);
  }

  static Future<void> submitReturn(String expenseId, double amount) async {
    await client.from('expenses').update({
      'return_amount': amount,
      'return_status': 'PENDING',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', expenseId);
  }

  static Future<void> resumeTrip(String expenseId) async {
    await client.from('expenses').update({
      'end_odometer_reading': null,
      'end_odometer_photo': null,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', expenseId);
  }

  static Future<void> approveReturn(String expenseId) async {
    await client.from('expenses').update({
      'return_status': 'APPROVED',
      'status': 'CLOSED',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', expenseId);
  }

  static Future<Map<String, dynamic>?> getActiveExpenseForExecutive(String userId) async {
    final response = await client.from('expenses')
        .select('*, expense_items(*)')
        .eq('executive_id', userId)
        .or('status.eq.ACTIVE,status.eq.APPROVED')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return response;
  }

  static Future<List<Map<String, dynamic>>> getExpenseHistory({
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    var query = client.from('expenses').select('*, profiles(full_name), expense_items(*)');
    
    if (userId != null) {
      query = query.eq('executive_id', userId);
    }
    
    if (startDate != null) {
      query = query.gte('created_at', startDate.copyWith(hour: 0, minute: 0, second: 0, millisecond: 0).toIso8601String());
    }
    if (endDate != null) {
      query = query.lte('created_at', endDate.copyWith(hour: 23, minute: 59, second: 59).toIso8601String());
    }
    
    final response = await query.order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  static Future<Map<String, dynamic>> getExpenseById(String id) async {
    final response = await client.from('expenses')
        .select('*, profiles(full_name), expense_items(*)')
        .eq('id', id)
        .single();
    return response;
  }

  // --- Edit Information Requests (Rise Tokens) ---

  static Future<void> submitEditRequest({
    required String entityType,
    required String entityId,
    required String fieldName,
    required String fieldLabel,
    required String oldValue,
    required String newValue,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw Exception('User must be authenticated');

    await client.from('edit_requests').insert({
      'entity_type': entityType,
      'entity_id': entityId,
      'field_name': fieldName,
      'field_label': fieldLabel,
      'old_value': oldValue,
      'new_value': newValue,
      'requested_by': user.id,
      'status': 'pending',
    });
  }

  static Future<List<Map<String, dynamic>>> getPendingEditRequests() async {
    final response = await client
        .from('edit_requests')
        .select('*, profiles!requested_by(full_name)')
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  static Future<void> processEditRequest({
    required String requestId,
    required String status, // 'approved' or 'rejected'
    required String entityType, // e.g., 'farmers'
    required String entityId,
    required String fieldName,
    required String newValue,
    String? adminNotes,
  }) async {
    // 1. If approved, perform the actual update on target table
    if (status == 'approved') {
      await client
          .from(entityType)
          .update({fieldName: newValue})
          .eq('id', entityId);
    }

    // 2. Mark the request itself as resolved
    await client
        .from('edit_requests')
        .update({
          'status': status,
          'admin_notes': adminNotes,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', requestId);
  }

  // --- Utility Methods ---

  /// Removes all keys starting with '_' to prevent sending local-only metadata to Supabase.
  static Map<String, dynamic> _cleanPayload(Map<String, dynamic> data) {
    final cleaned = Map<String, dynamic>.from(data);
    cleaned.removeWhere((key, _) => key.startsWith('_'));
    return cleaned;
  }

  // --- Admin Management Methods ---

  /// Deletes a record from any table by ID. Restricted to admins via RLS.
  static Future<void> deleteRecord(String table, dynamic id) async {
    await client.from(table).delete().eq('id', id);
  }

  /// Updates a record in any table by ID. Restricted to admins via RLS.
  static Future<void> updateRecord(String table, dynamic id, Map<String, dynamic> data) async {
    await client.from(table).update(_cleanPayload(data)).eq('id', id);
  }
}
