import 'package:flutter/material.dart';
import 'package:nature_biotic/core/theme.dart';
import 'package:nature_biotic/services/supabase_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

class ExecutiveExpenseDashboard extends StatefulWidget {
  const ExecutiveExpenseDashboard({super.key});

  @override
  State<ExecutiveExpenseDashboard> createState() =>
      _ExecutiveExpenseDashboardState();
}

class _ExecutiveExpenseDashboardState extends State<ExecutiveExpenseDashboard> {
  Map<String, dynamic>? _activeExpense;
  bool _isLoading = true;
  bool _isTelecaller = false;
  bool _isManager = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadActiveExpense();
  }

  Future<void> _loadActiveExpense() async {
    setState(() => _isLoading = true);
    try {
      final profile = await SupabaseService.getProfile();
      final userId = SupabaseService.client.auth.currentUser?.id;
      if (userId != null) {
        final expense = await SupabaseService.getActiveExpenseForExecutive(
          userId,
        );
        setState(() {
          _isTelecaller = profile?['role'] == 'telecaller';
          _isManager = profile?['role'] == 'manager';
          _activeExpense = expense;
        });
      }
    } catch (e) {
      debugPrint('Error loading active expense: $e');
    }
    setState(() => _isLoading = false);
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_activeExpense == null) {
      return _buildNoActiveTripPlaceholder();
    }

    final allotmentStatus = _activeExpense!['allotment_status'];
    if (allotmentStatus == 'PENDING') {
      return _buildPendingReceipt();
    }

    final endOdometer = _activeExpense!['end_odometer_reading'];
    if (endOdometer == null) {
      return _buildActiveTrip();
    }

    final returnStatus = _activeExpense!['return_status'];
    if (returnStatus == 'PENDING') {
      return _buildWaitingForManagerApproval();
    }

    return _buildSubmitReturn();
  }

  Widget _buildNoActiveTripPlaceholder() {
    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              (_isTelecaller || _isManager) ? Icons.account_balance_wallet_rounded : Icons.directions_car_rounded,
              size: 80,
              color: AppColors.primary.withOpacity(0.2),
            ),
            const SizedBox(height: 24),
            Text(
              (_isTelecaller || _isManager) ? 'No Active Expense' : 'No Active Trip',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              (_isTelecaller || _isManager) 
                  ? 'Please check in or start a daily expense.'
                  : 'Please start a trip from the Dashboard.',
              style: const TextStyle(color: AppColors.textGray),
            ),
            const SizedBox(height: 32),
            if (_isTelecaller || _isManager)
              ElevatedButton.icon(
                onPressed: () async {
                  setState(() => _isLoading = true);
                  final tripId = await SupabaseService.startExecutiveTrip();
                  if (tripId != null) {
                    await SupabaseService.updateTripStart(
                      expenseId: tripId,
                      vehicleType: 'None',
                      ownership: 'None',
                      odometer: 0,
                    );
                  }
                  await _loadActiveExpense();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Start Daily Expense'),
              )
            else
              TextButton.icon(
                onPressed: _loadActiveExpense,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh Status'),
              ),
            
            if (_isTelecaller || _isManager) const SizedBox(height: 16),
            if (_isTelecaller || _isManager)
              TextButton.icon(
                onPressed: _loadActiveExpense,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh Status'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingReceipt() {
    final amount = _activeExpense!['amount_allotted'];
    return Scaffold(
      appBar: AppBar(title: const Text('New Allotment')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(
              Icons.account_balance_wallet_rounded,
              size: 64,
              color: AppColors.primary,
            ),
            const SizedBox(height: 24),
            Text(
              '₹$amount Allotted',
              style: GoogleFonts.outfit(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Did you receive this amount from the manager?',
              style: TextStyle(color: AppColors.textGray),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  await SupabaseService.receiveExpenseFunds(
                    _activeExpense!['id'],
                  );
                  _loadActiveExpense();
                },
                child: const Text(
                  'Yes, Received',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTrip() {
    final allotted =
        double.tryParse(_activeExpense!['amount_allotted'].toString()) ?? 0.0;
    final items = List<Map<String, dynamic>>.from(
      _activeExpense!['expense_items'] ?? [],
    );
    final spent = items.fold(
      0.0,
      (sum, item) => sum + (double.tryParse(item['amount'].toString()) ?? 0.0),
    );
    final balance = allotted - spent;

    return Scaffold(
      appBar: AppBar(title: const Text('Current Trip')),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
            ),
            child: Column(
              children: [
                const Text(
                  'Remaining Balance',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  '₹${balance.toStringAsFixed(2)}',
                  style: GoogleFonts.outfit(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _summaryBlock('Allotted', '₹$allotted'),
                    _summaryBlock('Spent', '₹$spent'),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child:
                items.isEmpty
                    ? Center(
                      child: Text(
                        'No expenses logged yet',
                        style: TextStyle(color: AppColors.textGray),
                      ),
                    )
                    : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder:
                                  (context) => AlertDialog(
                                    title: Text(item['category']),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Amount: ₹${item['amount']}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Log Time: ${DateFormat('hh:mm a, dd MMM').format(DateTime.parse(item['created_at']))}',
                                        ),
                                        if (item['notes'] != null &&
                                            item['notes']
                                                .toString()
                                                .isNotEmpty) ...[
                                          const SizedBox(height: 12),
                                          Text(
                                            'Notes: ${item['notes']}',
                                            style: const TextStyle(
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ],
                                        if (item['bill_photo'] != null) ...[
                                          const SizedBox(height: 16),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            child: Image.network(
                                              item['bill_photo'],
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Close'),
                                      ),
                                    ],
                                  ),
                            );
                          },
                          leading: _categoryIcon(item['category']),
                          title: Text(item['category']),
                          subtitle: Text(
                            DateFormat(
                              'hh:mm a, dd MMM',
                            ).format(DateTime.parse(item['created_at'])),
                          ),
                          trailing: Text(
                            '₹${item['amount']}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        );
                      },
                    ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: _showAddExpenseDialog,
                    icon: const Icon(
                      Icons.add_circle_rounded,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Add Expense',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAddExpenseDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (context) => _AddExpenseDialogContent(
            expenseId: _activeExpense!['id'],
            onAdded: _loadActiveExpense,
            onCapture: () => _captureAndUpload('expense-documents'),
          ),
    );
  }

  Widget _buildSubmitReturn() {
    final allotted =
        double.tryParse(_activeExpense!['amount_allotted'].toString()) ?? 0.0;
    final items = List<Map<String, dynamic>>.from(
      _activeExpense!['expense_items'] ?? [],
    );
    final spent = items.fold(
      0.0,
      (sum, item) => sum + (double.tryParse(item['amount'].toString()) ?? 0.0),
    );
    final balance = allotted - spent;
    final isClaim = balance < 0;
    final returnController = TextEditingController(
      text: isClaim ? balance.abs().toString() : balance.toString(),
    );

    return Scaffold(
      appBar: AppBar(title: Text(isClaim ? 'Submit Claim' : 'Return Balance')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              isClaim
                  ? Icons.add_moderator_rounded
                  : Icons.assignment_return_rounded,
              size: 64,
              color: isClaim ? Colors.orange : AppColors.primary,
            ),
            const SizedBox(height: 24),
            Text(
              isClaim ? 'Expense Claim' : 'Trip Finished',
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_activeExpense!['start_odometer_reading'] != null &&
                _activeExpense!['end_odometer_reading'] != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Total Distance: ${((double.tryParse(_activeExpense!['end_odometer_reading'].toString()) ?? 0) - (double.tryParse(_activeExpense!['start_odometer_reading'].toString()) ?? 0)).toStringAsFixed(1)} KM',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              isClaim
                  ? 'You have spent more than allotted. Submit a claim for the difference.'
                  : 'Enter the amount you are returning to the manager.',
              style: const TextStyle(color: AppColors.textGray),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            TextField(
              controller: returnController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: isClaim ? 'Claim Amount' : 'Return Amount',
                prefixText: '₹ ',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isClaim ? Colors.orange : AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () async {
                  final amount = double.tryParse(returnController.text) ?? 0.0;
                  await SupabaseService.submitReturn(
                    _activeExpense!['id'],
                    isClaim ? -amount : amount,
                  );
                  _loadActiveExpense();
                },
                child: Text(
                  isClaim ? 'Submit Claim' : 'Submit Return',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingForManagerApproval() {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.hourglass_empty_rounded,
              size: 80,
              color: Colors.orange,
            ),
            const SizedBox(height: 24),
            Text(
              'Awaiting Manager Approval',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'You have submitted the return amount.',
              style: TextStyle(color: AppColors.textGray),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _loadActiveExpense,
              child: const Text('Check Status'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryBlock(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ],
    );
  }

  Widget _categoryIcon(String category) {
    IconData icon;
    Color color;
    switch (category) {
      case 'FOOD':
        icon = Icons.restaurant_rounded;
        color = Colors.orange;
        break;
      case 'FUEL':
        icon = Icons.local_gas_station_rounded;
        color = Colors.blue;
        break;
      case 'COURIER':
        icon = Icons.local_shipping_rounded;
        color = Colors.purple;
        break;
      case 'DRIVER':
        icon = Icons.person_rounded;
        color = Colors.teal;
        break;
      default:
        icon = Icons.more_horiz_rounded;
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

class _AddExpenseDialogContent extends StatefulWidget {
  final String expenseId;
  final VoidCallback onAdded;
  final Future<String?> Function() onCapture;

  const _AddExpenseDialogContent({
    required this.expenseId,
    required this.onAdded,
    required this.onCapture,
  });

  @override
  State<_AddExpenseDialogContent> createState() =>
      _AddExpenseDialogContentState();
}

class _AddExpenseDialogContentState extends State<_AddExpenseDialogContent> {
  String? _category;
  final _amountController = TextEditingController();
  final _courierController = TextEditingController();
  final _notesController = TextEditingController();
  String? _billPhoto;
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final bool canLog =
        _category != null &&
        _amountController.text.isNotEmpty &&
        !_isSubmitting;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add Expense',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items:
                  ['FOOD', 'FUEL', 'COURIER', 'DRIVER', 'OTHERS']
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
              onChanged: (v) => setState(() => _category = v),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_category == 'COURIER') ...[
              const SizedBox(height: 16),
              TextField(
                controller: _courierController,
                decoration: const InputDecoration(
                  labelText: 'Courier Name',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (Optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (['FUEL', 'COURIER'].contains(_category))
              _buildPhotoSelector('Take Bill Photo', _billPhoto, () async {
                final url = await widget.onCapture();
                if (url != null) setState(() => _billPhoto = url);
              }),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed:
                    canLog
                        ? () async {
                          setState(() => _isSubmitting = true);
                          try {
                            await SupabaseService.addExpenseItem(
                              expenseId: widget.expenseId,
                              category: _category!,
                              amount: double.parse(_amountController.text),
                              courierName: _courierController.text,
                              photoUrl: _billPhoto,
                              notes: _notesController.text,
                            );
                            Navigator.pop(context);
                            widget.onAdded();
                          } catch (e) {
                            setState(() => _isSubmitting = false);
                          }
                        }
                        : null,
                child:
                    _isSubmitting
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                          'Log Expense',
                          style: TextStyle(color: Colors.white),
                        ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoSelector(
    String label,
    String? photoUrl,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.textGray.withOpacity(0.2)),
          borderRadius: BorderRadius.circular(12),
          color: Colors.black.withOpacity(0.02),
        ),
        constraints: const BoxConstraints(maxHeight: 200),
        child:
            photoUrl != null
                ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(photoUrl, fit: BoxFit.contain),
                )
                : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.camera_alt_rounded,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textGray,
                      ),
                    ),
                  ],
                ),
      ),
    );
  }
}
