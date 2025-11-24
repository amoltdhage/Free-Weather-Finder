import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  runApp(const WeatherApp());
}

class WeatherApp extends StatelessWidget {
  const WeatherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Free Weather Finder",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, fontFamily: 'Poppins'),
      home: const WeatherHome(),
    );
  }
}

class WeatherHome extends StatefulWidget {
  const WeatherHome({super.key});

  @override
  State<WeatherHome> createState() => _WeatherHomeState();
}

class _WeatherHomeState extends State<WeatherHome> {
  final TextEditingController _controller = TextEditingController();
  bool loading = false;
  String? error;
  WeatherData? weather;
  List<DailyForecast> forecast = [];
  List<String> recentCities = [];
  double? currentLat;
  double? currentLon;

  @override
  void initState() {
    super.initState();
    _loadRecentCities();
    _tryAutoLocate();
  }

  // --- SharedPreferences ---
  Future<void> _loadRecentCities() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      recentCities = prefs.getStringList('recentCities') ?? [];
    });
  }

  Future<void> _saveCity(String city) async {
    final prefs = await SharedPreferences.getInstance();
    recentCities.remove(city);
    recentCities.insert(0, city);
    if (recentCities.length > 5) recentCities.removeLast();
    await prefs.setStringList('recentCities', recentCities);
    setState(() {});
  }

  Future<void> _removeCity(String city) async {
    final prefs = await SharedPreferences.getInstance();
    recentCities.remove(city);
    await prefs.setStringList('recentCities', recentCities);
    setState(() {});
  }

  // --- Auto-location ---
  Future<void> _tryAutoLocate() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      currentLat = pos.latitude;
      currentLon = pos.longitude;
      await fetchWeatherByCoordinates(
        currentLat!,
        currentLon!,
        saveCity: false,
      );
    } catch (e) {}
  }

  // --- Fetch weather by city name ---
  Future<void> fetchWeather(String city) async {
    if (city.trim().isEmpty) {
      if (currentLat != null && currentLon != null) {
        await fetchWeatherByCoordinates(
          currentLat!,
          currentLon!,
          saveCity: false,
        );
      }
      return;
    }

    setState(() {
      loading = true;
      error = null;
      weather = null;
      forecast = [];
    });

    try {
      final geoUrl = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
        "name": city,
        "count": "1",
      });
      final geoResponse = await http.get(geoUrl);
      final geoJson = jsonDecode(geoResponse.body);

      if (geoJson["results"] == null || geoJson["results"].isEmpty) {
        setState(() {
          error = "City not found ⚠️";
          loading = false;
        });
        return;
      }

      final loc = geoJson["results"][0];
      final lat = (loc["latitude"] as num).toDouble();
      final lon = (loc["longitude"] as num).toDouble();

      await _fetchWeatherForLatLon(lat, lon, loc["name"]);
      await _saveCity(loc["name"]);
    } catch (e) {
      setState(() => error = "Something went wrong 😢");
    } finally {
      setState(() => loading = false);
    }
  }

  // --- Fetch weather by coordinates ---
  Future<void> fetchWeatherByCoordinates(
    double lat,
    double lon, {
    bool saveCity = false,
  }) async {
    setState(() {
      loading = true;
      error = null;
      weather = null;
      forecast = [];
    });

    try {
      final revUrl = Uri.https('geocoding-api.open-meteo.com', '/v1/reverse', {
        'latitude': lat.toString(),
        'longitude': lon.toString(),
        'count': '1',
      });
      final revResp = await http.get(revUrl);
      final revJson = jsonDecode(revResp.body);
      String cityName = "Current Location";
      if (revJson['results'] != null && revJson['results'].isNotEmpty) {
        cityName = revJson['results'][0]['name'] ?? cityName;
      }

      await _fetchWeatherForLatLon(lat, lon, cityName, isCurrentLocation: true);
    } catch (e) {
      setState(() => error = "Could not detect location weather.");
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _fetchWeatherForLatLon(
    double lat,
    double lon,
    String cityName, {
    bool isCurrentLocation = false,
  }) async {
    final weatherUrl = Uri.https('api.open-meteo.com', '/v1/forecast', {
      "latitude": lat.toString(),
      "longitude": lon.toString(),
      "current_weather": "true",
      "hourly": "relativehumidity_2m",
      "daily": "temperature_2m_max,temperature_2m_min",
      "timezone": "auto",
    });

    final weatherResponse = await http.get(weatherUrl);
    final weatherJson = jsonDecode(weatherResponse.body);

    final displayName = isCurrentLocation ? "Current Location" : cityName;

    setState(() {
      weather = WeatherData.fromJson(weatherJson, displayName);
      forecast = DailyForecast.fromJsonList(weatherJson);

      if (!isCurrentLocation) {
        _controller.text = displayName;
      }
    });
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Free Weather Finder"),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.location_on),
              tooltip: "Use current location",
              onPressed: () async {
                final serviceEnabled =
                    await Geolocator.isLocationServiceEnabled();
                if (!serviceEnabled) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Location services are disabled."),
                    ),
                  );
                  return;
                }

                LocationPermission permission =
                    await Geolocator.checkPermission();
                if (permission == LocationPermission.denied) {
                  permission = await Geolocator.requestPermission();
                  if (permission == LocationPermission.denied) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Location permission denied."),
                      ),
                    );
                    return;
                  }
                }

                if (permission == LocationPermission.deniedForever) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Location permissions are permanently denied.",
                      ),
                    ),
                  );
                  return;
                }

                final pos = await Geolocator.getCurrentPosition(
                  desiredAccuracy: LocationAccuracy.medium,
                );
                currentLat = pos.latitude;
                currentLon = pos.longitude;
                await fetchWeatherByCoordinates(
                  currentLat!,
                  currentLon!,
                  saveCity: false,
                );
              },
            ),
          ],
        ),
        body: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.black87, // Keep neutral dark background
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              _buildSearchBox(),
              if (recentCities.isNotEmpty) _buildRecentSearch(),
              const SizedBox(height: 30),
              if (loading)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              if (error != null)
                Center(
                  child: Text(
                    error!,
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              if (weather != null) _buildWeatherCard(weather!),
              if (forecast.isNotEmpty) _buildForecast(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBox() {
    return TextField(
      controller: _controller,
      style: const TextStyle(color: Colors.white),
      textInputAction: TextInputAction.search,
      onChanged: (value) {
        if (value.trim().isEmpty) {
          if (currentLat != null && currentLon != null) {
            fetchWeatherByCoordinates(
              currentLat!,
              currentLon!,
              saveCity: false,
            );
          }
        }
      },
      onSubmitted: (value) {
        if (value.trim().isNotEmpty) fetchWeather(value.trim());
      },
      decoration: InputDecoration(
        hintText: "Enter City Name",
        hintStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: Colors.white10,
        suffixIcon: IconButton(
          icon: const Icon(Icons.search, color: Colors.white),
          onPressed: () {
            final text = _controller.text.trim();
            if (text.isNotEmpty) fetchWeather(text);
          },
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
          color: Color.fromARGB(231, 255, 255, 255), // <-- your desired border color
          width: 1.5,
        ),
        ),
      ),
    );
  }

  Widget _buildRecentSearch() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        height: 38,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: recentCities.map((city) {
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Chip(
                backgroundColor: Colors.white10,
                label: GestureDetector(
                  onTap: () {
                    _controller.text = city;
                    fetchWeather(city);
                  },
                  child: Text(
                    city,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                deleteIcon: const Icon(
                  Icons.close,
                  size: 18,
                  color: Colors.redAccent,
                ),
                onDeleted: () => _removeCity(city),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildWeatherCard(WeatherData w) {
    final bgColors = _getBackgroundColors(w.temperature);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: bgColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Center(
            child: Text(
              w.city,
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 10),
          Icon(
            _getIconForTemp(w.temperature),
            size: 90,
            color: Colors.yellow.shade300,
          ),
          const SizedBox(height: 12),
          Text(
            "${w.temperature.toStringAsFixed(1)}°C",
            style: const TextStyle(fontSize: 60, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Row(
                  children: [
                    const Icon(Icons.air, size: 26),
                    const SizedBox(width: 6),
                    Text(
                      "${w.wind} km/h",
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.water_drop, size: 26),
                    const SizedBox(width: 6),
                    Text(
                      "${w.humidity ?? '--'}%",
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildForecast() {
    final toShow = forecast.length >= 4 ? forecast.sublist(1, 4) : forecast;
    return Expanded(
      child: ListView.builder(
        itemCount: toShow.length,
        itemBuilder: (context, i) {
          final day = toShow[i];
          final mid = (day.maxTemp + day.minTemp) / 2;
          final cardColor = _getBackgroundColors(mid)[0].withOpacity(0.4);
          return Card(
            color: cardColor,
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: ListTile(
              leading: Icon(_getIconForTemp(mid), color: Colors.white),
              title: Text(
                day.date,
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                "Min ${day.minTemp}° • Max ${day.maxTemp}°",
                style: const TextStyle(color: Colors.white70),
              ),
              trailing: Text(
                "${mid.toStringAsFixed(0)}°",
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
        },
      ),
    );
  }
}

// --- MODELS ---
class WeatherData {
  final String city;
  final double temperature;
  final double wind;
  final double? humidity;

  WeatherData({
    required this.city,
    required this.temperature,
    required this.wind,
    this.humidity,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json, String city) {
    final current = json["current_weather"];
    final humidityList =
        (json["hourly"]?["relativehumidity_2m"]) as List<dynamic>?;
    double? humidityValue;
    if (humidityList != null && humidityList.isNotEmpty) {
      humidityValue = (humidityList[0] as num).toDouble();
    }

    return WeatherData(
      city: city,
      temperature: (current["temperature"] as num).toDouble(),
      wind: (current["windspeed"] as num).toDouble(),
      humidity: humidityValue,
    );
  }
}

class DailyForecast {
  final String date;
  final double maxTemp;
  final double minTemp;

  DailyForecast({
    required this.date,
    required this.maxTemp,
    required this.minTemp,
  });

  static List<DailyForecast> fromJsonList(Map<String, dynamic> json) {
    final dates = (json["daily"]?["time"]) as List<dynamic>? ?? [];
    final maxTemps =
        (json["daily"]?["temperature_2m_max"]) as List<dynamic>? ?? [];
    final minTemps =
        (json["daily"]?["temperature_2m_min"]) as List<dynamic>? ?? [];

    final count = [
      dates.length,
      maxTemps.length,
      minTemps.length,
    ].reduce((a, b) => a < b ? a : b);

    List<DailyForecast> list = [];
    for (int i = 0; i < count; i++) {
      list.add(
        DailyForecast(
          date: dates[i].toString(),
          maxTemp: (maxTemps[i] as num).toDouble(),
          minTemp: (minTemps[i] as num).toDouble(),
        ),
      );
    }
    return list;
  }
}

// --- BACKGROUND / ICON HELPERS ---
List<Color> _getBackgroundColors(double temp) {
  if (temp <= 0) return [Colors.blue.shade900, Colors.blue.shade600];
  if (temp <= 10) return [Colors.indigo.shade900, Colors.blueGrey.shade700];
  if (temp <= 20) return [Colors.teal.shade800, Colors.teal.shade400];
  if (temp <= 30) return [Colors.orange.shade700, Colors.orange.shade300];
  return [Colors.red.shade800, Colors.red.shade400];
}

IconData _getIconForTemp(double temp) {
  if (temp <= 0) return Icons.ac_unit;
  if (temp <= 10) return Icons.cloud;
  if (temp <= 20) return Icons.wb_cloudy;
  if (temp <= 30) return Icons.wb_sunny;
  return Icons.whatshot;
}
