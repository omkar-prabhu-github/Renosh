import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/maps_service.dart';

class FoodTrackScreen extends StatefulWidget {
  const FoodTrackScreen({super.key});

  @override
  State<FoodTrackScreen> createState() => _FoodTrackScreenState();
}

class _FoodTrackScreenState extends State<FoodTrackScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  final _foodItemController = TextEditingController();
  final _quantityMadeController = TextEditingController();
  bool _isLoading = false;
  bool _isAdding = false; // For debouncing
  final _currentDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _foodItemController.dispose();
    _quantityMadeController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.inter(
            color: const Color(0xFFF9F7F3),
            fontSize: 14,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: const Color(0xFFFF4A4A),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.inter(
            color: const Color(0xFF1A3C34),
            fontSize: 14,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: const Color(0xFF39FF14),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

  Future<void> _addFoodTracking() async {
    if (_isAdding) return; // Debounce
    setState(() => _isAdding = true);

    if (_foodItemController.text.trim().isEmpty ||
        _quantityMadeController.text.isEmpty) {
      _showErrorSnackBar('Please fill in all fields.');
      setState(() => _isAdding = false);
      return;
    }
    final made = int.tryParse(_quantityMadeController.text) ?? 0;

    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showErrorSnackBar('User not authenticated.');
        setState(() => _isLoading = false);
        setState(() => _isAdding = false);
        return;
      }
      await FirebaseFirestore.instance.collection('food_tracking').add({
        'establishmentId': user.uid,
        'day': DateFormat('EEEE').format(DateTime.now()),
        'date': _currentDate,
        'item_name': _foodItemController.text.trim(),
        'quantity_made': made,
        'quantity_surplus': made, // Initially, surplus is what was made
        'quantity_sold': 0, // Initially, 0 sold
        'timestamp': Timestamp.now(),
        'status': 'available',
      });
      _foodItemController.clear();
      _quantityMadeController.clear();
      _showSuccessSnackBar('Food item added to inventory successfully.');
    } catch (e) {
      _showErrorSnackBar('Failed to add food tracking: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        setState(() => _isAdding = false);
      }
    }
  }

  void _showPostSurplusDialog(Map<String, dynamic> itemData, String docId) {
    final pincodeController = TextEditingController();
    final pickupTimeController = TextEditingController();
    final quantityController = TextEditingController(
      text: itemData['quantity_surplus'].toString(),
    );
    bool isPosting = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF2D2D2D),
              title: Text(
                'Post Surplus Food',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Item: ${itemData['item_name']}',
                      style: GoogleFonts.inter(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: quantityController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration(
                        'Quantity to Donate',
                        Icons.balance,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pincodeController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration('Pincode', Icons.pin_drop),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pickupTimeController,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration(
                        'Pickup Time (e.g., 6 PM)',
                        Icons.access_time,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: isPosting
                      ? null
                      : () async {
                          final pincode = pincodeController.text.trim();
                          final pickupTime = pickupTimeController.text.trim();
                          final quantity =
                              int.tryParse(quantityController.text) ?? 0;

                          if (pincode.isEmpty ||
                              pickupTime.isEmpty ||
                              quantity <= 0) {
                            _showErrorSnackBar(
                              'Please fill all fields correctly.',
                            );
                            return;
                          }

                          setDialogState(() => isPosting = true);

                          try {
                            // 1. Geocode pincode
                            final latLng =
                                await MapsService.getLatLngFromAddress(pincode);
                            if (latLng == null) {
                              _showErrorSnackBar(
                                'Invalid pincode or geocoding failed.',
                              );
                              setDialogState(() => isPosting = false);
                              return;
                            }

                            // 2. Post to donations collection
                            final user = FirebaseAuth.instance.currentUser;
                            await FirebaseFirestore.instance
                                .collection('donations')
                                .add({
                                  'establishmentId': user!.uid,
                                  'item_name': itemData['item_name'],
                                  'quantity': quantity,
                                  'pickupTime': pickupTime,
                                  'pincode': pincode,
                                  'location': GeoPoint(
                                    latLng['lat']!,
                                    latLng['lng']!,
                                  ),
                                  'status': 'available',
                                  'claimStatus': 'none',
                                  'createdAt': FieldValue.serverTimestamp(),
                                });

                            // 3. Update inventory item to reflect it's been donated (optional logic)
                            // For now, we just post it.

                            Navigator.pop(context);
                            _showSuccessSnackBar('Food posted for donation!');
                          } catch (e) {
                            _showErrorSnackBar('Failed to post donation: $e');
                          } finally {
                            setDialogState(() => isPosting = false);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF39FF14),
                    foregroundColor: const Color(0xFF1A3C34),
                  ),
                  child: isPosting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Post'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: const Color(0xFF1A3C34),
      appBar: AppBar(
        title: Text(
          'Inventory Entry',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.5,
                colors: [
                  const Color(0xFF1A3C34).withOpacity(0.95),
                  const Color(0xFF2D2D2D).withOpacity(0.85),
                ],
              ),
            ),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFoodTrackingSection(),
                  const SizedBox(height: 32),
                  _buildTrackedItemsList(user),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFoodTrackingSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add New Food Item',
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFF9F7F3),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _foodItemController,
            style: GoogleFonts.inter(
              fontSize: 16,
              color: const Color(0xFFF9F7F3),
            ),
            decoration: _inputDecoration('Food Item Name', Icons.food_bank),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _quantityMadeController,
            keyboardType: TextInputType.number,
            style: GoogleFonts.inter(
              fontSize: 16,
              color: const Color(0xFFF9F7F3),
            ),
            decoration: _inputDecoration('Quantity Produced', Icons.factory),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isLoading || _isAdding
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      _addFoodTracking();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF39FF14),
                foregroundColor: const Color(0xFF1A3C34),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Color(0xFF1A3C34))
                  : Text(
                      'Add to Inventory',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.inter(
        fontSize: 14,
        color: const Color(0xFFB0B0B0),
      ),
      prefixIcon: Icon(icon, color: const Color(0xFF39FF14)),
      filled: true,
      fillColor: const Color(0xFF3A3A3A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF39FF14), width: 2),
      ),
    );
  }

  Widget _buildTrackedItemsList(User? user) {
    return StreamBuilder<QuerySnapshot>(
      stream: user == null
          ? null
          : FirebaseFirestore.instance
                .collection('food_tracking')
                .where('establishmentId', isEqualTo: user.uid)
                .where('date', isEqualTo: _currentDate)
                .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        final docs = snapshot.data!.docs;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Today\'s Inventory',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFF9F7F3),
              ),
            ),
            const SizedBox(height: 16),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final data = docs[index].data() as Map<String, dynamic>;
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D2D2D),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data['item_name'],
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Produced: ${data['quantity_made']} | Sold: ${data['quantity_sold']} | Left: ${data['quantity_surplus']}',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: Colors.grey[400],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (data['quantity_surplus'] > 0)
                        IconButton(
                          icon: const Icon(
                            Icons.volunteer_activism,
                            color: Color(0xFF39FF14),
                          ),
                          onPressed: () =>
                              _showPostSurplusDialog(data, docs[index].id),
                          tooltip: 'Post as Donation',
                        )
                      else
                        const Icon(Icons.outbox, color: Colors.redAccent),
                    ],
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
