import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'firebase_options.dart';
import 'login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const RenoshConsumerApp());
}

class CartItem {
  final String id;
  final String name;
  int quantity;
  final int maxSurplus;
  final String establishmentId;

  CartItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.maxSurplus,
    required this.establishmentId,
  });
}

class RenoshConsumerApp extends StatelessWidget {
  const RenoshConsumerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Renosh Consumer',
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
            return BrowseItemsScreenWrapper(user: snapshot.data!);
          }
          return const LoginScreen();
        },
      ),
    );
  }
}

class BrowseItemsScreenWrapper extends StatelessWidget {
  final User user;
  const BrowseItemsScreenWrapper({super.key, required this.user});

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

        // role check removed as requested

        return const BrowseItemsScreen();
      },
    );
  }
}

class BrowseItemsScreen extends StatefulWidget {
  const BrowseItemsScreen({super.key});

  @override
  State<BrowseItemsScreen> createState() => _BrowseItemsScreenState();
}

class _BrowseItemsScreenState extends State<BrowseItemsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, int> _localQuantities = {};
  final Map<String, CartItem> _cart = {};

  void _addToCart(
    String docId,
    String name,
    int surplus,
    int quantity,
    String establishmentId,
  ) {
    setState(() {
      if (_cart.containsKey(docId)) {
        _cart[docId]!.quantity += quantity;
        if (_cart[docId]!.quantity > surplus) {
          _cart[docId]!.quantity = surplus;
        }
      } else {
        _cart[docId] = CartItem(
          id: docId,
          name: name,
          quantity: quantity,
          maxSurplus: surplus,
          establishmentId: establishmentId,
        );
      }
      _localQuantities[docId] = 1; // Reset local selector
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added $quantity $name to cart'),
        backgroundColor: const Color(0xFF39FF14),
        behavior: SnackBarBehavior.floating,
        duration: 1.seconds,
      ),
    );
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) return;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final batch = _firestore.batch();
      final List<Map<String, dynamic>> purchaseRecords = [];

      for (var item in _cart.values) {
        final docRef = _firestore.collection('food_tracking').doc(item.id);

        // Use increment for sold and decrement for surplus
        batch.update(docRef, {
          'quantity_surplus': FieldValue.increment(-item.quantity),
          'quantity_sold': FieldValue.increment(item.quantity),
        });

        purchaseRecords.add({
          'itemId': item.id,
          'itemName': item.name,
          'purchaseDate': FieldValue.serverTimestamp(),
          'quantity': item.quantity,
          'consumerId':
              FirebaseAuth.instance.currentUser?.uid ?? 'anonymous_web_user',
          'establishmentId': item.establishmentId,
        });
      }

      // Add all purchases to history
      for (var record in purchaseRecords) {
        batch.set(_firestore.collection('purchases').doc(), record);
      }

      await batch.commit();

      if (mounted) {
        Navigator.pop(context); // Remove loading
        setState(() => _cart.clear());
        _showSuccessDialog();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Checkout failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Order Placed!'),
        content: const Text('Your order has been successfully processed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Great!',
              style: TextStyle(color: Color(0xFF39FF14)),
            ),
          ),
        ],
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

  void _showCart() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Your Cart',
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              if (_cart.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40.0),
                  child: Text('Your cart is empty.'),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _cart.length,
                    itemBuilder: (context, index) {
                      final item = _cart.values.elementAt(index);
                      return ListTile(
                        title: Text(item.name),
                        subtitle: Text('Qty: ${item.quantity}'),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.redAccent,
                          ),
                          onPressed: () {
                            setState(() => _cart.remove(item.id));
                            setModalState(() {});
                          },
                        ),
                      );
                    },
                  ),
                ),
              const Divider(height: 40),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _cart.isEmpty
                      ? null
                      : () {
                          Navigator.pop(context);
                          _checkout();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF39FF14),
                    foregroundColor: const Color(0xFF0F172A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Checkout Now',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 180,
            floating: false,
            pinned: true,
            backgroundColor: const Color(0xFF1E293B),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.redAccent),
                onPressed: _showLogoutConfirmation,
                tooltip: 'Log Out',
              ),
              Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.shopping_cart_outlined),
                    onPressed: _showCart,
                  ),
                  if (_cart.isNotEmpty)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '${_cart.length}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                'Renosh Consumer',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              background: Container(color: const Color(0xFF1E293B)),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('food_tracking')
                  .where(
                    'date',
                    isEqualTo: DateFormat('yyyy-MM-dd').format(DateTime.now()),
                  )
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return SliverToBoxAdapter(
                    child: Center(child: Text('Error: ${snapshot.error}')),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SliverToBoxAdapter(
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final items = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return (data['quantity_surplus'] ?? 0) > 0;
                }).toList();
                if (items.isEmpty) {
                  return const SliverToBoxAdapter(
                    child: Center(child: Text('No items available.')),
                  );
                }

                return SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 450,
                    mainAxisSpacing: 24,
                    crossAxisSpacing: 24,
                    childAspectRatio: 0.85,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final item = items[index].data() as Map<String, dynamic>;
                    final docId = items[index].id;
                    return ItemCard(
                      key: ValueKey(docId),
                      id: docId,
                      name: item['item_name'] ?? 'Unknown',
                      surplus: item['quantity_surplus'] ?? 0,
                      initialQty: _localQuantities[docId] ?? 1,
                      onAddToCart: (qty) => _addToCart(
                        docId,
                        item['item_name'],
                        item['quantity_surplus'],
                        qty,
                        item['establishmentId'] ?? 'unknown_establishment',
                      ),
                      onQtyChanged: (qty) => _localQuantities[docId] = qty,
                    );
                  }, childCount: items.length),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ItemCard extends StatefulWidget {
  final String id;
  final String name;
  final int surplus;
  final int initialQty;
  final Function(int) onAddToCart;
  final Function(int) onQtyChanged;

  const ItemCard({
    super.key,
    required this.id,
    required this.name,
    required this.surplus,
    required this.initialQty,
    required this.onAddToCart,
    required this.onQtyChanged,
  });

  @override
  State<ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<ItemCard>
    with AutomaticKeepAliveClientMixin {
  late int _qty;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _qty = widget.initialQty;
  }

  @override
  void didUpdateWidget(ItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQty != widget.initialQty) {
      _qty = widget.initialQty;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withAlpha(15), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F172A),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.flatware,
                      size: 64,
                      color: const Color(0xFF39FF14).withAlpha(40),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.name,
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.surplus} servings remaining',
                      style: TextStyle(color: Colors.grey[400], fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove, size: 18),
                                onPressed: _qty > 1
                                    ? () {
                                        setState(() => _qty--);
                                        widget.onQtyChanged(_qty);
                                      }
                                    : null,
                              ),
                              Text(
                                '$_qty',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add, size: 18),
                                onPressed: _qty < widget.surplus
                                    ? () {
                                        setState(() => _qty++);
                                        widget.onQtyChanged(_qty);
                                      }
                                    : null,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: () => widget.onAddToCart(_qty),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF39FF14),
                                foregroundColor: const Color(0xFF0F172A),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Add to Cart',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        )
        .animate(onPlay: (controller) => controller.forward())
        .fadeIn(duration: 400.ms);
  }
}
