import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'firebase_options.dart';
import 'services/maps_service.dart';
import 'login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const RenoshInventoryApp());
}

class RenoshInventoryApp extends StatelessWidget {
  const RenoshInventoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Renosh Inventory Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        primaryColor: const Color(0xFF39FF14),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF39FF14),
          brightness: Brightness.dark,
          surface: const Color(0xFF1E293B),
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              backgroundColor: Color(0xFF0F172A),
              body: Center(
                child: CircularProgressIndicator(color: Color(0xFF39FF14)),
              ),
            );
          }
          if (snapshot.hasData && snapshot.data != null) {
            return InventoryDashboardWrapper(user: snapshot.data!);
          }
          return const LoginScreen();
        },
      ),
    );
  }
}

class InventoryDashboardWrapper extends StatelessWidget {
  final User user;
  const InventoryDashboardWrapper({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF0F172A),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF39FF14)),
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
          return Scaffold(
            backgroundColor: const Color(0xFF0F172A),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'User profile not found or error occurred.',
                    style: TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    child: const Text(
                      'Log out',
                      style: TextStyle(color: Color(0xFF0F172A)),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF39FF14),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        final role = data?['role'] as String?;

        if (role != 'Food Establishment') {
          return Scaffold(
            backgroundColor: const Color(0xFF0F172A),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Access denied. Only Food Establishments can access this dashboard.',
                    style: TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    child: const Text(
                      'Log out',
                      style: TextStyle(color: Color(0xFF0F172A)),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF39FF14),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return InventoryDashboard(uid: user.uid);
      },
    );
  }
}

class InventoryDashboard extends StatefulWidget {
  final String uid;
  const InventoryDashboard({super.key, required this.uid});

  @override
  State<InventoryDashboard> createState() => _InventoryDashboardState();
}

class _InventoryDashboardState extends State<InventoryDashboard> {
  final _foodItemController = TextEditingController();
  final _quantityController = TextEditingController();
  final _soldController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  String get _currentDate => DateFormat('yyyy-MM-dd').format(_selectedDate);
  bool _isProcessing = false;

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF39FF14),
              onPrimary: Color(0xFF0F172A),
              surface: Color(0xFF1E293B),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _addItem() async {
    if (_foodItemController.text.isEmpty || _quantityController.text.isEmpty)
      return;

    setState(() => _isProcessing = true);
    try {
      final made = int.tryParse(_quantityController.text) ?? 0;
      final sold = int.tryParse(_soldController.text) ?? 0;
      final surplus = made - sold;

      await FirebaseFirestore.instance.collection('food_tracking').add({
        'establishmentId': widget.uid,
        'item_name': _foodItemController.text.trim(),
        'quantity_made': made,
        'quantity_surplus': surplus > 0 ? surplus : 0,
        'quantity_sold': sold,
        'date': _currentDate,
        'timestamp': FieldValue.serverTimestamp(),
        'status': surplus > 0 ? 'available' : 'sold_out',
      });
      _foodItemController.clear();
      _quantityController.clear();
      _soldController.clear();
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _clearDatabase() async {
    setState(() => _isProcessing = true);
    try {
      final db = FirebaseFirestore.instance;
      final userId = widget.uid;

      // Clear existing data for this establishment
      final collections = ['food_tracking', 'donations', 'purchases'];
      for (final coll in collections) {
        final snap = await db
            .collection(coll)
            .where('establishmentId', isEqualTo: userId)
            .get();
        for (var doc in snap.docs) {
          await doc.reference.delete();
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All establishment data cleared successfully.'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error during cleanup: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _seedDatabase() async {
    setState(() => _isProcessing = true);
    try {
      final db = FirebaseFirestore.instance;
      final userId = widget.uid;
      final now = DateTime.now();
      final dateFormatter = DateFormat('yyyy-MM-dd');

      // 1. Clear existing data for this establishment to start fresh
      final collections = ['food_tracking', 'donation', 'purchases'];
      for (final coll in collections) {
        final snap = await db
            .collection(coll)
            .where('establishmentId', isEqualTo: userId)
            .get();
        for (var doc in snap.docs) {
          await doc.reference.delete();
        }
      }

      final sampleItems = [
        {'name': 'Butter Chicken', 'baseMade': 40, 'baseSold': 32},
        {'name': 'Paneer Tikka', 'baseMade': 30, 'baseSold': 22},
        {'name': 'Dal Makhani', 'baseMade': 50, 'baseSold': 45},
        {'name': 'Naan', 'baseMade': 100, 'baseSold': 85},
        {'name': 'Gobi Manchurian', 'baseMade': 25, 'baseSold': 18},
      ];

      final random = Random();

      // 2. Generate data for the past 7 days
      for (int i = 6; i >= 0; i--) {
        final date = now.subtract(Duration(days: i));
        final dateStr = dateFormatter.format(date);
        final timestamp = Timestamp.fromDate(date);

        for (var item in sampleItems) {
          // Add some random variation (-5 to +10)
          final variance = random.nextInt(15) - 5;
          final made = (item['baseMade'] as int) + variance;
          final sold = (item['baseSold'] as int) + (variance ~/ 2);
          final surplus = made - sold;

          // Add to food_tracking
          final docRef = await db.collection('food_tracking').add({
            'establishmentId': userId,
            'item_name': item['name'],
            'quantity_made': made,
            'quantity_sold': sold,
            'quantity_surplus': surplus > 0 ? surplus : 0,
            'date': dateStr,
            'timestamp': timestamp,
            'status': surplus > 0 ? 'available' : 'sold_out',
            'isDonated':
                surplus > 0 && random.nextBool(), // 50% chance some was donated
          });

          // If surplus exists and marked as donated, add a donation record
          if (surplus > 0 && (docRef.id.hashCode % 2 == 0)) {
            final donatedQty = (surplus * 0.8).floor(); // Donate 80% of surplus
            if (donatedQty > 0) {
              await db.collection('donations').add({
                'establishmentId': userId,
                'foodId': docRef.id,
                'item_name': item['name'],
                'quantity': donatedQty,
                'status': 'available',
                'createdAt': timestamp,
                'donorName': 'Premium Establishment',
              });

              // Update tracking to reflect donation
              await docRef.update({'isDonated': true, 'status': 'donated'});
            }
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Successfully seeded 7 days of premium data!'),
            backgroundColor: Color(0xFF39FF14),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error during cleanup: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _deleteItem(String docId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Delete Item'),
        content: const Text(
          'Are you sure you want to remove this item from inventory?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseFirestore.instance
          .collection('food_tracking')
          .doc(docId)
          .delete();
    }
  }

  Future<void> _editItem(
    String docId,
    String currentName,
    int currentMade,
  ) async {
    final nameCtrl = TextEditingController(text: currentName);
    final qtyCtrl = TextEditingController(text: currentMade.toString());

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Edit Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Item Name'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantity Made'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final newMade = int.tryParse(qtyCtrl.text) ?? currentMade;
              // Simple update logic: reset surplus based on new made vs old sold
              // In a real app, this would be more nuanced
              await FirebaseFirestore.instance
                  .collection('food_tracking')
                  .doc(docId)
                  .update({
                    'item_name': nameCtrl.text.trim(),
                    'quantity_made': newMade,
                  });
              if (mounted) Navigator.pop(context);
            },
            child: const Text(
              'Save',
              style: TextStyle(color: Color(0xFF39FF14)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              _buildSummaryCards(),
              const SizedBox(height: 24),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left: Management Table
                    Expanded(flex: 6, child: _buildManagementSection()),
                    const SizedBox(width: 24),
                    // Right: Tabbed panel
                    Expanded(
                      flex: 4,
                      child: Column(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(24),
                              ),
                            ),
                            child: TabBar(
                              tabs: const [
                                Tab(text: 'Live Sales'),
                                Tab(text: 'Requests'),
                                Tab(text: 'Approved'),
                              ],
                              indicatorColor: const Color(0xFF39FF14),
                              labelColor: const Color(0xFF39FF14),
                              unselectedLabelColor: Colors.grey,
                              dividerColor: Colors.transparent,
                            ),
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                _buildRecentSalesFeed(),
                                _buildDonationRequestsFeed(),
                                _buildApprovedDonationsFeed(),
                              ],
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
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('food_tracking')
          .where('establishmentId', isEqualTo: widget.uid)
          .where('date', isEqualTo: _currentDate)
          .snapshots(),
      builder: (context, snapshot) {
        int totalMade = 0;
        int totalSold = 0;
        int totalSurplus = 0;

        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            totalMade += (data['quantity_made'] as num).toInt();
            totalSold += (data['quantity_sold'] as num).toInt();
            totalSurplus += (data['quantity_surplus'] as num).toInt();
          }
        }

        return Row(
          children: [
            _summaryCard(
              'Production',
              totalMade.toString(),
              Icons.add_business_rounded,
              Colors.blueAccent,
            ),
            const SizedBox(width: 24),
            _summaryCard(
              'Total Sold',
              totalSold.toString(),
              Icons.sell_rounded,
              const Color(0xFF39FF14),
            ),
            const SizedBox(width: 24),
            _summaryCard(
              'Current Surplus',
              totalSurplus.toString(),
              Icons.inventory_rounded,
              Colors.orangeAccent,
            ),
          ],
        );
      },
    );
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withAlpha(10)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withAlpha(20),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: Colors.grey[400], fontSize: 14),
                ),
                Text(
                  value,
                  style: GoogleFonts.outfit(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPostSurplusDialog() async {
    final pincodeController = TextEditingController();
    final pickupTimeController = TextEditingController();
    final Map<String, int> selectedItemQuantities = {};
    final Map<String, String> selectedItemNames = {};
    bool isPosting = false;

    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    // Fetch surplus items
    final snapshot = await FirebaseFirestore.instance
        .collection('food_tracking')
        .where('establishmentId', isEqualTo: widget.uid)
        .where('date', isEqualTo: todayStr)
        .get();

    final surplusItems = snapshot.docs.where((doc) {
      final data = doc.data();
      return (data['quantity_surplus'] ?? 0) > 0;
    }).toList();

    if (surplusItems.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No surplus items available to donate today.'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
      return;
    }

    // Pre-select all items with their max surplus
    for (var doc in surplusItems) {
      final data = doc.data();
      selectedItemQuantities[doc.id] = (data['quantity_surplus'] as num)
          .toInt();
      selectedItemNames[doc.id] = data['item_name'] ?? 'Unknown';
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Text(
            'Donate Surplus Food',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...surplusItems.map((doc) {
                    final data = doc.data();
                    final docId = doc.id;
                    final maxSurplus = (data['quantity_surplus'] as num)
                        .toInt();
                    final isSelected = selectedItemQuantities.containsKey(
                      docId,
                    );

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                        border: isSelected
                            ? Border.all(
                                color: const Color(0xFF39FF14),
                                width: 1,
                              )
                            : null,
                      ),
                      child: Row(
                        children: [
                          Checkbox(
                            value: isSelected,
                            activeColor: const Color(0xFF39FF14),
                            onChanged: (val) {
                              setDialogState(() {
                                if (val == true) {
                                  selectedItemQuantities[docId] = maxSurplus;
                                } else {
                                  selectedItemQuantities.remove(docId);
                                }
                              });
                            },
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data['item_name'] ?? 'Unknown',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Max Surplus: $maxSurplus',
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            SizedBox(
                              width: 80,
                              child: TextField(
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  labelText: 'Qty',
                                ),
                                controller:
                                    TextEditingController(
                                        text: selectedItemQuantities[docId]
                                            .toString(),
                                      )
                                      ..selection = TextSelection.fromPosition(
                                        TextPosition(
                                          offset: selectedItemQuantities[docId]
                                              .toString()
                                              .length,
                                        ),
                                      ),
                                onChanged: (val) {
                                  final newQty = int.tryParse(val) ?? 0;
                                  selectedItemQuantities[docId] =
                                      newQty > maxSurplus ? maxSurplus : newQty;
                                },
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  TextField(
                    controller: pincodeController,
                    keyboardType: TextInputType.number,
                    decoration: _inputDecoration('Pincode', Icons.pin_drop),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: pickupTimeController,
                    readOnly: true,
                    decoration: _inputDecoration(
                      'Pickup Time',
                      Icons.access_time,
                    ),
                    onTap: () async {
                      final TimeOfDay? pickedTime = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: const ColorScheme.dark(
                                primary: Color(0xFF39FF14),
                                onPrimary: Color(0xFF0F172A),
                                surface: Color(0xFF1E293B),
                                onSurface: Colors.white,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (pickedTime != null) {
                        setDialogState(() {
                          pickupTimeController.text = pickedTime.format(
                            context,
                          );
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isPosting || selectedItemQuantities.isEmpty
                  ? null
                  : () async {
                      if (pincodeController.text.isEmpty ||
                          pickupTimeController.text.isEmpty) {
                        return;
                      }

                      setDialogState(() => isPosting = true);
                      try {
                        final pincode = pincodeController.text.trim();
                        final latLng = await MapsService.getLatLngFromAddress(
                          pincode,
                        );
                        if (latLng == null) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Invalid pincode.')),
                            );
                          }
                          setDialogState(() => isPosting = false);
                          return;
                        }

                        final batch = FirebaseFirestore.instance.batch();
                        for (var entry in selectedItemQuantities.entries) {
                          final docId = entry.key;
                          final qty = entry.value;
                          if (qty <= 0) continue;

                          // 1. Add to global donations collection
                          final donationRef = FirebaseFirestore.instance
                              .collection('donations')
                              .doc();
                          batch.set(donationRef, {
                            'establishmentId': widget.uid,
                            'foodId': docId,
                            'item_name': selectedItemNames[docId],
                            'quantity': qty,
                            'pincode': pincode,
                            'pickupTime': pickupTimeController.text.trim(),
                            'location': GeoPoint(
                              latLng['lat']!,
                              latLng['lng']!,
                            ),
                            'status': 'available',
                            'claimStatus': 'none',
                            'createdAt': FieldValue.serverTimestamp(),
                          });

                          // 2. Update the original food_tracking record
                          final trackRef = FirebaseFirestore.instance
                              .collection('food_tracking')
                              .doc(docId);
                          batch.update(trackRef, {
                            'isDonated': true,
                            'status': 'donated',
                          });
                        }

                        await batch.commit();

                        if (mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Donations posted successfully!'),
                              backgroundColor: Color(0xFF39FF14),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Error: $e')));
                        }
                      } finally {
                        setDialogState(() => isPosting = false);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF39FF14),
                foregroundColor: const Color(0xFF0F172A),
              ),
              child: isPosting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Post Donations'),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          'Log Out',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        content: const Text(
          'Are you sure you want to log out?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              FirebaseAuth.instance.signOut(); // Trigger logout
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dashboard',
              style: GoogleFonts.outfit(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Real-time monitoring for today.',
              style: TextStyle(color: Colors.grey[400], fontSize: 16),
            ),
          ],
        ),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _showPostSurplusDialog,
              icon: const Icon(Icons.volunteer_activism, size: 20),
              label: const Text('Donate Surplus'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF39FF14),
                foregroundColor: const Color(0xFF0F172A),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(
                Icons.auto_awesome,
                color: Color(0xFF39FF14),
                size: 20,
              ),
              onPressed: _isProcessing ? null : _seedDatabase,
              tooltip: 'Seed Premium Data',
            ),
            IconButton(
              icon: const Icon(
                Icons.delete_sweep,
                color: Colors.redAccent,
                size: 20,
              ),
              onPressed: _isProcessing ? null : _clearDatabase,
              tooltip: 'Clear All Data',
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => _selectDate(context),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF39FF14).withAlpha(40),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: Color(0xFF39FF14),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('EEE, MMM dd').format(_selectedDate),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Icon(
                      Icons.arrow_drop_down,
                      size: 16,
                      color: Colors.grey,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.redAccent, size: 20),
              onPressed: _showLogoutConfirmation,
              tooltip: 'Log Out',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildManagementSection() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _foodItemController,
                  decoration: _inputDecoration('Item Name', Icons.fastfood),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration(
                    'Qty Made',
                    Icons.production_quantity_limits,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _soldController,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration(
                    'Qty Sold',
                    Icons.shopping_bag_outlined,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : _addItem,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF39FF14),
                    foregroundColor: const Color(0xFF0F172A),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isProcessing
                      ? const CircularProgressIndicator()
                      : const Text(
                          'Add to Stock',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(24),
            ),
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('food_tracking')
                  .where('establishmentId', isEqualTo: widget.uid)
                  .where('date', isEqualTo: _currentDate)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());
                final items = snapshot.data!.docs;
                if (items.isEmpty)
                  return _buildEmptyState(
                    'No items logged yet.',
                    Icons.no_food_outlined,
                  );

                return Scrollbar(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Theme(
                        data: Theme.of(
                          context,
                        ).copyWith(dividerColor: Colors.white.withAlpha(10)),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: MediaQuery.of(context).size.width * 0.6,
                          ),
                          child: DataTable(
                            columnSpacing:
                                MediaQuery.of(context).size.width * 0.05,
                            columns: const [
                              DataColumn(label: Text('Item Name')),
                              DataColumn(label: Text('Made')),
                              DataColumn(label: Text('Sold')),
                              DataColumn(label: Text('Surplus')),
                              DataColumn(label: Text('Actions')),
                            ],
                            rows: items.map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              return DataRow(
                                cells: [
                                  DataCell(
                                    Text(
                                      data['item_name'] ?? 'N/A',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  DataCell(Text('${data['quantity_made']}')),
                                  DataCell(Text('${data['quantity_sold']}')),
                                  DataCell(
                                    Text(
                                      '${data['quantity_surplus']}',
                                      style: TextStyle(
                                        color:
                                            (data['quantity_surplus'] ?? 0) > 0
                                            ? const Color(0xFF39FF14)
                                            : Colors.red,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit,
                                            size: 18,
                                          ),
                                          onPressed: () => _editItem(
                                            doc.id,
                                            data['item_name'],
                                            data['quantity_made'],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete,
                                            size: 18,
                                            color: Colors.redAccent,
                                          ),
                                          onPressed: () => _deleteItem(doc.id),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentSalesFeed() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('purchases')
            .where('establishmentId', isEqualTo: widget.uid)
            .limit(20)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return Center(child: Text('Error: ${snapshot.error}'));
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          final purchases = snapshot.data!.docs.toList();
          // Sort locally to avoid composite index
          purchases.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTime =
                (aData['purchaseDate'] as Timestamp?)?.toDate() ?? DateTime(0);
            final bTime =
                (bData['purchaseDate'] as Timestamp?)?.toDate() ?? DateTime(0);
            return bTime.compareTo(aTime);
          });

          if (purchases.isEmpty)
            return _buildEmptyState(
              'No sales yet.',
              Icons.shopping_cart_outlined,
            );

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: purchases.length,
            itemBuilder: (context, index) {
              final data = purchases[index].data() as Map<String, dynamic>;
              final date =
                  (data['purchaseDate'] as Timestamp?)?.toDate() ??
                  DateTime.now();
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['itemName'] ?? 'Item',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${data['quantity']} units • ${DateFormat('HH:mm').format(date)}',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_upward,
                      color: Color(0xFF39FF14),
                      size: 16,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDonationRequestsFeed() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('donations')
            .where('establishmentId', isEqualTo: widget.uid)
            .where('claimStatus', isEqualTo: 'pending')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          final requests = snapshot.data!.docs.toList();
          requests.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTime =
                (aData['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
            final bTime =
                (bData['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
            return bTime.compareTo(aTime);
          });

          if (requests.isEmpty)
            return _buildEmptyState(
              'No pending requests.',
              Icons.assignment_turned_in_outlined,
            );

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final data = requests[index].data() as Map<String, dynamic>;
              final docId = requests[index].id;
              final date =
                  (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.orangeAccent.withAlpha(60)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            data['item_name'] ?? 'Unknown',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orangeAccent.withAlpha(40),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${data['quantity']} units',
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Requested at ${DateFormat('dd MMM HH:mm').format(date)}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            FirebaseFirestore.instance
                                .collection('donations')
                                .doc(docId)
                                .update({
                                  'status': 'available',
                                  'claimStatus': 'none',
                                  'acceptorId': FieldValue.delete(),
                                  'claimedAt': FieldValue.delete(),
                                });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Rejected – item returned to market',
                                ),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            minimumSize: const Size(0, 28),
                          ),
                          child: const Text(
                            'Reject',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 6),
                        ElevatedButton(
                          onPressed: () {
                            FirebaseFirestore.instance
                                .collection('donations')
                                .doc(docId)
                                .update({
                                  'claimStatus': 'approved',
                                  'status': 'Claimed',
                                  'approvedAt': FieldValue.serverTimestamp(),
                                });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Approved!'),
                                backgroundColor: Color(0xFF39FF14),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF39FF14),
                            foregroundColor: const Color(0xFF0F172A),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            minimumSize: const Size(0, 28),
                          ),
                          child: const Text(
                            'Approve',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildApprovedDonationsFeed() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('donations')
            .where('establishmentId', isEqualTo: widget.uid)
            .where('claimStatus', isEqualTo: 'approved')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return Center(child: Text('Error: ${snapshot.error}'));
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          final approved = snapshot.data!.docs.toList();
          approved.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTime =
                (aData['approvedAt'] as Timestamp?)?.toDate() ?? DateTime(0);
            final bTime =
                (bData['approvedAt'] as Timestamp?)?.toDate() ?? DateTime(0);
            return bTime.compareTo(aTime);
          });

          if (approved.isEmpty)
            return _buildEmptyState(
              'No approved donations yet.',
              Icons.check_circle_outline,
            );

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: approved.length,
            itemBuilder: (context, index) {
              final data = approved[index].data() as Map<String, dynamic>;
              final approvedAt = (data['approvedAt'] as Timestamp?)?.toDate();
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF39FF14).withAlpha(60),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Color(0xFF39FF14),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['item_name'] ?? 'Unknown',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${data['quantity']} units${approvedAt != null ? " • Approved ${DateFormat('dd MMM HH:mm').format(approvedAt)}" : ""}',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: Colors.white.withAlpha(20)),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFF39FF14), size: 18),
      filled: true,
      fillColor: const Color(0xFF0F172A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF39FF14)),
      ),
    );
  }
}
