import 'package:flutter/material.dart';
import 'package:nature_biotic/core/theme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:nature_biotic/services/supabase_service.dart';

class ExpenseDetailScreen extends StatefulWidget {
  final Map<String, dynamic> expense;

  const ExpenseDetailScreen({super.key, required this.expense});

  @override
  State<ExpenseDetailScreen> createState() => _ExpenseDetailScreenState();
}

class _ExpenseDetailScreenState extends State<ExpenseDetailScreen> {
  late Map<String, dynamic> _data;
  bool _isLoading = true;
  String _userRole = 'manager';

  @override
  void initState() {
    super.initState();
    _data = widget.expense;
    _fetchFullDetails();
  }

  Future<void> _fetchFullDetails() async {
    try {
      final results = await Future.wait([
        SupabaseService.getExpenseById(widget.expense['id']),
        SupabaseService.getProfile(),
      ]);
      if (mounted) {
        setState(() {
          _data = results[0] as Map<String, dynamic>;
          final profile = results[1] as Map<String, dynamic>?;
          _userRole = profile?['role'] ?? 'manager';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show a small loader at top or full screen if data is minimal
    final items = List<Map<String, dynamic>>.from(_data['expense_items'] ?? []);
    final allotted = double.tryParse(_data['amount_allotted'].toString()) ?? 0.0;
    final spent = items.fold(0.0, (sum, item) => sum + (double.tryParse(item['amount'].toString()) ?? 0.0));
    final balance = allotted - spent;
    
    final name = _data['profiles']?['full_name'] ?? 'Executive';
    String date = 'N/A';
    if (_data['created_at'] != null) {
      try {
        date = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.parse(_data['created_at']));
      } catch (_) {}
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Expense Details'),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
            )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(name, date, _data['status']),
                const SizedBox(height: 24),
                _buildFinancialSummary(allotted, spent, balance, _data['return_amount'], _data['return_status']),
                const SizedBox(height: 24),
                _buildTripInfo(),
                const SizedBox(height: 24),
                Text('Expense Logs', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (items.isEmpty && !_isLoading)
                  const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No individual expenses logged.')))
                else if (items.isEmpty && _isLoading)
                  const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
                else
                  ...items.map((item) => _buildExpenseItem(item)),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: (_data['return_status'] == 'PENDING' && _userRole != 'admin') ? _buildApprovalActions() : null,
    );
  }

  Widget _buildApprovalActions() {
    final double returnAmount = (_data['return_amount'] is num) ? (_data['return_amount'] as num).toDouble() : (double.tryParse(_data['return_amount']?.toString() ?? '0') ?? 0.0);
    final isClaim = returnAmount < 0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -4))],
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: _isLoading ? null : () => _approveReturn(isClaim),
              style: ElevatedButton.styleFrom(
                backgroundColor: isClaim ? Colors.orange : Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(isClaim ? 'Approve Claim' : 'Accept Return & Close Trip', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _approveReturn(bool isClaim) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isClaim ? 'Approve Claim' : 'Confirm Return'),
        content: Text(isClaim 
          ? 'Are you sure you want to approve this claim? This will settle the amount spent by the executive from their pocket.'
          : 'Are you sure you want to accept this returned amount and close the trip?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true), 
            style: ElevatedButton.styleFrom(backgroundColor: isClaim ? Colors.orange : Colors.green),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        await SupabaseService.approveReturn(_data['id']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Return approved successfully')),
          );
          Navigator.pop(context, true); // Go back with success flag
        }
      } catch (e) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Widget _buildHeader(String name, String date, String status) {
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: AppColors.primary.withOpacity(0.1),
          child: Text(name[0], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold)),
              Text(date, style: TextStyle(color: AppColors.textGray, fontSize: 13)),
            ],
          ),
        ),
        _statusChip(status, _data['return_status']),
      ],
    );
  }

  Widget _buildFinancialSummary(double allotted, double spent, double balance, dynamic returned, dynamic returnStatus) {
    final double returnAmount = (returned is num) ? returned.toDouble() : (double.tryParse(returned?.toString() ?? '0') ?? 0.0);
    final isClaim = returnAmount < 0;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _summaryItem('Allotted', '₹$allotted', AppColors.primary),
                _summaryItem('Spent', '₹${spent.toStringAsFixed(2)}', Colors.orange),
                _summaryItem('Balance', '₹${balance.toStringAsFixed(2)}', balance < 0 ? Colors.orange.shade800 : Colors.blue),
              ],
            ),
            if (returnStatus != 'NONE' && returnStatus != null) ...[
              const Divider(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   Text(isClaim ? 'Claim Amount:' : 'Returned Amount:', style: const TextStyle(fontWeight: FontWeight.w500)),
                   Text('₹${returnAmount.abs()}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isClaim ? Colors.orange.shade700 : Colors.green)),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   Text(isClaim ? 'Claim Status:' : 'Return Status:', style: const TextStyle(fontSize: 12, color: AppColors.textGray)),
                   Text(isClaim && returnStatus == 'PENDING' ? 'AWAITING APPROVAL' : returnStatus.toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTripInfo() {
    final startOdo = double.tryParse(_data['start_odometer_reading']?.toString() ?? '0') ?? 0.0;
    final endOdo = double.tryParse(_data['end_odometer_reading']?.toString() ?? '0') ?? 0.0;
    final distance = (endOdo > 0 && endOdo >= startOdo) ? (endOdo - startOdo) : 0.0;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Trip Details', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                if (distance > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Total: ${distance.toStringAsFixed(1)} KM',
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _infoRow('Vehicle', '${_data['vehicle_type'] ?? 'N/A'} (${_data['vehicle_ownership'] ?? 'N/A'})'),
            const Divider(),
            _infoRow('Start Odometer', '${_data['start_odometer_reading'] ?? 'N/A'}'),
            if (_data['start_odometer_photo'] != null)
              _buildImagePreview('Start Odometer photo', _data['start_odometer_photo']),
            const Divider(),
            _infoRow('End Odometer', '${_data['end_odometer_reading'] ?? 'N/A'}'),
            if (_data['end_odometer_photo'] != null)
              _buildImagePreview('End Odometer photo', _data['end_odometer_photo']),
            if (distance > 0) ...[
              const Divider(),
              _infoRow('Total Distance', '${distance.toStringAsFixed(1)} KM'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExpenseItem(Map<String, dynamic> item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _categoryIcon(item['category']),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item['category'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (item['courier_name'] != null && item['courier_name'].toString().isNotEmpty)
                        Text('Courier: ${item['courier_name']}', style: const TextStyle(fontSize: 12, color: AppColors.textGray)),
                    ],
                  ),
                ),
                Text('₹${item['amount']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            if (item['notes'] != null && item['notes'].toString().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(item['notes'], style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
            ],
            if (item['bill_photo'] != null) ...[
              const SizedBox(height: 12),
              _buildImagePreview('Bill photo', item['bill_photo']),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview(String label, String url) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      constraints: const BoxConstraints(maxHeight: 400),
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        color: Colors.black.withOpacity(0.02),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          url, 
          fit: BoxFit.contain, 
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return const Center(child: CircularProgressIndicator());
          },
          errorBuilder: (_, __, ___) => const Center(child: Text('Image unavailable')),
        ),
      ),
    );
  }

  Widget _summaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textGray)),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textGray)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _statusChip(String? status, String? returnStatus) {
    String label = status ?? 'UNKNOWN';
    Color color = Colors.grey;
    final double returnAmount = (_data['return_amount'] is num) ? (_data['return_amount'] as num).toDouble() : (double.tryParse(_data['return_amount']?.toString() ?? '0') ?? 0.0);

    if (status == 'ACTIVE') { label = 'Active'; color = Colors.green; }
    else if (status == 'CLOSED') { label = 'Closed'; color = Colors.blue; }
    
    if (returnStatus == 'PENDING') { 
      if (returnAmount < 0) {
        label = 'Claim Pending';
        color = Colors.deepOrange;
      } else {
        label = 'Return Pending'; 
        color = Colors.orange; 
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _categoryIcon(String category) {
    IconData icon;
    Color color;
    switch (category) {
      case 'FOOD': icon = Icons.restaurant_rounded; color = Colors.orange; break;
      case 'FUEL': icon = Icons.local_gas_station_rounded; color = Colors.blue; break;
      case 'COURIER': icon = Icons.local_shipping_rounded; color = Colors.purple; break;
      case 'DRIVER': icon = Icons.person_rounded; color = Colors.teal; break;
      default: icon = Icons.more_horiz_rounded; color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
      child: Icon(icon, color: color, size: 20),
    );
  }
}
