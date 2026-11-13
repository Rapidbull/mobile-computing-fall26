import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'firebase_options.dart';
import 'login_screen.dart';
import 'saved_goals.dart';

// All of the app's shared information stays in this one Dart file.
enum LoadStatus { idle, loading, error, empty, data }

class UpcomingRace {
  final int id;
  final String name;
  final String date;
  final String city;
  final String state;
  final String street;
  final String website;

  const UpcomingRace({
    required this.id,
    required this.name,
    required this.date,
    required this.city,
    required this.state,
    required this.street,
    required this.website,
  });

  factory UpcomingRace.fromApi(Map<String, dynamic> item) {
    final race = Map<String, dynamic>.from(item['race'] as Map);
    final address = race['address'] is Map
        ? Map<String, dynamic>.from(race['address'] as Map)
        : <String, dynamic>{};
    return UpcomingRace(
      id: (race['race_id'] as num).toInt(),
      name: (race['name'] ?? 'Unnamed race').toString(),
      date: (race['next_date'] ?? 'Date not announced').toString(),
      city: (address['city'] ?? '').toString(),
      state: (address['state'] ?? '').toString(),
      street: (address['street'] ?? '').toString(),
      website: (race['url'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'date': date,
    'city': city,
    'state': state,
    'street': street,
    'website': website,
  };

  factory UpcomingRace.fromSaved(Map<String, dynamic> map) => UpcomingRace(
    id: (map['id'] as num).toInt(),
    name: map['name'] as String,
    date: map['date'] as String,
    city: map['city'] as String,
    state: map['state'] as String,
    street: map['street'] as String,
    website: map['website'] as String,
  );

  DateTime? get raceDate {
    final parts = date.split('/');
    if (parts.length != 3) return null;
    final month = int.tryParse(parts[0]);
    final day = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (month == null || day == null || year == null) return null;
    return DateTime(year, month, day);
  }

  String get location => [city, state].where((s) => s.isNotEmpty).join(', ');
}

class RaceWeather {
  final String location;
  final double currentTemperature;
  final double currentWind;
  final int currentHumidity;
  final int currentCode;
  final double? raceHigh;
  final double? raceLow;
  final double? raceWind;
  final int? raceRainChance;
  final int? raceCode;

  const RaceWeather({
    required this.location,
    required this.currentTemperature,
    required this.currentWind,
    required this.currentHumidity,
    required this.currentCode,
    this.raceHigh,
    this.raceLow,
    this.raceWind,
    this.raceRainChance,
    this.raceCode,
  });
}

String weatherDescription(int code) {
  if (code == 0) return 'Clear sky';
  if (code <= 3) return 'Partly cloudy';
  if (code <= 48) return 'Foggy';
  if (code <= 67) return 'Rainy';
  if (code <= 77) return 'Snowy';
  if (code <= 82) return 'Rain showers';
  if (code <= 86) return 'Snow showers';
  if (code >= 95) return 'Thunderstorms';
  return 'Mixed weather';
}

class RaceAppModel extends ChangeNotifier {
  static const distanceMeters = <String, double>{
    '5K': 5000,
    '8K': 8000,
    '10K': 10000,
    'Half Marathon': 21097.5,
    'Marathon': 42195,
  };

  // Provider owns everything that more than one screen needs.
  String selectedDistance = '5K';
  double goalSeconds = 0;
  String goalTimeText = '';
  UpcomingRace? selectedRace;
  UpcomingRace? nextRace;
  List<UpcomingRace> races = [];
  LoadStatus racesStatus = LoadStatus.idle;
  LoadStatus weatherStatus = LoadStatus.idle;
  RaceWeather? weather;
  String lastSearchName = '';
  String lastSearchState = 'KY';
  int _raceRequest = 0;
  int _weatherRequest = 0;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _savedRaceSubscription;

  RaceAppModel() {
    // A model exists only for the logged-in user; every change arrives live.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _savedRaceSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('saved')
          .doc('nextRace')
          .snapshots()
          .listen((snapshot) {
            final data = snapshot.data();
            nextRace = data == null ? null : UpcomingRace.fromSaved(data);
            notifyListeners();
          }, onError: (Object e) {
            debugPrint('Could not load saved race from Firestore: $e');
          });
    }
  }

  DocumentReference<Map<String, dynamic>> get _nextRaceDocument {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Please log in to save a race.');
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('saved')
        .doc('nextRace');
  }

  @override
  void dispose() {
    _savedRaceSubscription?.cancel();
    super.dispose();
  }

  void changeDistance(String value) {
    selectedDistance = value;
    notifyListeners();
  }

  void setGoal(String hours, String minutes, String seconds) {
    final h = int.tryParse(hours.trim().isEmpty ? '0' : hours.trim());
    final m = int.tryParse(minutes.trim().isEmpty ? '0' : minutes.trim());
    final s = double.tryParse(seconds.trim().isEmpty ? '0' : seconds.trim());
    if (h == null ||
        m == null ||
        s == null ||
        h < 0 ||
        m < 0 ||
        m >= 60 ||
        s < 0 ||
        s >= 60 ||
        (h == 0 && m == 0 && s == 0)) {
      throw const FormatException(
        'Enter a valid time (minutes and seconds under 60).',
      );
    }
    goalSeconds = h * 3600 + m * 60 + s;
    goalTimeText = formatTime(goalSeconds);
    notifyListeners();
  }

  void chooseRace(UpcomingRace race) {
    selectedRace = race;
    weather = null;
    weatherStatus = LoadStatus.idle;
    _weatherRequest++;
    notifyListeners();
  }

  Future<void> saveNextRace() async {
    final race = selectedRace;
    if (race == null) return;
    await _nextRaceDocument.set(race.toJson());
    // Listener above updates nextRace and the home screen.
  }

  Future<void> clearNextRace() async {
    await _nextRaceDocument.delete();
  }

  Future<void> loadRaces({String? name, String? state}) async {
    if (name != null) lastSearchName = name.trim();
    if (state != null) lastSearchState = state.trim().toUpperCase();
    final request = ++_raceRequest;
    racesStatus = LoadStatus.loading;
    notifyListeners();

    final query = <String, String>{
      'format': 'json',
      'results_per_page': '50',
      'sort': 'date ASC',
      'start_date': 'today',
    };
    if (lastSearchName.isNotEmpty) query['name'] = lastSearchName;
    if (lastSearchState.isNotEmpty) query['state'] = lastSearchState;

    try {
      final uri = Uri.https('api.runsignup.com', '/rest/races', query);
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('RunSignup returned ${response.statusCode}');
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body.containsKey('error'))
        throw Exception('RunSignup returned an error');
      final items = body['races'] as List<dynamic>? ?? [];
      final parsed = items
          .map(
            (item) =>
                UpcomingRace.fromApi(Map<String, dynamic>.from(item as Map)),
          )
          .toList();
      if (request != _raceRequest) return;
      races = parsed;
      racesStatus = races.isEmpty ? LoadStatus.empty : LoadStatus.data;
    } catch (e) {
      debugPrint('Race API error: $e');
      if (request != _raceRequest) return;
      racesStatus = LoadStatus.error;
    }
    notifyListeners();
  }

  Future<void> loadWeather() async {
    final race = selectedRace;
    if (race == null) return;
    final request = ++_weatherRequest;
    weather = null;
    weatherStatus = LoadStatus.loading;
    notifyListeners();
    try {
      if (race.city.trim().isEmpty) {
        if (request == _weatherRequest) weatherStatus = LoadStatus.empty;
        notifyListeners();
        return;
      }

      // Geocoding provides city-level coordinates, NOT the exact course route.
      Future<List<dynamic>> geocode(String name) async {
        final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
          'name': name,
          'count': '1',
          'countryCode': 'US',
        });
        final response = await http
            .get(uri)
            .timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) throw Exception('Geocoding failed');
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['results'] as List<dynamic>? ?? [];
      }

      var places = await geocode('${race.city}, ${race.state}');
      if (places.isEmpty) places = await geocode(race.city);
      if (request != _weatherRequest) return;
      if (places.isEmpty) {
        weatherStatus = LoadStatus.empty;
        notifyListeners();
        return;
      }
      final place = Map<String, dynamic>.from(places.first as Map);
      final latitude = (place['latitude'] as num).toString();
      final longitude = (place['longitude'] as num).toString();
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': latitude,
        'longitude': longitude,
        'current':
            'temperature_2m,wind_speed_10m,relative_humidity_2m,weather_code',
        'daily': 'temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max,weather_code',
        'temperature_unit': 'fahrenheit',
        'wind_speed_unit': 'mph',
        'timezone': 'auto',
        'forecast_days': '16',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw Exception('Weather request failed');
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final current = Map<String, dynamic>.from(json['current'] as Map);
      final daily = Map<String, dynamic>.from(json['daily'] as Map);
      final dates = (daily['time'] as List<dynamic>).cast<String>();
      final date = race.raceDate;
      final index = date == null
          ? -1
          : dates.indexOf(
              '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
            );

      double? dailyNumber(String key) => index < 0
          ? null
          : ((daily[key] as List<dynamic>)[index] as num?)?.toDouble();

      int? dailyInt(String key) => index < 0
          ? null
          : ((daily[key] as List<dynamic>)[index] as num?)?.round();

      final result = RaceWeather(
        location: '${place['name']}, ${place['admin1'] ?? race.state}',
        currentTemperature: (current['temperature_2m'] as num).toDouble(),
        currentWind: (current['wind_speed_10m'] as num).toDouble(),
        currentHumidity: (current['relative_humidity_2m'] as num).round(),
        currentCode: (current['weather_code'] as num).round(),
        raceHigh: dailyNumber('temperature_2m_max'),
        raceLow: dailyNumber('temperature_2m_min'),
        raceWind: dailyNumber('wind_speed_10m_max'),
        raceRainChance: dailyInt('precipitation_probability_max'),
        raceCode: dailyInt('weather_code'),
      );
      if (request != _weatherRequest) return;
      weather = result;
      weatherStatus = LoadStatus.data;
    } catch (e) {
      debugPrint('Weather API error: $e');
      if (request != _weatherRequest) return;
      weatherStatus = LoadStatus.error;
    }
    notifyListeners();
  }
}

String formatTime(double seconds) {
  final totalHundredths = (seconds * 100).round();
  final hours = totalHundredths ~/ 360000;
  final minutes = (totalHundredths ~/ 6000) % 60;
  final secs = (totalHundredths ~/ 100) % 60;
  final hundredths = totalHundredths % 100;
  final rest =
      '${secs.toString().padLeft(2, '0')}.${hundredths.toString().padLeft(2, '0')}';
  if (hours > 0) return '$hours:${minutes.toString().padLeft(2, '0')}:$rest';
  return '$minutes:$rest';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Keep the provider ABOVE MaterialApp, so Navigator-pushed screens
    // (including ResultsScreen and RaceDetailsScreen) can access it.
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final user = snapshot.data;
        final Widget home;
        if (snapshot.connectionState == ConnectionState.waiting) {
          home = const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        } else if (snapshot.hasError) {
          home = const Scaffold(
            body: Center(
              child: Text('Could not check login. Check your connection.'),
            ),
          );
        } else if (user == null) {
          home = const LoginScreen();
        } else {
          home = const HomeScreen();
        }

        final app = MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Race Splits',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
            useMaterial3: true,
          ),
          home: home,
        );

        // Creating a fresh provider per UID also prevents data from one
        // signed-in account carrying over to another.
        if (user == null ||
            snapshot.connectionState == ConnectionState.waiting ||
            snapshot.hasError) {
          return app;
        }
        return ChangeNotifierProvider<RaceAppModel>(
          key: ValueKey(user.uid),
          create: (_) => RaceAppModel(),
          child: app,
        );
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final hours = TextEditingController();
  final minutes = TextEditingController();
  final seconds = TextEditingController();

  @override
  void dispose() {
    hours.dispose();
    minutes.dispose();
    seconds.dispose();
    super.dispose();
  }

  void _calculate() {
    try {
      context.read<RaceAppModel>().setGoal(
        hours.text,
        minutes.text,
        seconds.text,
      );
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ResultsScreen()),
      );
    } on FormatException catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<RaceAppModel>();
    final race = model.nextRace;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Race Splits'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              // Remove signed-in routes before changing the auth state.
              Navigator.of(context).popUntil((route) => route.isFirst);
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.directions_run, size: 70, color: Colors.blue),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Hit your splits',
              style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Choose a race distance and enter your goal time.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 25),
          DropdownButtonFormField<String>(
            value: model.selectedDistance,
            decoration: const InputDecoration(
              labelText: 'Race distance',
              prefixIcon: Icon(Icons.flag),
              border: OutlineInputBorder(),
            ),
            items: RaceAppModel.distanceMeters.keys
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
            onChanged: (value) {
              if (value != null)
                context.read<RaceAppModel>().changeDistance(value);
            },
          ),
          const SizedBox(height: 20),
          const Text(
            'Goal time',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _timeField(hours, 'Hours')),
              const SizedBox(width: 8),
              Expanded(child: _timeField(minutes, 'Minutes')),
              const SizedBox(width: 8),
              Expanded(child: _timeField(seconds, 'Seconds')),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _calculate,
              icon: const Icon(Icons.calculate),
              label: const Text('Calculate Splits'),
            ),
          ),
          const SizedBox(height: 25),
          const Divider(),
          const SavedGoalsSection(),
          const SizedBox(height: 20),
          const Divider(),
          const Text(
            'My Next Race',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (race == null)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'No next race saved yet. Find a race to get started.',
                ),
              ),
            )
          else
            Card(
              child: ListTile(
                leading: const Icon(Icons.event_available, color: Colors.blue),
                title: Text(race.name),
                subtitle: Text('${race.date}  •  ${race.location}'),
                onTap: () {
                  context.read<RaceAppModel>().chooseRace(race);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RaceDetailsScreen(),
                    ),
                  );
                },
                trailing: IconButton(
                  tooltip: 'Remove saved race',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    try {
                      await context.read<RaceAppModel>().clearNextRace();
                    } catch (_) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Could not remove race. Try again.')),
                      );
                    }
                  },
                ),
              ),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('Find a Race'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FindRaceScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      );
}

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<RaceAppModel>();
    final distance = RaceAppModel.distanceMeters[model.selectedDistance]!;
    final total = model.goalSeconds;
    final pace = total / (distance / 1000);
    final rows = <Widget>[];
    var previous = 0.0;
    for (var meters = 1000.0; meters < distance; meters += 1000) {
      final elapsed = total * meters / distance;
      rows.add(
        ListTile(
          title: Text('${(meters / 1000).toInt()} km'),
          subtitle: Text('Split: ${formatTime(elapsed - previous)}'),
          trailing: Text(formatTime(elapsed)),
        ),
      );
      previous = elapsed;
    }
    rows.add(
      ListTile(
        title: const Text(
          'Finish',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('Final segment: ${formatTime(total - previous)}'),
        trailing: Text(
          formatTime(total),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Your Race Splits')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Icon(Icons.timer, size: 64, color: Colors.blue),
          Center(
            child: Text(
              model.selectedDistance,
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
            ),
          ),
          Center(
            child: Text(
              model.goalTimeText,
              style: const TextStyle(fontSize: 30),
            ),
          ),
          Center(child: Text('Average pace: ${formatTime(pace)} / km')),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Save Goal to Cloud'),
            onPressed: () async {
              try {
                await saveSplitGoal(
                  distance: model.selectedDistance,
                  goalSeconds: model.goalSeconds,
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Split goal saved to your account!')),
                );
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not save goal. Check your connection.')),
                );
              }
            },
          ),
          const SizedBox(height: 18),
          const Text(
            'Even-pace targets',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
          ),
          ...rows,
        ],
      ),
    );
  }
}

class FindRaceScreen extends StatefulWidget {
  const FindRaceScreen({super.key});

  @override
  State<FindRaceScreen> createState() => _FindRaceScreenState();
}

class _FindRaceScreenState extends State<FindRaceScreen> {
  final name = TextEditingController();
  final state = TextEditingController(text: 'KY');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<RaceAppModel>().loadRaces();
    });
  }

  @override
  void dispose() {
    name.dispose();
    state.dispose();
    super.dispose();
  }

  void _search() {
    FocusScope.of(context).unfocus();
    context.read<RaceAppModel>().loadRaces(name: name.text, state: state.text);
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<RaceAppModel>();
    return Scaffold(
      appBar: AppBar(title: const Text('Find a Race')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Race name (optional)',
                    hintText: 'Turkey Trot, Half Marathon...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: state,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'State (e.g. KY)',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _search(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: _search,
                      child: const Text('Search'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(child: _buildResults(context, model)),
        ],
      ),
    );
  }

  Widget _buildResults(BuildContext context, RaceAppModel model) {
    if (model.racesStatus == LoadStatus.loading ||
        model.racesStatus == LoadStatus.idle) {
      return const Center(child: CircularProgressIndicator());
    }
    if (model.racesStatus == LoadStatus.error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, color: Colors.grey, size: 52),
            const SizedBox(height: 12),
            const Text('Could not load races. Check your connection.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.read<RaceAppModel>().loadRaces(),
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    if (model.racesStatus == LoadStatus.empty) {
      return RefreshIndicator(
        onRefresh: () => context.read<RaceAppModel>().loadRaces(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 130),
            Icon(Icons.search_off, size: 50, color: Colors.grey),
            SizedBox(height: 12),
            Center(child: Text('No races found. Try another search.')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => context.read<RaceAppModel>().loadRaces(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: model.races.length,
        itemBuilder: (context, index) {
          final race = model.races[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: ListTile(
              leading: const Icon(Icons.flag_outlined, color: Colors.blue),
              title: Text(race.name),
              subtitle: Text('${race.date}  •  ${race.location}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                context.read<RaceAppModel>().chooseRace(race);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RaceDetailsScreen()),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class RaceDetailsScreen extends StatefulWidget {
  const RaceDetailsScreen({super.key});

  @override
  State<RaceDetailsScreen> createState() => _RaceDetailsScreenState();
}

class _RaceDetailsScreenState extends State<RaceDetailsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<RaceAppModel>().loadWeather();
    });
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<RaceAppModel>();
    final race = model.selectedRace;
    if (race == null) {
      return const Scaffold(body: Center(child: Text('Choose a race first.')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Race Details & Weather')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            race.name,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ListTile(leading: const Icon(Icons.event), title: Text(race.date)),
          ListTile(
            leading: const Icon(Icons.place),
            title: Text(
              race.location.isEmpty ? 'Location unavailable' : race.location,
            ),
            subtitle: race.street.isEmpty ? null : Text(race.street),
          ),
          if (race.website.startsWith('https://'))
            OutlinedButton.icon(
              icon: const Icon(Icons.route),
              label: const Text('Race Website / Course Information'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RaceWebsiteScreen()),
              ),
            ),
          const Text(
            'Course routes are not always available from RunSignup. Weather is estimated for the race city, not the exact course.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const Divider(height: 30),
          const Text(
            'Weather',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _weatherContent(context, model),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.bookmark_add),
            label: Text(
              model.nextRace?.id == race.id
                  ? 'Save Again as Next Race'
                  : 'Save as Next Race',
            ),
            onPressed: () async {
              try {
                await context.read<RaceAppModel>().saveNextRace();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Saved! This race is now on your Home screen.',
                    ),
                  ),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Could not save race to the cloud. Check your connection.'),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _weatherContent(BuildContext context, RaceAppModel model) {
    switch (model.weatherStatus) {
      case LoadStatus.idle:
      case LoadStatus.loading:
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(30),
            child: CircularProgressIndicator(),
          ),
        );
      case LoadStatus.error:
        return Column(
          children: [
            const Icon(Icons.wifi_off, color: Colors.grey, size: 44),
            const Text('Unable to load weather. Check your connection.'),
            TextButton(
              onPressed: () => context.read<RaceAppModel>().loadWeather(),
              child: const Text('Try again'),
            ),
          ],
        );
      case LoadStatus.empty:
        return Column(
          children: [
            const Text('No weather location could be found for this race.'),
            TextButton(
              onPressed: () => context.read<RaceAppModel>().loadWeather(),
              child: const Text('Try again'),
            ),
          ],
        );
      case LoadStatus.data:
        final w = model.weather!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current weather near ${w.location}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${w.currentTemperature.toStringAsFixed(0)}°F • ${weatherDescription(w.currentCode)}',
                      style: const TextStyle(fontSize: 21),
                    ),
                    Text(
                      'Wind: ${w.currentWind.toStringAsFixed(0)} mph  •  Humidity: ${w.currentHumidity}%',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Race-day forecast',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (w.raceHigh == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No forecast for this date yet. Open-Meteo forecasts up to 16 days ahead; check again closer to race day.',
                ),
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${weatherDescription(w.raceCode ?? 0)} • High ${w.raceHigh!.toStringAsFixed(0)}°F / Low ${w.raceLow?.toStringAsFixed(0) ?? '?'}°F',
                      ),
                      Text('Chance of rain: ${w.raceRainChance ?? 0}%'),
                      Text(
                        'Maximum wind: ${w.raceWind?.toStringAsFixed(0) ?? '?'} mph',
                      ),
                    ],
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => context.read<RaceAppModel>().loadWeather(),
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh weather'),
              ),
            ),
          ],
        );
    }
  }
}

class RaceWebsiteScreen extends StatefulWidget {
  const RaceWebsiteScreen({super.key});

  @override
  State<RaceWebsiteScreen> createState() => _RaceWebsiteScreenState();
}

class _RaceWebsiteScreenState extends State<RaceWebsiteScreen> {
  late final WebViewController controller;

  @override
  void initState() {
    super.initState();
    final url = context.read<RaceAppModel>().selectedRace?.website ?? '';
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
    final uri = Uri.tryParse(url);
    if (uri != null && uri.scheme == 'https') {
      controller.loadRequest(uri);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Race Website'),
      actions: [
        IconButton(
          tooltip: 'Reload',
          icon: const Icon(Icons.refresh),
          onPressed: () => controller.reload(),
        ),
      ],
    ),
    body: WebViewWidget(controller: controller),
  );
}
