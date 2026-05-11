import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nature_biotic/core/theme.dart';
import 'package:nature_biotic/services/supabase_service.dart';
import 'package:nature_biotic/services/local_database_service.dart';
import 'package:nature_biotic/services/sync_manager.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:nature_biotic/features/expenses/widgets/trip_widgets.dart';
import 'package:uuid/uuid.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _todayAttendance;
  Position? _currentPosition;
  String _currentAddress = 'Fetching location...';
  XFile? _image;
  final _picker = ImagePicker();
  bool _isSubmitting = false;
  Map<String, dynamic>? _activeTrip;
  bool _isExecutive = false;
  bool _isTelecaller = false;
  bool _isManager = false;

  // Odometer Fields for integrated check-in
  final _odoController = TextEditingController();
  String? _selectedVehicle;
  String? _selectedOwnership;
  XFile? _odoImage;
  String? _odoImageUrl;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final profile = await SupabaseService.getProfile();
      _isExecutive = profile?['role'] == 'executive';
      _isTelecaller = profile?['role'] == 'telecaller';
      _isManager = profile?['role'] == 'manager';

      // 1. Try fetching from remote
      _todayAttendance = await SupabaseService.getTodayAttendance();

      if (_isExecutive || _isTelecaller || _isManager) {
        final userId = SupabaseService.client.auth.currentUser?.id;
        if (userId != null) {
          _activeTrip = await SupabaseService.getActiveExpenseForExecutive(userId);
        }
      }

      // 2. If remote is null (sync pending), check local
      if (_todayAttendance == null && !kIsWeb) {
        _todayAttendance = await LocalDatabaseService.getTodayAttendance();
      }

      await _getCurrentLocation();
    } catch (e) {
      // Fallback to local on error (e.g. offline)
      if (!kIsWeb) {
        _todayAttendance = await LocalDatabaseService.getTodayAttendance();
      }

      if (mounted && _todayAttendance == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _currentAddress = 'Location services are disabled.');
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _currentAddress = 'Location permissions are denied');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(
        () => _currentAddress = 'Location permissions are permanently denied',
      );
      return;
    }

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() {
          _currentPosition = position;
          _currentAddress =
              '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
        });
      }

      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (mounted && placemarks.isNotEmpty) {
          setState(() {
            Placemark place = placemarks[0];
            final address =
                '${place.name ?? ''} ${place.street ?? ''}, ${place.locality ?? ''}, ${place.postalCode ?? ''}'
                    .trim();
            if (address.isNotEmpty) {
              _currentAddress = address;
            }
          });
        }
      } catch (e) {
        debugPrint('Geocoding error: $e');
        // Keep the coordinates already set above
      }
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              _currentAddress =
                  'Location Error: ${e.toString().split('\n')[0]}',
        );
      }
    }
  }

  Future<void> _takePhoto() async {
    try {
      final pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 50,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (pickedFile != null) {
        setState(() => _image = pickedFile);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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

  void _showStartTripDialog() async {
    if (_activeTrip == null) {
      await SupabaseService.startExecutiveTrip();
      await _loadData();
    }

    if (!mounted || _activeTrip == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StartTripForm(
          expenseId: _activeTrip!['id'],
          onStarted: () {
            Navigator.pop(context);
            _loadData();
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
      builder: (context) => EndTripDialogContent(
        expenseId: _activeTrip!['id'],
        startOdometer: double.tryParse(_activeTrip!['start_odometer_reading']?.toString() ?? '0') ?? 0.0,
        onEnded: _loadData,
        onCapture: () => _captureAndUpload('expense-documents'),
      ),
    );
  }

  Future<void> _takeOdoPhoto() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 50,
    );
    if (photo != null) {
      setState(() => _odoImage = photo);
    }
  }

  Future<void> _handleSubmit() async {
    final isCheckedIn = _todayAttendance != null && _todayAttendance!['check_out_time'] == null;
    final isCheckIn = _todayAttendance == null;
    final needsOdometer = isCheckedIn && _activeTrip != null && _activeTrip!['start_odometer_reading'] == null;
    final tripInProgress = isCheckedIn && _activeTrip != null && _activeTrip!['start_odometer_reading'] != null && _activeTrip!['end_odometer_reading'] == null;
    final needsOdoDuringCheckIn = isCheckIn && (_isExecutive || _isManager);
    final needsTripOdo = needsOdoDuringCheckIn || (needsOdometer && (_isExecutive || _isManager));

    if (isCheckIn && _image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please take a photo first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (needsTripOdo) {
      if (_selectedVehicle == null || _selectedOwnership == null || _odoController.text.isEmpty || _odoImage == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please complete vehicle details and odometer reading'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Wait for location...'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final isCheckIn = _todayAttendance == null;

      if (isCheckIn) {
        // Mandatory offline data sync during check-in
        try {
          await SupabaseService.syncAllDropdownOptions();
        } catch (e) {
          debugPrint('Sync failed during check-in: $e');
        }
      }

      if (isCheckIn) {
        await _handleAttendance();
        if (_isExecutive || _isTelecaller || _isManager) {
          await _handleTripStart();
        }
      } else if (needsOdometer) {
        await _handleTripStart();
      } else if (tripInProgress) {
        await _handleTripEnd();
      } else {
        await _handleAttendance();
        if (_isTelecaller && _activeTrip != null) {
          await _handleTripEnd();
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              needsOdoDuringCheckIn
                  ? 'Checked In & Trip Started Successfully'
                  : needsOdometer
                      ? 'Trip Started Successfully'
                      : tripInProgress
                          ? 'Trip Ended Successfully'
                          : isCheckIn
                              ? 'Checked In Successfully'
                              : 'Checked Out Successfully',
            ),
            backgroundColor: AppColors.primary,
          ),
        );
        _loadData(); // Refresh UI
        setState(() {
          _image = null;
          _odoImage = null;
          _odoController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleAttendance() async {
    final isCheckIn = _todayAttendance == null;
    final isCheckedIn = _todayAttendance != null && _todayAttendance!['check_out_time'] == null;

    String? imageUrl;
    if (_image != null) {
      final fileName =
          '${SupabaseService.client.auth.currentUser!.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      imageUrl = await SupabaseService.uploadImage(
        await _image!.readAsBytes(),
        fileName,
        'attendance',
      );
    }

    final attendanceData = {
      if (_todayAttendance != null) 'id': _todayAttendance!['id'],
      if (isCheckIn)
        'check_in_time': DateTime.now().toIso8601String()
      else if (isCheckedIn)
        'check_out_time': DateTime.now().toIso8601String(),

      if (isCheckIn)
        'check_in_photo': imageUrl
      else if (isCheckedIn)
        'check_out_photo': imageUrl,

      if (isCheckIn)
        'check_in_location_lat': _currentPosition!.latitude
      else if (isCheckedIn)
        'check_out_location_lat': _currentPosition!.latitude,

      if (isCheckIn)
        'check_in_location_lng': _currentPosition!.longitude
      else if (isCheckedIn)
        'check_out_location_lng': _currentPosition!.longitude,

      'created_at': DateTime.now().toIso8601String(),
      '_local_photo': null,
    };

    if (kIsWeb) {
      if (isCheckIn) {
        await SupabaseService.checkIn({
          'check_in_time': DateTime.now().toIso8601String(),
          'check_in_photo': imageUrl,
          'check_in_location_lat': _currentPosition!.latitude,
          'check_in_location_lng': _currentPosition!.longitude,
        });
      } else {
        await SupabaseService.checkOut(_todayAttendance!['id'], {
          'check_out_time': DateTime.now().toIso8601String(),
          'check_out_photo': imageUrl,
          'check_out_location_lat': _currentPosition!.latitude,
          'check_out_location_lng': _currentPosition!.longitude,
        });
      }
    } else {
      await LocalDatabaseService.saveAndQueue(
        tableName: 'attendance',
        data: attendanceData,
        operation: isCheckIn ? 'INSERT' : 'UPDATE',
      );
      SyncManager().sync();
    }
  }

  Future<void> _handleTripStart() async {
    final tripId = await SupabaseService.startExecutiveTrip();
    
    if (_isTelecaller && tripId != null) {
      await SupabaseService.updateTripStart(
        expenseId: tripId,
        vehicleType: 'None',
        ownership: 'None',
        odometer: 0,
      );
      return;
    }

    if (tripId != null && _odoController.text.isNotEmpty && _odoImage != null) {
      final odoFileName = 'odo_${tripId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final odoPhotoUrl = await SupabaseService.uploadImage(
        await _odoImage!.readAsBytes(),
        odoFileName,
        'expense-documents',
      );

      await SupabaseService.updateTripStart(
        expenseId: tripId,
        vehicleType: _selectedVehicle!,
        ownership: _selectedOwnership!,
        odometer: double.parse(_odoController.text),
        photoUrl: odoPhotoUrl,
      );
    }
  }

  Future<void> _handleTripEnd() async {
    if (_activeTrip == null) return;
    
    if (_isTelecaller) {
      await SupabaseService.updateTripEnd(
        expenseId: _activeTrip!['id'],
        odometer: 0,
      );
      return;
    }

    if (_odoController.text.isEmpty || _odoImage == null) return;
    
    final odoFileName = 'odo_end_${_activeTrip!['id']}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final odoPhotoUrl = await SupabaseService.uploadImage(
      await _odoImage!.readAsBytes(),
      odoFileName,
      'expense-documents',
    );

    await SupabaseService.updateTripEnd(
      expenseId: _activeTrip!['id'],
      odometer: double.parse(_odoController.text),
      photoUrl: odoPhotoUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCheckIn = _todayAttendance == null;
    final isCheckedIn =
        _todayAttendance != null && _todayAttendance!['check_out_time'] == null;
    final isCompleted =
        _todayAttendance != null && _todayAttendance!['check_out_time'] != null;

    // Trip Status Logic for Field Staff and Managers
    bool needsOdometer = false;
    bool tripInProgress = false;
    if (isCheckedIn && (_isExecutive || _isManager)) {
      needsOdometer = _activeTrip != null && _activeTrip!['start_odometer_reading'] == null;
      tripInProgress = _activeTrip != null && 
                       _activeTrip!['start_odometer_reading'] != null && 
                       _activeTrip!['end_odometer_reading'] == null;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Attendance')),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Info Card
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.secondary.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Column(
                            children: [
                              _infoRow(
                                Icons.calendar_today_rounded,
                                'Date',
                                DateFormat(
                                  'EEEE, MMM d',
                                ).format(DateTime.now()),
                              ),
                              const Divider(height: 32),
                              _infoRow(
                                Icons.location_on_rounded,
                                'Location',
                                _currentAddress,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Photo Area
                        GestureDetector(
                          onTap: (isCompleted || needsOdometer || tripInProgress) ? null : _takePhoto,
                          child: Container(
                            width: double.infinity,
                            height: 250,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: AppColors.secondary,
                                width: 2,
                              ),
                            ),
                            child:
                                _image != null
                                    ? ClipRRect(
                                      borderRadius: BorderRadius.circular(22),
                                      child: kIsWeb
                                          ? Image.network(
                                              _image!.path,
                                              fit: BoxFit.cover,
                                            )
                                          : Image.file(
                                              File(_image!.path),
                                              fit: BoxFit.cover,
                                            ),
                                    )
                                    : isCompleted
                                    ? const Center(
                                      child: Text('Shift Completed for Today'),
                                    )
                                    : (needsOdometer || tripInProgress)
                                    ? Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.speed_rounded,
                                            size: 64,
                                            color: AppColors.primary.withOpacity(0.5),
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            needsOdometer ? 'Start Trip to Proceed' : 'Trip In Progress',
                                            style: const TextStyle(color: AppColors.textGray),
                                          ),
                                        ],
                                      ),
                                    )
                                    : Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.camera_alt_rounded,
                                          size: 64,
                                          color: AppColors.primary.withOpacity(
                                            0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        const Text(
                                          'Tap to take photo',
                                          style: TextStyle(
                                            color: AppColors.textGray,
                                          ),
                                        ),
                                      ],
                                    ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        if ((isCheckIn || needsOdometer) && (_isExecutive || _isTelecaller || _isManager))
                          _buildOdometerSection(),
                        
                        if (tripInProgress && (_isExecutive || _isTelecaller || _isManager))
                          _buildEndTripSection(),

                        const SizedBox(height: 40),

                        if (isCompleted)
                          const Text(
                            'You have already logged your attendance for today.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        else
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isSubmitting 
                                ? null 
                                : _handleSubmit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    isCheckIn
                                        ? AppColors.primary
                                        : needsOdometer 
                                            ? Colors.blue
                                            : tripInProgress
                                              ? Colors.redAccent
                                              : Colors.orange,
                              ),
                              child:
                                  _isSubmitting
                                      ? Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Text(
                                              isCheckedIn ? 'Checking Out...' : 'Syncing & Checking In...',
                                              style: const TextStyle(color: Colors.white),
                                            ),
                                          ],
                                        )
                                      : Text(
                                        isCheckIn
                                          ? ((_isExecutive || _isTelecaller || _isManager) ? 'Check In & Start Trip' : 'Check In')
                                          : needsOdometer 
                                            ? 'Start Trip' 
                                            : tripInProgress 
                                              ? 'End Trip' 
                                              : 'Check Out',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                            ),
                          ),

                        const SizedBox(height: 24),

                        // Today Stats
                        if (_todayAttendance != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Activity Today',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _activityItem(
                                  'Check In',
                                  DateFormat('hh:mm a').format(
                                    DateTime.parse(
                                      _todayAttendance!['check_in_time'],
                                    ),
                                  ),
                                  true,
                                ),
                                if (_todayAttendance!['check_out_time'] != null)
                                  _activityItem(
                                    'Check Out',
                                    DateFormat('hh:mm a').format(
                                      DateTime.parse(
                                        _todayAttendance!['check_out_time'],
                                      ),
                                    ),
                                    false,
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

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: AppColors.textGray, fontSize: 12),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _activityItem(String label, String time, bool isGreen) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isGreen ? Colors.green : Colors.orange,
            ),
          ),
          const SizedBox(width: 16),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(
            time,
            style: const TextStyle(
              color: AppColors.textGray,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  Widget _choiceChip(String label, bool selected, VoidCallback onSelected) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: AppColors.primary.withOpacity(0.2),
      labelStyle: TextStyle(
        color: selected ? AppColors.primary : Colors.black,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildOdometerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 48),
        const Text(
          'Start Trip Details',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Vehicle Type',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _choiceChip(
              'Two Wheeler',
              _selectedVehicle == 'TWO_WHEELER',
              () => setState(() => _selectedVehicle = 'TWO_WHEELER'),
            ),
            const SizedBox(width: 12),
            _choiceChip(
              'Four Wheeler',
              _selectedVehicle == 'FOUR_WHEELER',
              () => setState(() => _selectedVehicle = 'FOUR_WHEELER'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          'Vehicle Ownership',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _choiceChip(
              'Own Vehicle',
              _selectedOwnership == 'OWN',
              () => setState(() => _selectedOwnership = 'OWN'),
            ),
            const SizedBox(width: 12),
            _choiceChip(
              'Company Vehicle',
              _selectedOwnership == 'COMPANY',
              () => setState(() => _selectedOwnership = 'COMPANY'),
            ),
          ],
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _odoController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Current Odometer Reading',
            prefixIcon: const Icon(Icons.speed_rounded),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Odometer Photo',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _takeOdoPhoto,
          child: Container(
            width: double.infinity,
            height: 150,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.secondary),
            ),
            child: _odoImage != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: kIsWeb
                        ? Image.network(
                            _odoImage!.path,
                            fit: BoxFit.cover,
                          )
                        : Image.file(
                            File(_odoImage!.path),
                            fit: BoxFit.cover,
                          ),
                  )
                : const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo_rounded, color: AppColors.textGray),
                        SizedBox(height: 8),
                        Text('Take Odometer Photo', style: TextStyle(color: AppColors.textGray)),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildEndTripSection() {
    final startOdo = double.tryParse(_activeTrip!['start_odometer_reading']?.toString() ?? '0') ?? 0.0;
    final endOdo = double.tryParse(_odoController.text) ?? 0.0;
    final distance = endOdo - startOdo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 48),
        const Text(
          'End Trip Details',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.redAccent,
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _odoController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'End Odometer Reading',
            prefixIcon: const Icon(Icons.speed_rounded),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (_odoController.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            distance >= 0 
              ? 'Total Distance: ${distance.toStringAsFixed(1)} KM'
              : 'Reading must be >= $startOdo',
            style: TextStyle(
              color: distance >= 0 ? AppColors.primary : Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
        const SizedBox(height: 24),
        const Text(
          'End Odometer Photo',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _takeOdoPhoto,
          child: Container(
            width: double.infinity,
            height: 150,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.secondary),
            ),
            child: _odoImage != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: kIsWeb
                        ? Image.network(
                            _odoImage!.path,
                            fit: BoxFit.cover,
                          )
                        : Image.file(
                            File(_odoImage!.path),
                            fit: BoxFit.cover,
                          ),
                  )
                : const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo_rounded, color: AppColors.textGray),
                        SizedBox(height: 8),
                        Text('Take Odometer Photo', style: TextStyle(color: AppColors.textGray)),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
