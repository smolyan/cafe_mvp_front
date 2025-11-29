import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;

// эти два только для web, но их можно смело подключать
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models/menu_models.dart';

// ==== URL'ы backenda ====
// для Railway:
const String kMenuUrl = 'https://cafemvp-production.up.railway.app/menu';
const String kBusinessLunchUrl =
    'https://cafemvp-production.up.railway.app/business-lunch';

// для локального теста можно временно заменить на:
// const String kMenuUrl = 'http://localhost:8080/menu';
// const String kBusinessLunchUrl = 'http://localhost:8080/business-lunch';

const String kMenuCacheKey = 'menu_cache_json';
const String kBusinessLunchCacheKey = 'business_lunch_cache_json';

void main() {
  runApp(const CafeMvpApp());
}

class CafeMvpApp extends StatelessWidget {
  const CafeMvpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cafe MVP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: null, // системный современный шрифт
      ),
      home: const CafeHomePage(),
    );
  }
}

class PastelTheme {
  final Color background;
  final Color footer;

  const PastelTheme({required this.background, required this.footer});
}

class CafeHomePage extends StatefulWidget {
  const CafeHomePage({super.key});

  @override
  State<CafeHomePage> createState() => _CafeHomePageState();
}

class _CafeHomePageState extends State<CafeHomePage> {
  final PageController _pageController = PageController();

  final List<PastelTheme> _themes = const [
    PastelTheme(background: Color(0xFFF5E9F2), footer: Color(0xFFFFF4FB)),
    PastelTheme(background: Color(0xFFE8F5F5), footer: Color(0xFFF5FEFF)),
    PastelTheme(background: Color(0xFFFDF4E3), footer: Color(0xFFFFFBF1)),
    PastelTheme(background: Color(0xFFEFE9FF), footer: Color(0xFFF8F3FF)),
  ];

  // Акцентные цвета под 4 темы — фиолетовая, оранжевая, зелёная, синяя
  // Используются в пузырьковом фоне.
  final List<Color> _accentColors = const [
    Color(0xFFB388FF), // фиолетовый
    Color(0xFFFFB74D), // оранжевый
    Color(0xFF81C784), // зелёный
    Color(0xFF64B5F6), // синий
  ];

  int _currentThemeIndex = 0;

  // новая переменная: дата меню из menu.json
  String? _menuDate;

  StreamSubscription<AccelerometerEvent>? _accelerometerSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  DateTime _lastShakeTime = DateTime.fromMillisecondsSinceEpoch(0);

  bool _isOnline = true;

  BusinessLunch? _businessLunch;
  List<MenuCategory> _categories = [];

  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _initShakeDetection();
    _initConnectivity();
    _loadData();
  }

  @override
  void dispose() {
    _accelerometerSub?.cancel();
    _connectivitySub?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  // ====== загрузка меню и бизнес-ланча с бэка + кеш ======

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    final prefs = await SharedPreferences.getInstance();

    try {
      final menuResp = await http.get(Uri.parse(kMenuUrl));
      final businessResp = await http.get(Uri.parse(kBusinessLunchUrl));

      if (menuResp.statusCode != 200) {
        throw Exception('Menu status: ${menuResp.statusCode}');
      }
      if (businessResp.statusCode != 200) {
        throw Exception('Business lunch status: ${businessResp.statusCode}');
      }

      final menuJson = jsonDecode(menuResp.body) as Map<String, dynamic>;
      final businessJson =
          jsonDecode(businessResp.body) as Map<String, dynamic>;

      final menu = MenuResponse.fromJson(menuJson);
      final lunch = BusinessLunch.fromJson(businessJson);

      // кешируем исходный JSON
      await prefs.setString(kMenuCacheKey, menuResp.body);
      await prefs.setString(kBusinessLunchCacheKey, businessResp.body);

      setState(() {
        _categories = menu.categories;
        _businessLunch = lunch;
        _menuDate = menu.date; // <<< сохраняем дату из JSON
        _isLoading = false;
        _loadError = null;
      });
    } catch (_) {
      // Не получилось с сети — пробуем кеш
      final cachedMenu = prefs.getString(kMenuCacheKey);
      final cachedLunch = prefs.getString(kBusinessLunchCacheKey);

      if (cachedMenu != null && cachedLunch != null) {
        try {
          final menuJson = jsonDecode(cachedMenu) as Map<String, dynamic>;
          final businessJson = jsonDecode(cachedLunch) as Map<String, dynamic>;

          final menu = MenuResponse.fromJson(menuJson);
          final lunch = BusinessLunch.fromJson(businessJson);

          setState(() {
            _categories = menu.categories;
            _businessLunch = lunch;
            _menuDate = menu.date; // <<< и при загрузке из кеша тоже
            _isLoading = false;
            _loadError = null;
          });
        } catch (_) {
          setState(() {
            _isLoading = false;
            _loadError = 'Не удалось разобрать сохранённое меню';
          });
        }
      } else {
        setState(() {
          _isLoading = false;
          _loadError = 'Не удалось загрузить меню. Проверьте соединение.';
        });
      }
    }
  }

  // ====== shake для смены темы ======

  void _initShakeDetection() {
    const double shakeThreshold = 2.0;
    const int minMillisBetweenShakes = 700;

    _accelerometerSub = accelerometerEventStream().listen((event) {
      final gX = event.x / 9.81;
      final gY = event.y / 9.81;
      final gZ = event.z / 9.81;

      final gForce = sqrt(gX * gX + gY * gY + gZ * gZ);

      if (gForce > shakeThreshold) {
        final now = DateTime.now();
        if (now.difference(_lastShakeTime).inMilliseconds >
            minMillisBetweenShakes) {
          _lastShakeTime = now;
          _onShake();
        }
      }
    });
  }

  void _onShake() {
    setState(() {
      _currentThemeIndex = (_currentThemeIndex + 1) % _themes.length;
    });
  }

  // ====== запрос разрешений на движение (iOS Safari / Яндекс) ======

  Future<void> _requestMotionPermission() async {
    if (!kIsWeb) return;

    try {
      final deviceMotionEvent = js_util.getProperty(
        html.window,
        'DeviceMotionEvent',
      );

      if (deviceMotionEvent != null &&
          js_util.hasProperty(deviceMotionEvent, 'requestPermission')) {
        final result = await js_util.promiseToFuture<String>(
          js_util.callMethod(deviceMotionEvent, 'requestPermission', []),
        );

        debugPrint('Motion permission: $result');
      } else {
        debugPrint('DeviceMotionEvent.requestPermission not available');
      }
    } catch (e) {
      debugPrint('Error requesting motion permission: $e');
    }
  }

  // ====== онлайновость (connectivity_plus 6.x) ======

  void _initConnectivity() async {
    final connectivity = Connectivity();

    final results = await connectivity.checkConnectivity();
    _updateOnlineStatus(results);

    _connectivitySub = connectivity.onConnectivityChanged.listen(
      _updateOnlineStatus,
    );
  }

  void _updateOnlineStatus(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online != _isOnline) {
      setState(() {
        _isOnline = online;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pastel = _themes[_currentThemeIndex];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Фоновый градиент с пузырями
          Positioned.fill(
            child: _BubblesBackground(
              baseColor: pastel.background,
              accentColor: _accentColors[_currentThemeIndex],
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                if (!_isOnline)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    color: Colors.black.withValues(alpha: 0.05),
                    child: Text(
                      'Сейчас вы офлайн — показываем сохранённое меню.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black.withValues(alpha: 0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_menuDate != null) ...[
                            Text(
                              'Меню столовой',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                color: Colors.black.withValues(alpha: 0.75),
                                height: 1.2,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _menuDate!,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w400,
                                color: Colors.black.withValues(alpha: 0.55),
                                letterSpacing: 0.3,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 400,
                            child: _isLoading
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : _loadError != null
                                ? Center(
                                    child: Text(
                                      _loadError!,
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.black.withValues(
                                          alpha: 0.6,
                                        ),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  )
                                : PageView(
                                    controller: _pageController,
                                    children: [
                                      if (_businessLunch != null)
                                        _BusinessLunchCard(
                                          businessLunch: _businessLunch!,
                                        ),
                                      _MenuCard(categories: _categories),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: pastel.footer,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 12,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Text(
                    'Экспериментальное приложение. Возможны ошибки. '
                    'Пожелания и предложения: +7 915 213 93 99',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black.withValues(alpha: 0.65),
                      height: 1.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final List<MenuCategory> categories;

  const _MenuCard({required this.categories});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 760, // можно 800–960, если захочешь потом подправить
        ),
        child: _GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Общее меню',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.black.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _CategoryBlock(category: category),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BusinessLunchCard extends StatelessWidget {
  final BusinessLunch businessLunch;

  const _BusinessLunchCard({super.key, required this.businessLunch});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: _GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Бизнес-ланч',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.black.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Состав:',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 8),
              ...businessLunch.items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '• ',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black.withValues(alpha: 0.7),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          item,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.black.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  '${businessLunch.price} ${businessLunch.currency}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.black.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryBlock extends StatelessWidget {
  final MenuCategory category;

  const _CategoryBlock({required this.category});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          category.name,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 4),
        ...category.dishes.map(
          (dish) => Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    dish.title,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.black.withValues(alpha: 0.8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${dish.price} ${dish.currency}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;

  const _GlassCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 32),
      clipBehavior: Clip.none,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),

        // 🔹 Глубокий стеклянный фон
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.75),
            Colors.white.withValues(alpha: 0.30),
          ],
        ),

        // 🔹 Объёмная, мягкая тень
        boxShadow: [
          // Основная тень снизу
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 28,
            spreadRadius: -4,
            offset: const Offset(0, 8),
          ),

          // Лёгкая подсветка сверху, создаёт глубину
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.6),
            blurRadius: 20,
            spreadRadius: -6,
            offset: const Offset(0, -4),
          ),
        ],

        // Тонкая стеклянная рамка
        border: Border.all(
          width: 1.4,
          color: Colors.white.withValues(alpha: 0.45),
        ),
      ),

      padding: const EdgeInsets.all(20),
      child: child,
    );
  }
}

class _BubblesBackground extends StatefulWidget {
  final Color baseColor;
  final Color accentColor;

  const _BubblesBackground({
    required this.baseColor,
    required this.accentColor,
  });

  @override
  State<_BubblesBackground> createState() => _BubblesBackgroundState();
}

class _BubblesBackgroundState extends State<_BubblesBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10), // было 20, сделаем быстрее
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.baseColor;
    final accentColor = widget.accentColor;

    final lighter = baseColor.withValues(alpha: 0.95);
    final light = baseColor.withValues(alpha: 0.8);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [baseColor, lighter],
            ),
          ),
          child: Stack(
            children: [
              _animatedBubble(
                progress: t,
                phase: 0.0,
                top: -80,
                left: -40,
                size: 260,
                color: light,
              ),
              _animatedBubble(
                progress: t,
                phase: 0.8,
                top: 40,
                right: -60,
                size: 220,
                color: accentColor.withValues(alpha: 0.45),
              ),
              _animatedBubble(
                progress: t,
                phase: 1.6,
                bottom: -60,
                left: -30,
                size: 220,
                color: accentColor.withValues(alpha: 0.55),
              ),
              _animatedBubble(
                progress: t,
                phase: 2.4,
                bottom: -40,
                right: -40,
                size: 260,
                color: accentColor.withValues(alpha: 0.5),
              ),
              _animatedBubble(
                progress: t,
                phase: 3.2,
                top: 140,
                left: 60,
                size: 140,
                color: accentColor.withValues(alpha: 0.4),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _animatedBubble({
    required double progress,
    required double phase,
    double? top,
    double? left,
    double? right,
    double? bottom,
    required double size,
    required Color color,
  }) {
    final wave = math.sin(2 * math.pi * (progress + phase));

    // усилим дыхание
    final scale = 1.0 + 0.12 * wave; // было 0.04
    final offsetShift = 18.0 * wave; // было 6.0

    return Positioned(
      top: top != null ? top + offsetShift : null,
      left: left != null ? left + offsetShift : null,
      right: right != null ? right - offsetShift : null,
      bottom: bottom != null ? bottom - offsetShift : null,
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, color.withValues(alpha: 0.0)],
              center: Alignment.center,
              radius: 0.9,
            ),
          ),
        ),
      ),
    );
  }
}
