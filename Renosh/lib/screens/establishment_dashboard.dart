import 'dart:async';
import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
// import 'package:renosh_app/screens/secrets.dart';
import 'package:renosh_app/screens/surplus_details_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';

class Constants {
  static const Map<String, int> defaultPredictions = {
    'Butter Chicken': 120,
    'Paneer Tikka': 150,
    'Dal Makhani': 100,
    'Naan': 200,
  };
  static const Color primaryColor = Color(0xFF39FF14);
  static const Color backgroundColor = Color(0xFF1A3C34);
  static const Color errorColor = Color(0xFFFF4A4A);
  static const Color textColor = Color(0xFFF9F7F3);
  static const Color secondaryTextColor = Color(0xFFB0B0B0);
}

class EstablishmentDashboard extends StatefulWidget {
  const EstablishmentDashboard({super.key});

  @override
  State<EstablishmentDashboard> createState() => _EstablishmentDashboardState();
}

class _EstablishmentDashboardState extends State<EstablishmentDashboard>
    with TickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;
  String? _establishmentName;
  bool _isLoading = true;
  String _greeting = '';
  bool _isPredictionsLoading = false;
  Map<String, int>? _predictions;
  Map<String, int>? _yesterdayPredictions;
  String? _predictionsError;
  // Map<String, int>? _lastSuccessfulPredictions;
  bool _isOffline = false;
  // int _retryCount = 0;
  // static const int _maxRetries = 3;
  List<String> _aiInsights = [];
  bool _isFetchingInsights = false;
  List<Map<String, dynamic>> _sustainabilityData = [];
  StreamSubscription? _inventorySubscription;
  StreamSubscription? _donationSubscription;
  // bool _forceRefresh = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _glowAnimation = Tween<double>(begin: 0.2, end: 0.4).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    _animController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _glowController.repeat(reverse: true);
      }
    });
    _setGreeting();
    _fetchUserData();
    _fetchPredictions();
    _clearOldCache();
    _setupRealtimeListeners();
  }

  void _setupRealtimeListeners() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _inventorySubscription = FirebaseFirestore.instance
        .collection('food_tracking')
        .where('establishmentId', isEqualTo: user.uid)
        .snapshots()
        .listen((_) => _fetchSustainabilityData());

    _donationSubscription = FirebaseFirestore.instance
        .collection('donations')
        .where('establishmentId', isEqualTo: user.uid)
        .snapshots()
        .listen((_) => _fetchSustainabilityData());
  }

  @override
  void dispose() {
    _inventorySubscription?.cancel();
    _donationSubscription?.cancel();
    _animController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  void _setGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      _greeting = 'Good Morning';
    } else if (hour < 17) {
      _greeting = 'Good Afternoon';
    } else {
      _greeting = 'Good Evening';
    }
  }

  Future<void> _clearOldCache() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final now = DateTime.now();
    for (final key in keys) {
      if (key.startsWith('predictions_date_') ||
          key.startsWith('predictions_data_') ||
          key.startsWith('last_server_update_')) {
        final dateStr = key.split('_').last;
        try {
          final date = DateTime.parse(dateStr);
          if (now.difference(date).inDays > 7) {
            await prefs.remove(key);
          }
        } catch (e) {
          debugPrint('Failed to parse date in cache key $key: $e');
        }
      }
    }
  }

  Future<void> _clearCacheForDate(String targetDate) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('predictions_date_$targetDate');
    await prefs.remove('predictions_data_$targetDate');
    debugPrint('Cleared cache for $targetDate');
  }

  Future<bool> _checkConnectivity() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    return connectivityResult != ConnectivityResult.none;
  }

  Future<void> _fetchUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showErrorSnackBar('Please log in to continue.');
        setState(() => _isLoading = false);
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
        return;
      }

      final doc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
      if (doc.exists && doc.data()!['role'] == 'Food Establishment') {
        if (!mounted) return;
        setState(() {
          _establishmentName = doc.data()!['name'] ?? 'Establishment';
          _isLoading = false;
        });
        _fetchAIInsights();
      } else {
        _showErrorSnackBar('Invalid account type. Please contact support.');
        await FirebaseAuth.instance.signOut();
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
      }
    } on FirebaseAuthException catch (e) {
      _showErrorSnackBar('Authentication error: ${e.message}');
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } on FirebaseException catch (e) {
      _showErrorSnackBar('Database error: ${e.message}');
      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e) {
      _showErrorSnackBar('An unexpected error occurred. Please try again.');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchSustainabilityData() async {
    setState(() => _sustainabilityData = []);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final now = DateTime.now();
      final dateFormatter = DateFormat('yyyy-MM-dd');
      final Map<String, Map<String, double>> dailyMetrics = {};

      for (int i = 6; i >= 0; i--) {
        final dateStr = dateFormatter.format(now.subtract(Duration(days: i)));
        dailyMetrics[dateStr] = {
          'meals_donated': 0.0,
          'food_saved_kg': 0.0,
          'waste_reduced_kg': 0.0,
          'ai_optimized_waste_reduced_kg': 0.0,
        };
      }

      // 1. Get Donations
      final donationSnapshot =
          await FirebaseFirestore.instance
              .collection('donations')
              .where('establishmentId', isEqualTo: user.uid)
              .get();

      for (var doc in donationSnapshot.docs) {
        final data = doc.data();
        if (data['createdAt'] == null) continue;
        final dateStr = dateFormatter.format(
          (data['createdAt'] as Timestamp).toDate(),
        );
        if (dailyMetrics.containsKey(dateStr)) {
          final qty = (data['quantity']?.toDouble() ?? 0.0);
          dailyMetrics[dateStr]!['meals_donated'] =
              dailyMetrics[dateStr]!['meals_donated']! + qty;
          // 0.5kg per meal donated is a standard estimation
          dailyMetrics[dateStr]!['food_saved_kg'] =
              dailyMetrics[dateStr]!['food_saved_kg']! + (qty * 0.5);
        }
      }

      // 2. Get Food Tracking (Waste Reduction)
      final foodTrackingSnapshot =
          await FirebaseFirestore.instance
              .collection('food_tracking')
              .where('establishmentId', isEqualTo: user.uid)
              .get();

      for (var doc in foodTrackingSnapshot.docs) {
        final d = doc.data();
        final dateStr = d['date'] as String?;
        if (dateStr != null && dailyMetrics.containsKey(dateStr)) {
          final surplus = (d['quantity_surplus']?.toDouble() ?? 0.0);
          final isDonated = d['isDonated'] as bool? ?? false;
          final status = d['status'] as String? ?? '';

          if (isDonated || status == 'donated') {
            dailyMetrics[dateStr]!['waste_reduced_kg'] =
                dailyMetrics[dateStr]!['waste_reduced_kg']! + (surplus * 0.5);
          }
          // AI Optimized is a refinement based on smart surplus management
          dailyMetrics[dateStr]!['ai_optimized_waste_reduced_kg'] =
              dailyMetrics[dateStr]!['waste_reduced_kg']! * 0.45;
        }
      }

      final sortedDates = dailyMetrics.keys.toList()..sort();
      final finalData =
          sortedDates.map((date) {
            final m = dailyMetrics[date]!;
            return {
              'date': date,
              'meals_donated': m['meals_donated']!,
              'food_saved_kg': m['food_saved_kg']!,
              'waste_reduced_kg': m['waste_reduced_kg']!,
              'ai_optimized_waste_reduced_kg':
                  m['ai_optimized_waste_reduced_kg']!,
            };
          }).toList();

      if (!mounted) return;
      setState(() => _sustainabilityData = finalData);
    } catch (e) {
      debugPrint('Error deriving real sustainability data: $e');
    }
  }

  /*
  Future<Map<String, dynamic>> _fetchHistoricalData() async {
    // ... logic removed ...
  }
  */

  Future<void> _fetchAIInsights() async {
    if (_isFetchingInsights) return;
    setState(() => _isFetchingInsights = true);

    try {
      final apiKey = 'AIzaSyC-ZzwrwTh_9YdwGQGukXoOjtqOLw1K1KQ';
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: apiKey,
        safetySettings: [
          SafetySetting(HarmCategory.harassment, HarmBlockThreshold.none),
          SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.none),
          SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.none),
          SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.none),
        ],
      );

      final dataContext = _sustainabilityData
          .map((d) {
            return "Date: ${d['date']}, Meals Donated: ${d['meals_donated']}, Waste Reduced: ${d['waste_reduced_kg']}kg";
          })
          .join("\n");

      final prompt = """
        You are an AI specialized in food waste reduction for restaurants. 
        Based on the following 7-day sustainability tracking data for this establishment:
        $dataContext
        
        Provide exactly 4 short, actionable, and specific bullet points (insights) to help them improve their sustainability further.
        Keep each insight under 15 words. Focus on production planning, donation tips, and waste reduction.
        Only return the 4 bullet points, one per line, without any markdown formatting or introductory text.
      """;

      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);

      final text = response.text;
      if (text != null && text.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _aiInsights =
              text
                  .split('\n')
                  .map(
                    (s) => s.trim().replaceAll(RegExp(r'^[\*\-\d\.]+\s*'), ''),
                  )
                  .where((s) => s.isNotEmpty)
                  .take(4)
                  .toList();
        });
      }
    } catch (e) {
      debugPrint('Error fetching AI insights: $e');
      // Fallback to defaults if AI fails
      if (!mounted) return;
      setState(() {
        _aiInsights = [
          'Monitor weekend demand to optimize prep levels.',
          'Consider donating surplus items earlier in the evening.',
          'Review high-waste items for menu adjustments.',
          'Track sales patterns to refine daily quantity making.',
        ];
      });
    } finally {
      if (!mounted) return;
      setState(() => _isFetchingInsights = false);
    }
  }

  Future<void> _fetchPredictions({bool forceRefresh = false}) async {
    if (_isPredictionsLoading) return;
    setState(() {
      _isPredictionsLoading = true;
      _predictionsError = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final snapshot =
          await FirebaseFirestore.instance
              .collection('food_tracking')
              .where('establishmentId', isEqualTo: user.uid)
              .get();

      final dataByItem = <String, List<Map<String, dynamic>>>{};
      for (var doc in snapshot.docs) {
        final d = doc.data();
        final name = d['item_name'] ?? 'Unknown';
        dataByItem.putIfAbsent(name, () => []).add({
          'made': d['quantity_made'],
          'sold': d['quantity_sold'],
          'surplus': d['quantity_surplus'],
          'date': d['date'],
        });
      }

      if (dataByItem.isEmpty) {
        if (!mounted) return;
        setState(() {
          _predictions = null;
          _isPredictionsLoading = false;
        });
        return;
      }

      final requestItems = <Map<String, dynamic>>[];
      dataByItem.forEach((name, history) {
        final recentHistory =
            history.toList()..sort((a, b) => b['date'].compareTo(a['date']));
        
        final top7 = recentHistory.take(7).toList();
        if (top7.isEmpty) return;

        double totalMade = 0.0;
        double totalSurplus = 0.0;
        
        for (var h in top7) {
          totalMade += (h['made'] ?? 0.0).toDouble();
          totalSurplus += (h['surplus'] ?? 0.0).toDouble();
        }
        
        final avgMade = totalMade / top7.length;
        final avgSurplus = totalSurplus / top7.length;
        
        requestItems.add({
          'name': name,
          'qty_prep': avgMade.round(),
          'avg_wastage_7d': avgSurplus,
        });
      });

      final response = await http.post(
        Uri.parse('http://127.0.0.1:5000/predict'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'items': requestItems}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final predictedDict = data['predictions'] as Map<String, dynamic>? ?? {};
        final newPredictions = <String, int>{};
        predictedDict.forEach((k, v) {
          newPredictions[k] = (v as num).toInt();
        });

        if (!mounted) return;
        setState(() {
          _predictions = newPredictions.isEmpty ? null : newPredictions;
          _isPredictionsLoading = false;
        });
      } else {
        throw Exception('Server error: \${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching AI predictions: $e');
      final errorStr = e.toString();
      if (!mounted) return;
      setState(() {
        _isPredictionsLoading = false;
        _predictionsError =
            'AI forecasting unavailable: ${errorStr.length > 30 ? errorStr.substring(0, 30) : errorStr}...';
      });
    }
    _fetchAIInsights();
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.inter(color: Constants.textColor, fontSize: 14),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Constants.errorColor,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.inter(color: Constants.textColor, fontSize: 14),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Constants.primaryColor,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

  void _showPredictionsDialog() {
    debugPrint('Showing predictions dialog');
    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16),
            child: Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF2D2D2D),
                        Constants.backgroundColor.withOpacity(0.9),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(4, 4),
                      ),
                      BoxShadow(
                        color: Constants.textColor.withOpacity(0.03),
                        blurRadius: 8,
                        offset: const Offset(-4, -4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Constants.primaryColor.withOpacity(0.3),
                              Constants.backgroundColor.withOpacity(0.5),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Today\'s AI Predictions',
                                style: GoogleFonts.inter(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: Constants.textColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Row(
                              children: [
                                if (_isOffline)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Icon(
                                      Icons.cloud_off,
                                      color: Constants.secondaryTextColor,
                                      size: 24,
                                    ),
                                  ),
                                IconButton(
                                  icon: Icon(
                                    Icons.refresh,
                                    color: Constants.primaryColor,
                                    size: 24,
                                  ),
                                  onPressed:
                                      _isPredictionsLoading
                                          ? null
                                          : () async {
                                            debugPrint(
                                              'Refresh predictions clicked',
                                            );
                                            final now = DateTime.now();
                                            final targetDate =
                                                now.toIso8601String().split(
                                                  'T',
                                                )[0];
                                            await _clearCacheForDate(
                                              targetDate,
                                            );
                                            _fetchPredictions(
                                              forceRefresh: true,
                                            );
                                          },
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.close,
                                    color: Constants.textColor,
                                    size: 24,
                                  ),
                                  onPressed: () {
                                    debugPrint('Closing predictions dialog');
                                    Navigator.pop(context);
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_isPredictionsLoading)
                        Column(
                          children: [
                            Center(
                              child: SizedBox(
                                width: 36,
                                height: 36,
                                child: CircularProgressIndicator(
                                  color: Constants.primaryColor,
                                  strokeWidth: 2.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Fetching predictions... This may take up to 30 seconds.',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: Constants.secondaryTextColor,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        )
                      else if (_predictionsError != null)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Constants.errorColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Constants.errorColor.withOpacity(0.4),
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: Constants.errorColor,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _predictionsError!,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Constants.textColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'The API may take up to 30 seconds to respond.',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: Constants.secondaryTextColor,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      else if (_predictions == null || _predictions!.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2D2D2D).withOpacity(0.7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Constants.secondaryTextColor,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'No predictions available for today.',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Constants.secondaryTextColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.of(context).size.height * 0.4,
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _predictions!.length,
                            itemBuilder: (context, index) {
                              final dish = _predictions!.keys.elementAt(index);
                              final quantity = _predictions![dish]!;
                              final yesterdayQuantity =
                                  _yesterdayPredictions != null &&
                                          _yesterdayPredictions!.containsKey(
                                            dish,
                                          )
                                      ? _yesterdayPredictions![dish]!
                                      : null;
                              IconData? trendIcon;
                              Color? trendColor;
                              if (yesterdayQuantity != null) {
                                if (quantity > yesterdayQuantity) {
                                  trendIcon = Icons.trending_up;
                                  trendColor = Constants.primaryColor;
                                } else if (quantity < yesterdayQuantity) {
                                  trendIcon = Icons.trending_down;
                                  trendColor = Constants.errorColor;
                                } else {
                                  trendIcon = Icons.trending_flat;
                                  trendColor = Constants.secondaryTextColor;
                                }
                              }

                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 400),
                                curve: Curves.easeOut,
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color(0xFF2D2D2D).withOpacity(0.9),
                                      Constants.backgroundColor.withOpacity(
                                        0.8,
                                      ),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.08),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                    BoxShadow(
                                      color: Constants.primaryColor.withOpacity(
                                        0.05,
                                      ),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                  border: Border.all(
                                    color: Constants.primaryColor.withOpacity(
                                      0.2,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Constants.primaryColor
                                            .withOpacity(0.2),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.restaurant_menu,
                                        color: Constants.primaryColor,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  dish,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: Constants.textColor,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (trendIcon != null)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        left: 8,
                                                      ),
                                                  child: Icon(
                                                    trendIcon,
                                                    color: trendColor,
                                                    size: 20,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Predicted: $quantity ${quantity == 1 ? 'item' : 'items'}',
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w400,
                                              color:
                                                  Constants.secondaryTextColor,
                                            ),
                                          ),
                                          if (yesterdayQuantity != null)
                                            Text(
                                              'Yesterday: $yesterdayQuantity ${yesterdayQuantity == 1 ? 'item' : 'items'}',
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w400,
                                                color:
                                                    Constants
                                                        .secondaryTextColor,
                                              ),
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
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: const Duration(seconds: 5),
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.topLeft,
                          radius: 2,
                          colors: [
                            Constants.primaryColor.withOpacity(0.05),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
    ).catchError((e) {
      debugPrint('Error showing predictions dialog: $e');
      _showErrorSnackBar('Failed to show predictions dialog: $e');
    });
  }

  Widget _buildAIInsightsCard() {
    return GestureDetector(
      onTap: () {
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          HapticFeedback.lightImpact();
        }
        debugPrint('AI Insights card tapped');
        _showSuccessSnackBar('AI Insights refreshed!');
        _fetchAIInsights();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF2D2D2D),
              Constants.backgroundColor.withOpacity(0.9),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(4, 4),
            ),
            BoxShadow(
              color: Constants.textColor.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(-4, -4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI Insights',
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Constants.textColor,
              ),
            ),
            const SizedBox(height: 16),
            if (_isFetchingInsights)
              Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Constants.primaryColor,
                    strokeWidth: 2,
                  ),
                ),
              )
            else if (_aiInsights.isEmpty)
              Text(
                'No insights available. Tap to refresh.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Constants.secondaryTextColor,
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children:
                    _aiInsights.map((insight) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '• ',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: Constants.textColor,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                insight,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: Constants.textColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
              ),
            const SizedBox(height: 8),
            Text(
              'Powered by ReNosh AI',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Constants.secondaryTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSustainabilityCharts() {
    if (_sustainabilityData.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF2D2D2D),
              Constants.backgroundColor.withOpacity(0.9),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(4, 4),
            ),
            BoxShadow(
              color: Constants.textColor.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(-4, -4),
            ),
          ],
        ),
        child: Center(
          child: SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              color: Constants.primaryColor,
              strokeWidth: 2.5,
            ),
          ),
        ),
      );
    }

    final mealsDonatedData =
        _sustainabilityData.asMap().entries.map((entry) {
          return BarChartGroupData(
            x: entry.key,
            barRods: [
              BarChartRodData(
                toY: entry.value['meals_donated'],
                color: Constants.primaryColor,
              ),
            ],
          );
        }).toList();

    final foodSavedData =
        _sustainabilityData.asMap().entries.map((entry) {
          return FlSpot(entry.key.toDouble(), entry.value['food_saved_kg']);
        }).toList();

    final totalWasteReduced = _sustainabilityData.fold<double>(
      0,
      (sum, item) => sum + item['waste_reduced_kg'],
    );
    final totalAIWasteReduced = _sustainabilityData.fold<double>(
      0,
      (sum, item) => sum + item['ai_optimized_waste_reduced_kg'],
    );
    final standardWasteReduced = totalWasteReduced - totalAIWasteReduced;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF2D2D2D),
            Constants.backgroundColor.withOpacity(0.9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(4, 4),
          ),
          BoxShadow(
            color: Constants.textColor.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(-4, -4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sustainability Tracking',
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Constants.textColor,
            ),
          ),
          const SizedBox(height: 16),
          CarouselSlider(
            options: CarouselOptions(
              height: 240,
              autoPlay: true,
              enlargeCenterPage: true,
              aspectRatio: 2.0,
              viewportFraction: 0.8,
              autoPlayAnimationDuration: const Duration(milliseconds: 800),
              enableInfiniteScroll: true,
            ),
            items: [
              _buildChartCard(
                title: 'Meals Donated (Last 7 Days)',
                chart: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index >= 0 &&
                                index < _sustainabilityData.length) {
                              final date =
                                  _sustainabilityData[index]['date']
                                      .split('-')
                                      .last;
                              return SideTitleWidget(
                                meta: meta,
                                child: Text(
                                  date,
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: Constants.secondaryTextColor,
                                  ),
                                ),
                              );
                            }
                            return const Text('');
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          getTitlesWidget: (value, meta) {
                            return Text(
                              value.toInt().toString(),
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 10,
                              ),
                            );
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    barGroups: mealsDonatedData,
                  ),
                ),
              ),
              _buildChartCard(
                title: 'Food Saved (kg, Last 7 Days)',
                chart: LineChart(
                  LineChartData(
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index >= 0 &&
                                index < _sustainabilityData.length) {
                              final date =
                                  _sustainabilityData[index]['date']
                                      .split('-')
                                      .last;
                              return SideTitleWidget(
                                meta: meta,
                                child: Text(
                                  date,
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: Constants.secondaryTextColor,
                                  ),
                                ),
                              );
                            }
                            return const Text('');
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          getTitlesWidget: (value, meta) {
                            return Text(
                              value.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 10,
                              ),
                            );
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: foodSavedData,
                        isCurved: true,
                        color: Constants.primaryColor,
                        barWidth: 4,
                        isStrokeCapRound: true,
                        belowBarData: BarAreaData(show: false),
                      ),
                    ],
                  ),
                ),
              ),
              _buildChartCard(
                title: 'Waste Reduction Impact',
                chart: PieChart(
                  PieChartData(
                    sections: [
                      PieChartSectionData(
                        value: totalAIWasteReduced,
                        color: Constants.primaryColor,
                        title: 'AI-Optimized',
                        titleStyle: GoogleFonts.inter(
                          fontSize: 12,
                          color: Constants.textColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      PieChartSectionData(
                        value: standardWasteReduced,
                        color: Constants.secondaryTextColor,
                        title: 'Standard',
                        titleStyle: GoogleFonts.inter(
                          fontSize: 12,
                          color: Constants.textColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    sectionsSpace: 0,
                    centerSpaceRadius: 40,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard({required String title, required Widget chart}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8),
        ],
      ),
      child: Column(
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Constants.textColor,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          SizedBox(height: 105, child: chart),
        ],
      ),
    );
  }

  Widget _buildSurplusItems() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D).withOpacity(0.7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              color: Constants.secondaryTextColor,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Please log in to view surplus items.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Constants.secondaryTextColor,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF2D2D2D),
            Constants.backgroundColor.withOpacity(0.9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(4, 4),
          ),
          BoxShadow(
            color: Constants.textColor.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(-4, -4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Surplus Items',
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Constants.textColor,
            ),
          ),
          const SizedBox(height: 4),
          StreamBuilder<QuerySnapshot>(
            stream:
                FirebaseFirestore.instance
                    .collection('food_tracking')
                    .where('establishmentId', isEqualTo: user.uid)
                    .where('date', isEqualTo: DateFormat('yyyy-MM-dd').format(DateTime.now()))
                    .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      color: Constants.primaryColor,
                      strokeWidth: 2.5,
                    ),
                  ),
                );
              }
              if (snapshot.hasError) {
                debugPrint('Surplus query error: \${snapshot.error}');
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Constants.errorColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Constants.errorColor.withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Constants.errorColor,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Failed to load surplus items. Please try again later.',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Constants.textColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              final surplusDocs = snapshot.data?.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>?;
                final qty = (data?['quantity_surplus'] as num?)?.toInt() ?? 0;
                return qty > 0;
              }).toList() ?? [];

              if (!snapshot.hasData || surplusDocs.isEmpty) {
                debugPrint('No surplus items found for user: \${user.uid}');
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D2D2D).withOpacity(0.7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Constants.secondaryTextColor,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No surplus items found for today. Try adding some in Food Track.',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Constants.secondaryTextColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
              debugPrint('Found \${surplusDocs.length} surplus items for today');
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: surplusDocs.length,
                itemBuilder: (context, index) {
                  final doc = surplusDocs[index];
                  final item = doc['item_name']?.toString() ?? 'Unnamed Item';
                  final quantity = (doc['quantity_surplus'] as num?)?.toInt() ?? 0;

                  return InkWell(
                    onTap: () {
                      try {
                        debugPrint(
                          'Navigating to SurplusDetailsScreen for item: $item',
                        );
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (context) => SurplusDetailsScreen(
                                  itemName: item,
                                  quantity: quantity,
                                  docId: doc.id,
                                ),
                          ),
                        );
                      } catch (e) {
                        debugPrint('Navigation exception: $e');
                        _showErrorSnackBar(
                          'Error navigating to surplus details: $e',
                        );
                      }
                    },
                    splashColor: Constants.primaryColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(14),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2D2D2D).withOpacity(0.85),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                          BoxShadow(
                            color: Constants.primaryColor.withOpacity(0.05),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                        border: Border.all(
                          color: Constants.primaryColor.withOpacity(0.1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Constants.primaryColor.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.restaurant_menu,
                              color: Constants.primaryColor,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item,
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Constants.textColor,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Surplus: $quantity ${quantity == 1 ? 'item' : 'items'}',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    color: Constants.secondaryTextColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineBanner() {
    if (!_isOffline) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Constants.errorColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Constants.errorColor.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off, color: Constants.errorColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'You are offline. Using cached data.',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Constants.textColor,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              debugPrint('Retry connection clicked');
              if (await _checkConnectivity()) {
                setState(() {
                  _isOffline = false;
                });
                _fetchPredictions(forceRefresh: true);
                _fetchAIInsights();
                _fetchSustainabilityData();
              } else {
                _showErrorSnackBar(
                  'Still offline. Please check your connection.',
                );
              }
            },
            child: Text(
              'Retry',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Constants.primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Constants.backgroundColor,
      body:
          _isLoading
              ? Center(
                child: CircularProgressIndicator(
                  color: Constants.primaryColor,
                  strokeWidth: 2.5,
                ),
              )
              : SafeArea(
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: FadeTransition(
                                    opacity: _fadeAnimation,
                                    child: ScaleTransition(
                                      scale: _scaleAnimation,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _greeting,
                                            style: GoogleFonts.inter(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w400,
                                              color:
                                                  Constants.secondaryTextColor,
                                            ),
                                          ),
                                          Text(
                                            _establishmentName ?? 'Restaurant',
                                            style: GoogleFonts.inter(
                                              fontSize: 28,
                                              fontWeight: FontWeight.w700,
                                              color: Constants.textColor,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: GestureDetector(
                                    onTap: () {
                                      debugPrint(
                                        'Today\'s Predictions button tapped',
                                      );
                                      if (!kIsWeb &&
                                          (Platform.isAndroid ||
                                              Platform.isIOS)) {
                                        HapticFeedback.lightImpact();
                                      }
                                      _showPredictionsDialog();
                                    },
                                    child: AnimatedBuilder(
                                      animation: _glowController,
                                      builder: (context, child) {
                                        return Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Constants.primaryColor
                                                .withOpacity(
                                                  _glowAnimation.value,
                                                ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Constants.primaryColor
                                                    .withOpacity(0.4),
                                                blurRadius: 8,
                                                spreadRadius: 1,
                                              ),
                                            ],
                                          ),
                                          child: Icon(
                                            Icons.insights,
                                            color: Constants.textColor,
                                            size: 28,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildOfflineBanner(),
                          _buildAIInsightsCard(),
                          const SizedBox(height: 24),
                          _buildSustainabilityCharts(),
                          const SizedBox(height: 24),
                          _buildSurplusItems(),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
    );
  }
}
