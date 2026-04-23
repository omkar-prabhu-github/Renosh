import 'package:http/http.dart' as http;
import 'dart:convert';

class MapsService {
  /// Fetches LatLng for a given pincode or address string using the Nominatim API.
  /// Returns a Map with 'lat' and 'lng' keys.
  static Future<Map<String, double>?> getLatLngFromAddress(
    String address,
  ) async {
    if (address.trim().isEmpty) return null;

    try {
      final encodedAddress = Uri.encodeComponent(address);
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=$encodedAddress&format=json&limit=1',
      );

      final response = await http.get(
        url,
        headers: {'User-Agent': 'RenoshInventoryApp/1.0 (contact@renosh.app)'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        if (data.isNotEmpty) {
          final lat = double.tryParse(data[0]['lat'] as String);
          final lng = double.tryParse(data[0]['lon'] as String);
          if (lat != null && lng != null) {
            print('Geocoded "$address" to lat=$lat, lng=$lng');
            return {'lat': lat, 'lng': lng};
          }
        }
      }
    } catch (e) {
      print('Nominatim geocoding error for "$address": $e');
    }

    return null;
  }
}
