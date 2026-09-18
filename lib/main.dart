import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import 'video_source.dart';

const bg = Color(0xfff8fafc);
const cyan = Color(0xff38bdf8);
const violet = Color(0xff2563eb);
const gold = Color(0xff10b981);
const ink = Color(0xff0f172a);
const mutedInk = Color(0xff64748b);
const olive = Color(0xff10b981);
const emerald = Color(0xff10b981);
const burgundy = Color(0xff2563eb);
const loginTeal = Color(0xff0f9f95);
const loginAqua = Color(0xff2dd4bf);
const isProductionBuild = bool.fromEnvironment('dart.vm.product');
const configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');
const apiBaseUrl = configuredApiBaseUrl != ''
    ? configuredApiBaseUrl
    : (isProductionBuild ? '' : 'http://127.0.0.1:8000');

void validateApiBaseUrl() {
  if (apiBaseUrl.isEmpty) {
    throw StateError('API_BASE_URL is required for production builds.');
  }
  final parsed = Uri.tryParse(apiBaseUrl);
  if (parsed == null || parsed.host.isEmpty || !{'http', 'https'}.contains(parsed.scheme)) {
    throw StateError('API_BASE_URL must be a valid HTTP(S) URL.');
  }
  if (isProductionBuild && parsed.scheme != 'https') {
    throw StateError('Production API_BASE_URL must use HTTPS.');
  }
}

class TheodoreApi {
  static Future<String> _token() async => (await SharedPreferences.getInstance()).getString('theodore_access_token') ?? '';

  static Future<dynamic> adminGet(String path) async {
    final response = await http.get(Uri.parse('$apiBaseUrl$path'), headers: {'Authorization': 'Bearer ${await _token()}'}).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception('request_failed');
    return jsonDecode(response.body);
  }

  static Future<dynamic> adminPut(String path, Map<String, dynamic> body) async {
    final response = await http.put(Uri.parse('$apiBaseUrl$path'), headers: {'Authorization': 'Bearer ${await _token()}', 'Content-Type': 'application/json'}, body: jsonEncode(body)).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception('request_failed');
    return jsonDecode(response.body);
  }

  static Future<void> adminDelete(String path) async {
    final response = await http.delete(Uri.parse('$apiBaseUrl$path'), headers: {'Authorization': 'Bearer ${await _token()}'}).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception('request_failed');
  }

  static Future<List<dynamic>> authenticatedGet(String path) async {
    final response = await http.get(Uri.parse('$apiBaseUrl$path'), headers: {'Authorization': 'Bearer ${await _token()}'}).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception('request_failed');
    return jsonDecode(response.body) as List<dynamic>;
  }

  static Future<String> signedVideoUrl(int videoId) async {
    final response = await http.get(Uri.parse('$apiBaseUrl/videos/$videoId/url'), headers: {'Authorization': 'Bearer ${await _token()}'}).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception('video_access_denied');
    return (jsonDecode(response.body) as Map<String, dynamic>)['url'] as String;
  }

  static Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/auth/login'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'username': username, 'password': password},
    ).timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) throw Exception('login_failed');
    final token = jsonDecode(response.body) as Map<String, dynamic>;
    final me = await http.get(Uri.parse('$apiBaseUrl/auth/me'), headers: {'Authorization': 'Bearer ${token['access_token']}'}).timeout(const Duration(seconds: 6));
    if (me.statusCode != 200) throw Exception('profile_failed');
    return {...token, 'user': jsonDecode(me.body)};
  }

  static Future<Map<String, dynamic>> register({required String username, required String password}) async {
    final response = await http.post(Uri.parse('$apiBaseUrl/auth/register'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'username': username, 'password': password})).timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) throw Exception('register_failed');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}

class MillionSoundEffects {
  static Uint8List tone({
    required List<double> frequencies,
    required int durationMs,
    double volume = .18,
  }) {
    const sampleRate = 22050;
    final sampleCount = (sampleRate * durationMs / 1000).round();
    final bytes = Uint8List(44 + sampleCount * 2);
    final data = ByteData.sublistView(bytes);
    void writeAscii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes[offset + i] = value.codeUnitAt(i);
      }
    }

    writeAscii(0, 'RIFF');
    data.setUint32(4, bytes.length - 8, Endian.little);
    writeAscii(8, 'WAVEfmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    writeAscii(36, 'data');
    data.setUint32(40, sampleCount * 2, Endian.little);

    for (var i = 0; i < sampleCount; i++) {
      final progress = i / sampleCount;
      final frequency = frequencies[(progress * frequencies.length).floor().clamp(0, frequencies.length - 1).toInt()];
      final envelope = math.min(1, i / (sampleRate * .012)) * math.min(1, (sampleCount - i) / (sampleRate * .045));
      final sample = (math.sin(2 * math.pi * frequency * i / sampleRate) * volume * envelope * 32767).round();
      data.setInt16(44 + i * 2, sample, Endian.little);
    }
    return bytes;
  }

  static final correct = tone(frequencies: [523.25, 659.25, 783.99], durationMs: 230);
  static final wrong = tone(frequencies: [311.13, 233.08], durationMs: 280, volume: .16);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  validateApiBaseUrl();
  runApp(const App());
  unawaited(loadVideoCatalog());
}

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  Timer? syncTimer;

  @override
  void initState() {
    super.initState();
    syncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      loadVideoCatalog();
    });
  }

  @override
  void dispose() {
    syncTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ثيودور لابز',
      locale: const Locale('ar', 'IQ'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('ar', 'IQ'), Locale('en', 'US')],
      theme: ThemeData.light(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: emerald,
          brightness: Brightness.light,
          primary: emerald,
          secondary: olive,
          tertiary: cyan,
          surface: Colors.white,
          onSurface: ink,
        ),
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: ink,
          displayColor: ink,
          fontFamily: 'Arial',
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          labelStyle: const TextStyle(color: mutedInk),
          hintStyle: const TextStyle(color: mutedInk),
          prefixIconColor: emerald,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xffe2e8f0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xffe2e8f0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: emerald, width: 2),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: burgundy,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: ink,
          contentTextStyle: TextStyle(color: Colors.white),
        ),
      ),
      home: const LoginPage(),
    );
  }
}

class Shell extends StatelessWidget {
  final Widget child;
  final bool showBack;
  const Shell({required this.child, this.showBack = true, super.key});
  @override
  Widget build(BuildContext context) {
    final canGoBack = Navigator.canPop(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xffeff6ff), bg, Color(0xffecfdf5)],
          ),
        ),
        child: Column(
          children: [
            if (canGoBack && showBack)
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'رجوع',
                        onPressed: () => Navigator.maybePop(context),
                        icon: const BackButtonIcon(),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: emerald,
                          side: const BorderSide(color: Color(0xffe2e8f0)),
                          minimumSize: const Size(46, 46),
                        ),
                      ),
                      const Spacer(),
                      const TheodoreBrand(size: 48, compact: true),
                    ],
                  ),
                ),
              ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class LaunchPage extends StatefulWidget {
  const LaunchPage({super.key});

  @override
  State<LaunchPage> createState() => _LaunchPageState();
}

class TheodoreBrand extends StatelessWidget {
  final double size;
  final bool compact;
  final bool teal;
  final bool showName;
  const TheodoreBrand({
    this.size = 150,
    this.compact = false,
    this.teal = false,
    this.showName = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Image.asset(
        '67.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    ],
  );
}

class _LaunchPageState extends State<LaunchPage> {
  final PageController pageController = PageController();
  int currentPage = 0;

  static const onboardingPages = [
    (
      'المدرسة',
      'تعلم منظم يبدأ من هنا',
      'دروس تفاعلية ومسارات واضحة تساعدك على بناء مهاراتك بثقة.',
      'https://images.unsplash.com/photo-1503676260728-1c00da094a0b?auto=format&fit=crop&w=1200&q=85',
      Icons.school,
      olive,
    ),
    (
      'البرمجة',
      'حوّل أفكارك إلى مشاريع',
      'بيئة عملية لتعلم البرمجة، تطوير الحلول، وصناعة منتجات رقمية حقيقية.',
      'https://images.unsplash.com/photo-1516321318423-f06f85e504b3?auto=format&fit=crop&w=1200&q=85',
      Icons.code,
      emerald,
    ),
    (
      'المكتبة',
      'معرفة موثوقة في مكان واحد',
      'اكتشف الكتب والمراجع المختارة، وابنِ عادة قراءة تدعم تطورك المستمر.',
      'https://images.unsplash.com/photo-1521587760476-6c12a4b040da?auto=format&fit=crop&w=1200&q=85',
      Icons.menu_book,
      Color(0xff3f7568),
    ),
    (
      'ثيودور لابز',
      'منصة واحدة لنموك',
      'تعلم، ابتكر، تابع صحتك، وشارك المعرفة ضمن تجربة تقنية متكاملة.',
      'https://images.unsplash.com/photo-1519389950473-47ba0277781c?auto=format&fit=crop&w=1200&q=85',
      Icons.biotech,
      burgundy,
    ),
  ];

  @override
  void dispose() {
    pageController.dispose();
    super.dispose();
  }

  void nextPage() {
    if (currentPage == onboardingPages.length - 1) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
      return;
    }
    pageController.nextPage(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: bg,
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: pageController,
              itemCount: onboardingPages.length,
              onPageChanged: (page) => setState(() => currentPage = page),
              itemBuilder: (context, index) => _OnboardingSlide(
                page: onboardingPages[index],
                isLast: index == onboardingPages.length - 1,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Row(
              children: [
                Row(
                  children: List.generate(
                    onboardingPages.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsetsDirectional.only(end: 6),
                      width: index == currentPage ? 28 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: index == currentPage ? burgundy : const Color(0xffcbd6cf),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: nextPage,
                  icon: Icon(
                    currentPage == onboardingPages.length - 1
                        ? Icons.arrow_forward
                        : Icons.chevron_left,
                  ),
                  label: Text(
                    currentPage == onboardingPages.length - 1
                        ? 'ابدأ الآن'
                        : 'التالي',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _OnboardingSlide extends StatelessWidget {
  final (String, String, String, String, IconData, Color) page;
  final bool isLast;
  const _OnboardingSlide({required this.page, required this.isLast});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TheodoreBrand(size: isLast ? 74 : 58, compact: true),
            ),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: AspectRatio(
                aspectRatio: 1.55,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      page.$4,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: page.$6.withValues(alpha: .12),
                        child: Icon(page.$5, size: 90, color: page.$6),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, ink.withValues(alpha: .72)],
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      start: 18,
                      bottom: 18,
                      child: CircleAvatar(
                        radius: 25,
                        backgroundColor: page.$6,
                        child: Icon(page.$5, color: Colors.white, size: 27),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 26),
            Text(
              page.$1,
              style: TextStyle(color: page.$6, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              page.$2,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 29, fontWeight: FontWeight.bold, height: 1.2),
            ),
            const SizedBox(height: 12),
            Text(
              page.$3,
              textAlign: TextAlign.center,
              style: const TextStyle(color: mutedInk, fontSize: 16, height: 1.6),
            ),
          ],
        ),
      ),
    ),
  );
}

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const Panel({required this.child, this.padding = const EdgeInsets.all(18), super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .92),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xffdfe7e1)),
      boxShadow: const [
        BoxShadow(color: Color(0x120d3b2e), blurRadius: 22, offset: Offset(0, 8)),
      ],
    ),
    child: Material(color: Colors.transparent, child: child),
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool busy = false;
  bool loadingAccounts = true;
  bool creatingAccount = false;
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final firstNameController = TextEditingController();
  final secondNameController = TextEditingController();
  final emailController = TextEditingController();
  final birthDateController = TextEditingController();
  List<Map<String, dynamic>> accounts = [];
  static const arabicMonths = [
    'كانون الثاني',
    'شباط',
    'آذار',
    'نيسان',
    'أيار',
    'حزيران',
    'تموز',
    'آب',
    'أيلول',
    'تشرين الأول',
    'تشرين الثاني',
    'كانون الأول',
  ];

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    String? saved;
    try {
      final preferences = await SharedPreferences.getInstance();
      saved = preferences.getString('local_accounts');
    } catch (_) {
      saved = null;
    }
    if (!mounted) return;
    setState(() {
        accounts = saved == null
          ? []
          : List<Map<String, dynamic>>.from(jsonDecode(saved)).map((account) {
            final sanitized = Map<String, dynamic>.from(account);
            sanitized.remove('password');
            return sanitized;
          }).toList();
      loadingAccounts = false;
    });
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    firstNameController.dispose();
    secondNameController.dispose();
    emailController.dispose();
    birthDateController.dispose();
    super.dispose();
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> enter() async {
    final username = usernameController.text.trim();
    final password = passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      showMessage('اكتب اسم المستخدم وكلمة المرور أولًا');
      return;
    }
    setState(() => busy = true);
    var isManager = false;
    var role = 'user';
    try {
      final result = await TheodoreApi.login(username, password);
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('theodore_access_token', result['access_token'] as String);
      role = (result['user'] as Map<String, dynamic>)['role'] as String? ?? 'user';
      isManager = role == 'superadmin';
    } catch (_) {
      setState(() => busy = false);
      showMessage('تعذر الاتصال بالسيرفر أو بيانات الدخول غير صحيحة');
      return;
    }
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('million_current_user', username.toLowerCase());
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomePage(isManager: isManager, role: role)),
      );
    }
  }

  Future<void> createAccount() async {
    final username = usernameController.text.trim();
    final normalizedUsername = username.toLowerCase();
    final email = emailController.text.trim().toLowerCase();
    final password = passwordController.text;
    final confirmation = confirmPasswordController.text;
    if (firstNameController.text.trim().isEmpty ||
        secondNameController.text.trim().isEmpty ||
        emailController.text.trim().isEmpty ||
        birthDateController.text.isEmpty ||
        username.isEmpty ||
        password.isEmpty ||
        confirmation.isEmpty) {
      showMessage('أكمل جميع حقول إنشاء الحساب');
      return;
    }
    if (username == '1') {
      showMessage('اسم المستخدم 1 محجوز للمدير');
      return;
    }
    if (password != confirmation) {
      showMessage('كلمة المرور وإعادة كتابتها غير متطابقتين');
      return;
    }
    if (accounts.any(
      (account) =>
          account['username'].toString().toLowerCase() == normalizedUsername ||
          account['email'].toString().toLowerCase() == email,
    )) {
      showMessage('اسم المستخدم مستخدم من قبل، اختر اسمًا آخر');
      return;
    }
    if (password.length < 8) {
      showMessage('كلمة المرور يجب أن تحتوي على 8 رموز على الأقل للحماية');
      return;
    }
    try {
      await TheodoreApi.register(username: normalizedUsername, password: password);
    } catch (_) {
      showMessage('تعذر إنشاء الحساب على السيرفر، حاول مرة أخرى');
      return;
    }
    final newAccount = {
      'username': normalizedUsername,
      'firstName': firstNameController.text.trim(),
      'secondName': secondNameController.text.trim(),
      'email': email,
      'birthDate': birthDateController.text,
    };
    final updatedAccounts = [...accounts, newAccount];
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('local_accounts', jsonEncode(updatedAccounts));
    } catch (_) {
      // Keep the account available for the current session if storage is unavailable.
    }
    if (!mounted) return;
    setState(() {
      accounts = updatedAccounts;
      creatingAccount = false;
      passwordController.clear();
      confirmPasswordController.clear();
    });
    showMessage('تم إنشاء الحساب. استخدم اسم المستخدم وكلمة المرور للدخول');
  }

  @override
  Widget build(BuildContext context) => Shell(
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            children: [
              const TheodoreBrand(size: 92, compact: true, teal: true),
              const SizedBox(height: 12),
              Text(
                creatingAccount ? 'أنشئ حسابك التعليمي' : 'مرحبًا بعودتك في تطبيق',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              if (!creatingAccount) ...[
                const SizedBox(height: 7),
                const Directionality(
                  textDirection: TextDirection.rtl,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'ثيودور',
                        style: TextStyle(
                          color: ink,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.apple, color: Color(0xffa8b0bb), size: 25),
                      SizedBox(width: 8),
                      Text(
                        '(Theodore)',
                        style: TextStyle(
                          color: ink,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                creatingAccount
                    ? 'ابدأ رحلتك التعليمية بخطوة بسيطة'
                    : 'سجّل دخولك وتابع تقدمك بثقة',
                textAlign: TextAlign.center,
                style: const TextStyle(color: mutedInk, fontSize: 15),
              ),
              const SizedBox(height: 24),
              Panel(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: creatingAccount
                      ? _buildCreateAccountForm()
                      : _buildLoginForm(),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildLoginForm() => Column(
    key: const ValueKey('login'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: usernameController,
        decoration: InputDecoration(
          labelText: 'اسم المستخدم',
          prefixIcon: Icon(Icons.person_outline),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: passwordController,
        obscureText: true,
        decoration: InputDecoration(
          labelText: 'كلمة المرور',
          prefixIcon: Icon(Icons.lock_outline),
        ),
      ),
      const SizedBox(height: 20),
      SizedBox(
        height: 52,
        child: FilledButton.icon(
          onPressed: busy ? null : enter,
          style: FilledButton.styleFrom(
            backgroundColor: loginTeal,
            foregroundColor: Colors.white,
            shadowColor: loginTeal.withValues(alpha: .3),
            elevation: 3,
          ),
          icon: const Icon(Icons.login_rounded),
          label: const Text('تسجيل دخول'),
        ),
      ),
      const SizedBox(height: 14),
      Center(
        child: TextButton.icon(
          onPressed: () => setState(() => creatingAccount = true),
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 19),
          label: const Text('إنشاء حساب'),
        ),
      ),
    ],
  );

  Widget _buildCreateAccountForm() => Column(
    key: const ValueKey('create-account'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          IconButton(
            tooltip: 'العودة إلى تسجيل الدخول',
            onPressed: () => setState(() => creatingAccount = false),
            icon: const Icon(Icons.arrow_forward_rounded),
            color: emerald,
          ),
          const Expanded(
            child: Text(
              'بيانات الحساب',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        controller: usernameController,
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          labelText: 'اسم المستخدم',
          prefixIcon: Icon(Icons.alternate_email_rounded),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: passwordController,
        obscureText: true,
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          labelText: 'كلمة المرور',
          prefixIcon: Icon(Icons.lock_outline),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: confirmPasswordController,
        obscureText: true,
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          labelText: 'إعادة كتابة كلمة المرور',
          prefixIcon: Icon(Icons.lock_reset_rounded),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: firstNameController,
        decoration: InputDecoration(
          labelText: 'الاسم الأول',
          prefixIcon: Icon(Icons.person_outline),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: secondNameController,
        decoration: InputDecoration(
          labelText: 'الاسم الثاني',
          prefixIcon: Icon(Icons.badge_outlined),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: emailController,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(
          labelText: 'البريد الإلكتروني',
          prefixIcon: Icon(Icons.email_outlined),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: birthDateController,
        readOnly: true,
        onTap: () async {
          final date = await showDatePicker(
            context: context,
            locale: const Locale('ar', 'IQ'),
            firstDate: DateTime(1940),
            lastDate: DateTime.now(),
            initialDate: DateTime(2010),
            builder: (context, child) => Theme(
              data: Theme.of(context).copyWith(
                colorScheme: Theme.of(context).colorScheme.copyWith(primary: emerald),
              ),
              child: child!,
            ),
          );
          if (date != null) {
            birthDateController.text =
                '${date.day} ${arabicMonths[date.month - 1]} ${date.year}';
          }
        },
        decoration: const InputDecoration(
          labelText: 'تاريخ الميلاد (اليوم / الشهر / السنة)',
          prefixIcon: Icon(Icons.calendar_month_outlined),
          suffixIcon: Icon(Icons.expand_more_rounded),
        ),
      ),
      const SizedBox(height: 20),
      SizedBox(
        height: 52,
        child: FilledButton.icon(
          onPressed: createAccount,
          style: FilledButton.styleFrom(
            backgroundColor: loginTeal,
            foregroundColor: Colors.white,
            shadowColor: loginTeal.withValues(alpha: .3),
            elevation: 3,
          ),
          icon: const Icon(Icons.check_circle_outline_rounded),
          label: const Text('تسجيل'),
        ),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => setState(() => creatingAccount = false),
        child: const Text('لديك حساب؟ تسجيل دخول'),
      ),
    ],
  );
}

class HomePage extends StatelessWidget {
  final bool isManager;
  final String role;
  const HomePage({this.isManager = false, this.role = 'user', super.key});
  static const items = [
    ('البرمجة', 'تعلم وبناء المشاريع', Icons.code, emerald, 'asset:assets/images/45.png'),
    ('المدرسة', 'دروس ومهارات تفاعلية', Icons.school, olive, 'asset:assets/images/school_item.png'),
    ('المكتبة', 'كتب ومعارف مختارة', Icons.menu_book, Color(0xff3f7568), 'asset:assets/images/3444444444.png'),
    ('طريق المليون', 'أسئلة وتحديات حتى القمة', Icons.emoji_events, Color(0xffd4a72c), 'https://images.unsplash.com/photo-1516321318423-f06f85e504b3?auto=format&fit=crop&w=900&q=85'),
    ('الصحة', 'متابعة مؤشراتك الحيوية', Icons.favorite, burgundy, 'https://images.unsplash.com/photo-1576091160550-112173f7f869?auto=format&fit=crop&w=900&q=85'),
    ('الاستكشاف', 'اكتشف عوالم جديدة', Icons.explore, Color(0xff557c72), 'https://images.unsplash.com/photo-1518770660439-4636190af475?auto=format&fit=crop&w=900&q=85'),
    ('الإنجازات', 'تابع تقدمك وتطورك', Icons.emoji_events, Color(0xff9b6b2f), 'https://images.unsplash.com/photo-1552664730-d307ca884978?auto=format&fit=crop&w=900&q=85'),
    ('المجتمع', 'تواصل وشارك المعرفة', Icons.groups, Color(0xff6b8060), 'https://images.unsplash.com/photo-1529156069898-49953e39b3ac?auto=format&fit=crop&w=900&q=85'),
    ('الإعدادات', 'خصص تجربتك', Icons.settings, mutedInk, 'https://images.unsplash.com/photo-1558655146-9f40138edfeb?auto=format&fit=crop&w=900&q=85'),
    ('عن ثيودور', 'تعرف على المنصة', Icons.info_outline, mutedInk, 'https://images.unsplash.com/photo-1497366754035-f200968a6e72?auto=format&fit=crop&w=900&q=85'),
    ('الإدارة', 'لوحة التحكم والصلاحيات', Icons.admin_panel_settings, burgundy, 'https://images.unsplash.com/photo-1556761175-b413da4baf72?auto=format&fit=crop&w=900&q=85'),
  ];
  @override
  Widget build(BuildContext context) => Shell(
    child: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final columns = width < 560
              ? 2
              : width < 900
              ? 3
              : 5;
            final visibleItems = isManager
              ? items
              : items.where((item) {
                  if (item.$1 == 'الإدارة') return false;
                  if (role == 'user' && item.$1 == 'الصحة') return false;
                  return true;
                }).toList();
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Column(
                    children: [
                      Align(
                        alignment: AlignmentDirectional.topStart,
                        child: IconButton.filledTonal(
                          tooltip: 'رجوع',
                          onPressed: () => Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => const LoginPage()),
                          ),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      ),
                      TheodoreBrand(
                        size: width < 560 ? 112 : 142,
                        compact: true,
                      ),
                      const SizedBox(height: 4),
                      const Directionality(
                        textDirection: TextDirection.rtl,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'ثيودور',
                              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: ink),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.apple, color: Color(0xffa8b0bb), size: 25),
                            SizedBox(width: 8),
                            Text(
                              '(Theodore)',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: ink),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        FeatureTile(
                          item: visibleItems[index],
                          index: items.indexOf(visibleItems[index]),
                        ),
                    childCount: visibleItems.length,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: width < 560 ? 1.05 : 1.1,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class FeatureTile extends StatefulWidget {
  final (String, String, IconData, Color, String) item;
  final int index;
  const FeatureTile({required this.item, required this.index, super.key});

  @override
  State<FeatureTile> createState() => _FeatureTileState();
}

class _FeatureTileState extends State<FeatureTile> {
  bool pressed = false;

  @override
  Widget build(BuildContext context) => InkWell(
    onTapDown: (_) => setState(() => pressed = true),
    onTapUp: (_) {
      setState(() => pressed = false);
      _openFeature(context);
    },
    onTapCancel: () => setState(() => pressed = false),
    borderRadius: BorderRadius.circular(18),
    child: AnimatedScale(
      scale: pressed ? .985 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0x1f0f172a),
              blurRadius: pressed ? 20 : 14,
              offset: Offset(0, pressed ? 10 : 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.item.$5.startsWith('asset:')
                  ? Image.asset(
                      widget.item.$5.substring(6),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _FeatureFallback(item: widget.item),
                    )
                  : Image.network(
                      widget.item.$5,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _FeatureFallback(item: widget.item),
                    ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [widget.item.$4.withValues(alpha: .1), ink.withValues(alpha: .88)],
                  ),
                ),
              ),
              PositionedDirectional(
                top: 12,
                end: 12,
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: widget.item.$4,
                  child: Icon(widget.item.$3, size: 23, color: Colors.white),
                ),
              ),
              PositionedDirectional(
                start: 14,
                end: 14,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.item.$1, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 3),
                    Text(widget.item.$2, style: const TextStyle(color: Color(0xffe2e8f0), fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  void _openFeature(BuildContext context) {
    if (widget.index == 0) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProgrammingPage()),
        );
      }
      if (widget.index == 2) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ModernLibraryPage()),
        );
      }
      if (widget.index == 3) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MillionRoadPage()),
        );
      }
      if (widget.index == 4) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HealthHubPage()),
        );
      }
      if (widget.index == 5) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ExplorationPage()),
        );
      }
      if (widget.index == 10) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminPage()),
        );
      }
  }
}

class _FeatureFallback extends StatelessWidget {
  final (String, String, IconData, Color, String) item;
  const _FeatureFallback({required this.item});

  @override
  Widget build(BuildContext context) => Container(
    color: item.$4,
    child: Center(
      child: Icon(item.$3, color: Colors.white.withValues(alpha: .82), size: 92),
    ),
  );
}

class ExplorationPage extends StatelessWidget {
  const ExplorationPage({super.key});

  @override
  Widget build(BuildContext context) => _LearningScaffold(
    title: 'الاستكشافات',
    subtitle: 'مسارات معرفية مرتبة لتتعلم خطوة بخطوة',
    child: Column(
      children: [
        _LearningHeader(
          icon: Icons.explore_outlined,
          color: const Color(0xff557c72),
          title: 'هندسة تقنيات الحاسوب',
          subtitle: 'اختر المادة التي تريد استكشافها',
        ),
        const SizedBox(height: 16),
        _LearningTile(
          icon: Icons.calculate_outlined,
          color: emerald,
          title: 'الرياضيات',
          subtitle: 'فصول وموضوعات الرياضيات الأساسية',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MathematicsPage()),
          ),
        ),
      ],
    ),
  );
}

class MathematicsPage extends StatelessWidget {
  const MathematicsPage({super.key});

  @override
  Widget build(BuildContext context) => _LearningScaffold(
    title: 'الرياضيات',
    subtitle: 'هندسة تقنيات الحاسوب',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _LearningHeader(
          icon: Icons.calculate_outlined,
          color: emerald,
          title: 'الفصول الدراسية',
          subtitle: 'الفصل الأول متاح الآن، وبقية الفصول قيد التطوير',
        ),
        const SizedBox(height: 16),
        _ChapterTile(
          title: 'الفصل الأول',
          subtitle: 'الأعداد المركبة',
          active: true,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ComplexNumbersPage()),
          ),
        ),
        const SizedBox(height: 10),
        const _ChapterTile(title: 'الفصل الثاني', subtitle: 'قيد التطوير'),
        const SizedBox(height: 10),
        const _ChapterTile(title: 'الفصل الثالث', subtitle: 'قيد التطوير'),
        const SizedBox(height: 10),
        const _ChapterTile(title: 'الفصل الرابع', subtitle: 'قيد التطوير'),
      ],
    ),
  );
}

class ComplexNumbersPage extends StatelessWidget {
  const ComplexNumbersPage({super.key});

  static const operations = [
    ('جمع الأعداد المركبة', 'نجمع الحقيقي مع الحقيقي والتخيلي مع التخيلي', Icons.add_circle_outline),
    ('طرح الأعداد المركبة', 'نحوّل الطرح إلى جمع ثم نغيّر إشارات القوس الثاني', Icons.remove_circle_outline),
    ('ضرب الأعداد المركبة', 'نوزّع كل حد ثم نستبدل i² بسالب واحد', Icons.close),
    ('قسمة الأعداد المركبة', 'نتخلص من i في المقام بالمرافق', Icons.functions),
  ];

  @override
  Widget build(BuildContext context) => _LearningScaffold(
    title: 'الأعداد المركبة',
    subtitle: 'اختر عملية واحدة لفتح درسها فقط',
    child: Column(
      children: [
        const _LearningHeader(
          icon: Icons.functions,
          color: burgundy,
          title: 'موضوع الأعداد المركبة',
          subtitle: 'كل عملية لها درس مستقل وواضح',
        ),
        const SizedBox(height: 16),
        ...operations.map(
          (operation) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _LearningTile(
              icon: operation.$3,
                color: operation.$1 == 'جمع الأعداد المركبة'
                  ? emerald
                  : operation.$1 == 'طرح الأعداد المركبة'
                  ? burgundy
                  : operation.$1 == 'ضرب الأعداد المركبة'
                  ? const Color(0xffc47a22)
                  : mutedInk,
              title: operation.$1,
              subtitle: operation.$2,
                enabled: operation.$1 == 'جمع الأعداد المركبة' ||
                  operation.$1 == 'طرح الأعداد المركبة' ||
                  operation.$1 == 'ضرب الأعداد المركبة' ||
                  operation.$1 == 'قسمة الأعداد المركبة',
              onTap: operation.$1 == 'جمع الأعداد المركبة'
                  ? () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ComplexAdditionLessonPage()),
                    )
                  : operation.$1 == 'طرح الأعداد المركبة'
                  ? () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ComplexSubtractionLessonPage()),
                    )
                  : operation.$1 == 'ضرب الأعداد المركبة'
                  ? () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ComplexMultiplicationLessonPage()),
                    )
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ComplexDivisionLessonPage(),
                      ),
                    ),
            ),
          ),
        ),
      ],
    ),
  );
}

class ComplexDivisionLessonPage extends StatelessWidget {
  const ComplexDivisionLessonPage({super.key});

  @override
  Widget build(BuildContext context) => _LearningScaffold(
    title: 'قسمة الأعداد المركبة',
    subtitle: 'دراسة موحدة: خطوة واحدة واضحة في كل مرة',
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const _LessonIllustration(icon: Icons.functions, label: 'إذا رأيت i في المقام، نتخلص منها بالمرافق', color: Color(0xff2563eb)),
      const SizedBox(height: 14),
      const Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('ملاحظة عامة للطالب', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xff1d4ed8))),
        SizedBox(height: 8),
        Text('انتبه، إذا تشوف i بالمقام لازم نتخلص منها. نجيب مرافق المقام، يعني نفس الأعداد بس نغير الإشارة اللي بالنص، ونضرب بالمرافق فوق وتحت.', textAlign: TextAlign.center, style: TextStyle(color: mutedInk, height: 1.7)),
      ])),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ComplexDivisionFirstExamplePage())),
        style: FilledButton.styleFrom(backgroundColor: const Color(0xff2563eb)),
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('انطيني مثال'),
      ),
    ]),
  );
}

class ComplexDivisionFirstExamplePage extends StatefulWidget {
  const ComplexDivisionFirstExamplePage({super.key});
  @override
  State<ComplexDivisionFirstExamplePage> createState() => _ComplexDivisionFirstExamplePageState();
}

class _ComplexDivisionFirstExamplePageState extends State<ComplexDivisionFirstExamplePage> {
  int visibleStep = 0;
  bool showMore = false;

  static const steps = [
    ('نكتب الكسر', '(1 + i) / (2 + 4i)', 'لدينا i في المقام، لذلك نحتاج إلى المرافق.'),
    ('نجيب مرافق المقام', '(2 + 4i)  →  (2 - 4i)', 'نغيّر إشارة الجزء التخيلي فقط، ويبقى 2 كما هو.'),
    ('نضرب بالمرافق فوق وتحت', '(1 + i) / (2 + 4i)  ×  (2 - 4i) / (2 - 4i)', 'نضرب الكسر الأول بالكسر الثاني، ونستعمل المرافق نفسه فوق وتحت.'),
    ('نفتح البسط', '2 - 4i + 2i - 4i²', 'كل حد في القوس الأول يضرب كل حد في القوس الثاني.'),
    ('نفتح المقام', '2² + 4² = 4 + 16 = 20', 'القوسان مترافقان، لذلك يصير المقام عدداً حقيقياً.'),
    ('نتذكر i²', '-4i² = -4 × -1 = +4', 'تذكر، i² = -1. السالب في السالب يصير موجباً.'),
    ('نبسط البسط', '2 + 4 - 2i = 6 - 2i', 'نجمع الحقيقي مع الحقيقي، ونترك الجزء التخيلي على اليمين.'),
    ('نكتب الناتج على 20', '(6 - 2i) / 20', 'العدد الحقيقي 6 على اليسار، والجزء التخيلي -2i على اليمين.'),
    ('نختصر بخط أخضر', '(6 - 2i) / 20 = (3 - i) / 10', 'نقسم 6 و2 و20 على 2، فتظهر أبسط صورة.'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showConjugatePrompt());
  }

  void _showConjugatePrompt() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('انتبه'),
        content: const Text('عدنا i بالمقام، تحب أوضحلك ليش نجيب المرافق؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('لا، أكمل')),
          FilledButton(onPressed: () { Navigator.pop(context); setState(() => showMore = true); }, child: const Text('وضحلي')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _DivisionNotebookScaffold(
    title: 'المثال الأول',
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (showMore) ...[
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xffeff6ff), borderRadius: BorderRadius.circular(8)), child: const Text('حبيبي، نجيب المرافق حتى نخلي المقام بدون i.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xff1d4ed8), fontWeight: FontWeight.bold, height: 1.6))),
        const SizedBox(height: 8),
      ],
      _DivisionStepList(steps: steps, visibleStep: visibleStep),
      const SizedBox(height: 12),
      _DivisionQuestion(onMore: () => setState(() => showMore = true), onSkip: () => setState(() => showMore = false)),
      const SizedBox(height: 8),
      if (visibleStep < steps.length - 1)
        FilledButton.icon(onPressed: () => setState(() { visibleStep++; showMore = false; }), style: FilledButton.styleFrom(backgroundColor: const Color(0xff2563eb)), icon: const Icon(Icons.arrow_downward_rounded), label: const Text('فهمت، كمل'))
      else
        FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ComplexDivisionSecondExamplePage())), style: FilledButton.styleFrom(backgroundColor: const Color(0xff15803d)), icon: const Icon(Icons.arrow_forward_rounded), label: const Text('فهمت، إلى المثال الثاني')),
      TextButton.icon(onPressed: () => setState(() { visibleStep = 0; showMore = false; }), icon: const Icon(Icons.replay), label: const Text('أعد المثال')),
    ]),
  );
}

class ComplexDivisionSecondExamplePage extends StatefulWidget {
  const ComplexDivisionSecondExamplePage({super.key});
  @override
  State<ComplexDivisionSecondExamplePage> createState() => _ComplexDivisionSecondExamplePageState();
}

class _ComplexDivisionSecondExamplePageState extends State<ComplexDivisionSecondExamplePage> {
  int visibleStep = 0;
  static const steps = [
    ('نكتب المثال', '(1 + √3i) / (1 - √3i)', 'نجيب مرافق المقام: (1 + √3i).'),
    ('نضرب فوق وتحت', '(1 + √3i) / (1 - √3i)  ×  (1 + √3i) / (1 + √3i)', 'فتح الأقواس يكون خطوة خطوة.'),
    ('نبسط المقام', '1² + (√3)² = 1 + 3 = 4', 'هنا ظهر 1 + 3 = 4 لأن (√3)² = 3.'),
    ('نفتح البسط', '1 + 2√3i + 3i²', 'نضرب الأول في الأول، ثم الحدين الأوسطين، ثم الأخيرين.'),
    ('نبدل i²', '1 + 2√3i + 3(-1) = -2 + 2√3i', 'تذكر، i² = -1.'),
    ('الناتج المرتب', '(-2 + 2√3i) / 4 = -1/2 + (√3/2)i', 'الحقيقي على اليسار، والتخيلي على اليمين. هذه هي الصورة الصحيحة للمثال.'),
  ];

  @override
  Widget build(BuildContext context) => _DivisionNotebookScaffold(
    title: 'المثال الثاني',
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _DivisionStepList(steps: steps, visibleStep: visibleStep),
      const SizedBox(height: 12),
      _DivisionQuestion(onMore: () {}, onSkip: () {}),
      const SizedBox(height: 8),
      if (visibleStep < steps.length - 1)
        FilledButton.icon(onPressed: () => setState(() => visibleStep++), style: FilledButton.styleFrom(backgroundColor: const Color(0xff2563eb)), icon: const Icon(Icons.arrow_downward_rounded), label: const Text('فهمت، كمل'))
      else
        FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ComplexDivisionHomeworkPage())), style: FilledButton.styleFrom(backgroundColor: const Color(0xff15803d)), icon: const Icon(Icons.arrow_forward_rounded), label: const Text('فهمت، إلى الواجب البيتي')),
      TextButton.icon(onPressed: () => setState(() => visibleStep = 0), icon: const Icon(Icons.replay), label: const Text('أعد المثال')),
    ]),
  );
}

class ComplexDivisionHomeworkPage extends StatefulWidget {
  const ComplexDivisionHomeworkPage({super.key});
  @override
  State<ComplexDivisionHomeworkPage> createState() => _ComplexDivisionHomeworkPageState();
}

class _ComplexDivisionHomeworkPageState extends State<ComplexDivisionHomeworkPage> {
  int visibleStep = 0;
  static const steps = [
    ('المسألة', '(2√3i) / (2 + 4i)', 'نجيب مرافق المقام: (2 - 4i).'),
    ('نضرب فوق وتحت', '((2√3i)(2 - 4i)) / ((2 + 4i)(2 - 4i))', 'نستعمل المرافق نفسه في البسط والمقام.'),
    ('تذكير', 'i² = -1', 'راقب الحد الذي فيه i × i.'),
    ('أكمل بنفسك', '____________________________', 'رتب الحقيقي على اليسار والتخيلي على اليمين.'),
  ];

  @override
  Widget build(BuildContext context) => _DivisionNotebookScaffold(
    title: 'واجب بيتي',
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _DivisionStepList(steps: steps, visibleStep: visibleStep),
      const SizedBox(height: 12),
      _DivisionQuestion(onMore: () {}, onSkip: () {}),
      const SizedBox(height: 10),
      Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(onPressed: () => setState(() => visibleStep = math.min(visibleStep + 1, steps.length - 1)), style: FilledButton.styleFrom(backgroundColor: const Color(0xff2563eb)), icon: const Icon(Icons.help_outline), label: const Text('وضحلي')),
        OutlinedButton.icon(onPressed: () => setState(() => visibleStep = math.min(visibleStep + 1, steps.length - 1)), icon: const Icon(Icons.skip_next), label: const Text('تخطي')),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: FilledButton.icon(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أحسنت، راجع المرافق ثم أكمل خطوة خطوة.'))), icon: const Icon(Icons.check), label: const Text('فهمت الحل'))),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(onPressed: () => setState(() => visibleStep = 0), icon: const Icon(Icons.edit), label: const Text('أريد أحله بنفسي'))),
      ]),
    ]),
  );
}

class _DivisionNotebookScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  const _DivisionNotebookScaffold({required this.title, required this.child});
  @override
  Widget build(BuildContext context) => _LearningScaffold(title: 'قسمة الأعداد المركبة', subtitle: title, child: Panel(child: CustomPaint(painter: _DivisionPaperPainter(), child: Padding(padding: const EdgeInsets.all(16), child: child))));
}

class _DivisionPaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xff93c5fd).withValues(alpha: .2)..strokeWidth = 1;
    for (var y = 20.0; y < size.height; y += 34) canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DivisionStepList extends StatelessWidget {
  final List<(String, String, String)> steps;
  final int visibleStep;
  const _DivisionStepList({required this.steps, required this.visibleStep});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: List.generate(visibleStep + 1, (index) {
    final item = steps[index];
    final isGreen = index == steps.length - 1 || item.$1.contains('اختصر') || item.$1.contains('الناتج');
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (index > 0) const Align(alignment: Alignment.centerRight, child: Icon(Icons.arrow_downward_rounded, color: Color(0xff64748b), size: 20)),
      Text(item.$1, textAlign: TextAlign.right, style: TextStyle(color: isGreen ? const Color(0xff15803d) : const Color(0xff2563eb), fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      _DivisionMathLine(text: item.$2, color: isGreen ? const Color(0xff15803d) : const Color(0xff334155)),
      Text(item.$3, textAlign: TextAlign.center, style: const TextStyle(color: mutedInk, height: 1.5)),
      if (item.$2.contains('i²')) const Text('↑ تذكر، i² = -1', textAlign: TextAlign.center, style: TextStyle(color: Color(0xffb91c1c), fontWeight: FontWeight.bold)),
    ]));
  }));
}

class _DivisionMathLine extends StatelessWidget {
  final String text;
  final Color color;
  const _DivisionMathLine({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    if (text.contains(' × ')) {
      final parts = text.split(' × ');
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
          for (var index = 0; index < parts.length; index++) ...[
            _DivisionFraction(text: parts[index].trim(), color: color),
            if (index < parts.length - 1) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('×', style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold))),
          ],
          ],
        ),
      );
    }
    return _DivisionFraction(text: text, color: color);
  }
}

class _DivisionFraction extends StatelessWidget {
  final String text;
  final Color color;
  const _DivisionFraction({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final slashIndex = text.indexOf(' / ');
    if (slashIndex == -1) {
      return Directionality(textDirection: TextDirection.ltr, child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold, height: 1.5)));
    }

    final numerator = text.substring(0, slashIndex).trim();
    final remainder = text.substring(slashIndex + 3).trim();
    final equalsIndex = remainder.indexOf(' = ');
    final denominator = equalsIndex == -1 ? remainder : remainder.substring(0, equalsIndex).trim();
    final afterFraction = equalsIndex == -1 ? null : remainder.substring(equalsIndex + 3).trim();

    return IntrinsicWidth(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Directionality(textDirection: TextDirection.ltr, child: Text(numerator, textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold, height: 1.35))),
        Container(height: 2, margin: const EdgeInsets.symmetric(vertical: 3), color: color),
        Directionality(textDirection: TextDirection.ltr, child: Text(denominator, textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold, height: 1.35))),
        if (afterFraction != null) ...[
          const SizedBox(height: 4),
          Directionality(textDirection: TextDirection.ltr, child: Text('= $afterFraction', textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold, height: 1.35))),
        ],
      ]),
    );
  }
}

class _DivisionQuestion extends StatelessWidget {
  final VoidCallback onMore;
  final VoidCallback onSkip;
  const _DivisionQuestion({required this.onMore, required this.onSkip});
  @override
  Widget build(BuildContext context) => Row(children: [
    const Expanded(child: Text('تريد أوضح أكثر لو أكمل؟', textAlign: TextAlign.center, style: TextStyle(color: mutedInk, fontWeight: FontWeight.bold))),
    TextButton(onPressed: onMore, child: const Text('وضحلي')),
    TextButton(onPressed: onSkip, child: const Text('تخطي')),
  ]);
}

class ComplexAdditionLessonPage extends StatefulWidget {
  const ComplexAdditionLessonPage({super.key});

  @override
  State<ComplexAdditionLessonPage> createState() => _ComplexAdditionLessonPageState();
}

class _ComplexAdditionLessonPageState extends State<ComplexAdditionLessonPage> {
  static const notes = [
    (
      'رتّب العددين أولاً',
      'نكتب كل عدد مركب داخل قوسين على صورة (الحقيقي + التخيلي). يبقى الجزء الحقيقي يساراً والجزء التخيلي يميناً.',
      'الصورة المرتبة تجعل كل جزء في مكانه: (a + bi).'
    ),
    (
      'اجمع الأجزاء المتشابهة فقط',
      'نجمع العددين الحقيقيين معاً، ثم نجمع العددين التخيليين معاً. لا نخلط الحقيقي بالتخيلي.',
      'الحقيقي مع الحقيقي، والتخيلي مع التخيلي؛ لأنهما نوعان مختلفان من الأجزاء.'
    ),
    (
      'انتبه إلى الإشارات والأقواس',
      'إذا سبقت قيمة الجزء علامة سالبة، تبقى الإشارة مع القيمة داخل القوس حتى ننفذ الجمع.',
      'الأقواس تحفظ إشارة كل جزء وتمنع إسقاط السالب أثناء الحل.'
    ),
  ];

  int understoodNotes = 0;
  final Set<int> simplerNotes = {};
  bool showExamples = false;
  bool showSkillHelp = false;
  int currentExample = 0;
  bool allExamplesDone = false;

  void markNote(int index, bool understood) {
    setState(() {
      if (understood) {
        understoodNotes = math.max(understoodNotes, index + 1);
        simplerNotes.remove(index);
      } else {
        simplerNotes.add(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) => _LearningScaffold(
    title: 'جمع الأعداد المركبة',
    subtitle: 'ملاحظات الجمع ثم أمثلة تفاعلية',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LessonIllustration(
          icon: understoodNotes == notes.length
              ? Icons.auto_awesome_rounded
              : simplerNotes.isNotEmpty
              ? Icons.lightbulb_outline_rounded
              : Icons.psychology_alt_outlined,
          label: understoodNotes == notes.length
              ? 'أحسنت، حان وقت التطبيق'
              : simplerNotes.isNotEmpty
              ? 'نبسّط الفكرة معاً'
              : 'نستكشف الفكرة خطوة بخطوة',
          color: understoodNotes == notes.length ? burgundy : emerald,
        ),
        const SizedBox(height: 14),
        const _LearningHeader(
          icon: Icons.add_circle_outline,
          color: emerald,
          title: 'ملاحظات الجمع',
          subtitle: 'أكمل الملاحظات بالترتيب قبل الانتقال إلى الأمثلة',
        ),
        const SizedBox(height: 16),
        ...List.generate(notes.length, (index) => _NoteCard(
          number: index + 1,
          title: notes[index].$1,
          body: notes[index].$2,
          simplerBody: notes[index].$3,
          isSimpler: simplerNotes.contains(index),
          isDone: understoodNotes > index,
          onUnderstood: () => markNote(index, true),
          onNotUnderstood: () => markNote(index, false),
        )),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: understoodNotes == notes.length
              ? () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ComplexAdditionExamplesPage()),
                )
              : null,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('ابدأ الأمثلة التفاعلية'),
        ),
      ],
    ),
  );
}

class ComplexAdditionExamplesPage extends StatefulWidget {
  const ComplexAdditionExamplesPage({super.key});

  @override
  State<ComplexAdditionExamplesPage> createState() => _ComplexAdditionExamplesPageState();
}

class _ComplexAdditionExamplesPageState extends State<ComplexAdditionExamplesPage> {
  int currentExample = 0;
  bool allExamplesDone = false;
  bool showSkillHelp = false;

  @override
  Widget build(BuildContext context) => _LearningScaffold(
    title: 'أمثلة جمع الأعداد المركبة',
    subtitle: 'مثال واحد في كل واجهة، ثم ننتقل بعد الضغط على «فهمت»',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _LessonIllustration(
          icon: Icons.edit_note_rounded,
          label: 'نكتب ونحسب ونفسّر السبب',
          color: burgundy,
        ),
        const SizedBox(height: 14),
        _ExampleProgress(currentExample: currentExample, completed: allExamplesDone),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 480),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(.08, 0), end: Offset.zero).animate(animation),
              child: child,
            ),
          ),
          child: allExamplesDone
              ? const _ExamplesCompleted(key: ValueKey('examples-completed'))
              : _AdditionExampleCard(
                  key: ValueKey(currentExample),
                  title: currentExample == 0 ? 'المثال الأول' : 'المثال الثاني مع الإشارات',
                  expression: currentExample == 0 ? '(3 + 2i) + (5 + 4i)' : '(-4 + 3i) + (7 - 5i)',
                  steps: currentExample == 0
                      ? const [
                          ('نحافظ على الأقواس ونفصل النوعين', '(3 + 2i) + (5 + 4i)', 'حتى تبقى إشارة كل جزء واضحة.'),
                          ('نجمع الحقيقي مع الحقيقي', '3 + 5 = 8', 'لأن 3 و5 جزءان حقيقيان.'),
                          ('نجمع التخيلي مع التخيلي', '2i + 4i = 6i', 'لأن 2i و4i يحملان الوحدة التخيلية نفسها i.'),
                          ('نكتب الناتج بالترتيب الصحيح', '8 + 6i', 'الحقيقي دائماً على اليسار والتخيلي على اليمين.'),
                        ]
                      : const [
                          ('نحافظ على الأقواس والإشارات', '(-4 + 3i) + (7 - 5i)', 'حتى لا نفقد الإشارة السالبة في أي جزء.'),
                          ('نجمع الحقيقي مع الحقيقي', '-4 + 7 = 3', 'الإشارة السالبة جزء من العدد الحقيقي الأول.'),
                          ('نجمع التخيلي مع التخيلي', '3i + (-5i) = -2i', 'الإشارتان تحددان أن الناتج التخيلي سالب.'),
                          ('نكتب الناتج بالترتيب الصحيح', '3 - 2i', 'الحقيقي بقي يساراً والتخيلي بقي يميناً.'),
                        ],
                  isLastExample: currentExample == 1,
                  onSkillHelp: () => setState(() => showSkillHelp = true),
                  onCompleted: () => setState(() {
                    showSkillHelp = false;
                    if (currentExample == 0) {
                      currentExample = 1;
                    } else {
                      allExamplesDone = true;
                    }
                  }),
                ),
        ),
        if (showSkillHelp) ...[
          const SizedBox(height: 14),
          const Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('شرح المهارة الأساسية', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('في الجمع لا نحتاج إلى القسمة الطويلة أو تبسيط الكسور. نرتب الأجزاء، ثم نجمع القيم ذات النوع نفسه فقط، ونعود مباشرة إلى إكمال المثال.'),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

class PlaceholderLessonPage extends StatelessWidget {
  final String title;
  const PlaceholderLessonPage({required this.title, super.key});

  @override
  Widget build(BuildContext context) => _LearningScaffold(
    title: title,
    subtitle: 'درس مستقل',
    child: const Panel(
      child: Column(
        children: [
          Icon(Icons.construction_outlined, size: 54, color: mutedInk),
          SizedBox(height: 14),
          Text('قيد التطوير', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('سيضاف هذا الدرس بنفس البنية التفاعلية قريباً.', textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class ComplexSubtractionLessonPage extends StatefulWidget {
  const ComplexSubtractionLessonPage({super.key});

  @override
  State<ComplexSubtractionLessonPage> createState() => _ComplexSubtractionLessonPageState();
}

class _ComplexSubtractionLessonPageState extends State<ComplexSubtractionLessonPage> {
  static const notes = [
    (
      'نزل القوس الأول كما هو',
      'نكتب العدد المركب الأول داخل قوسيه من دون تغيير أي إشارة.',
      'القوس الأول يبقى كما هو: (a + bi).'
    ),
    (
      'حوّل إشارة الطرح إلى جمع',
      'نستبدل علامة الطرح بين القوسين بعلامة جمع حتى نطبق قاعدة جمع الأعداد المركبة.',
      'بدل (الأول) - (الثاني) نكتب (الأول) + (الثاني بعد تغيير إشاراته).'
    ),
    (
      'غيّر إشارات القوس الثاني كلها',
      'نغيّر إشارة الجزء الحقيقي وإشارة الجزء التخيلي في القوس الثاني، ثم نجمع الحقيقي مع الحقيقي والتخيلي مع التخيلي.',
      'السالب أمام القوس يقلب الإشارتين: الموجب يصبح سالباً والسالب يصبح موجباً.'
    ),
    (
      'حافظ على الشكل القياسي',
      'نكتب الناتج النهائي بحيث يكون العدد الحقيقي على اليسار والجزء التخيلي على اليمين مع إبقاء الإشارات واضحة.',
      'الشكل القياسي دائماً: الحقيقي ثم التخيلي، مثل -1 - 2i أو 8 + 7i.'
    ),
  ];

  int understoodNotes = 0;
  final Set<int> simplerNotes = {};
  bool showExamples = false;

  void markNote(int index, bool understood) {
    setState(() {
      if (understood) {
        understoodNotes = math.max(understoodNotes, index + 1);
        simplerNotes.remove(index);
      } else {
        simplerNotes.add(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) => _LearningScaffold(
    title: 'طرح الأعداد المركبة',
    subtitle: 'درس تفاعلي داخل قسم الأعداد المركبة',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LessonIllustration(
          icon: understoodNotes == notes.length ? Icons.auto_awesome_rounded : Icons.lightbulb_outline_rounded,
          label: understoodNotes == notes.length ? 'أحسنت، طبّق القاعدة الآن' : 'نحوّل الطرح إلى جمع بذكاء',
          color: burgundy,
        ),
        const SizedBox(height: 14),
        const _LearningHeader(
          icon: Icons.remove_circle_outline,
          color: burgundy,
          title: 'ملاحظات طرح الأعداد المركبة',
          subtitle: 'اقرأ كل قاعدة واضغط «فهمت» للانتقال في التعلم',
        ),
        const SizedBox(height: 16),
        const _SubtractionRuleMap(),
        const SizedBox(height: 18),
        ...List.generate(notes.length, (index) => _NoteCard(
          number: index + 1,
          title: notes[index].$1,
          body: notes[index].$2,
          simplerBody: notes[index].$3,
          isSimpler: simplerNotes.contains(index),
          isDone: understoodNotes > index,
          onUnderstood: () => markNote(index, true),
          onNotUnderstood: () => markNote(index, false),
        )),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: understoodNotes == notes.length
              ? () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ComplexSubtractionExamplesPage()),
                )
              : null,
          style: FilledButton.styleFrom(backgroundColor: burgundy),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('ابدأ أمثلة الطرح التفاعلية'),
        ),
      ],
    ),
  );
}

class _SubtractionRuleMap extends StatelessWidget {
  const _SubtractionRuleMap();

  static const steps = [
    ('1', 'القوس الأول', '(a + bi)', Icons.vertical_align_bottom_rounded),
    ('2', 'نحوّل الطرح إلى جمع', '(a + bi) + (...)', Icons.add_circle_outline),
    ('3', 'نغيّر إشارات القوس الثاني', '(-c - di)', Icons.flip_rounded),
    ('4', 'نجمع الأجزاء المتشابهة', '(a-c) + (b-d)i', Icons.calculate_outlined),
  ];

  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(children: [
          Icon(Icons.account_tree_outlined, color: burgundy),
          SizedBox(width: 8),
          Expanded(child: Text('خريطة حل الطرح', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        ]),
        const SizedBox(height: 12),
        ...List.generate(steps.length, (index) {
          final step = steps[index];
          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: index.isEven ? const Color(0xfffff8f5) : const Color(0xfff5f9ff),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: burgundy.withValues(alpha: .16)),
                ),
                child: Row(children: [
                  CircleAvatar(radius: 17, backgroundColor: burgundy, foregroundColor: Colors.white, child: Text(step.$1)),
                  const SizedBox(width: 10),
                  Icon(step.$4, color: burgundy, size: 24),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(step.$2, style: const TextStyle(fontWeight: FontWeight.bold, color: ink)),
                    const SizedBox(height: 4),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(step.$3, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: burgundy)),
                    ),
                  ])),
                ]),
              ),
              if (index < steps.length - 1)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 3),
                  child: Icon(Icons.arrow_downward_rounded, color: burgundy, size: 22),
                ),
            ],
          );
        }),
        const SizedBox(height: 12),
        const Text(
          'القوس الأول ينزل كما هو، نحول إشارة الطرح إلى جمع، نغير جميع إشارات القوس الثاني الحقيقي والتخيلي، ثم نجمع الحقيقي مع الحقيقي والتخيلي مع التخيلي.',
          textAlign: TextAlign.center,
          style: TextStyle(color: mutedInk, height: 1.6),
        ),
      ],
    ),
  );
}

class ComplexSubtractionExamplesPage extends StatefulWidget {
  const ComplexSubtractionExamplesPage({super.key});

  @override
  State<ComplexSubtractionExamplesPage> createState() => _ComplexSubtractionExamplesPageState();
}

class _ComplexSubtractionExamplesPageState extends State<ComplexSubtractionExamplesPage> {
  int currentExample = 0;
  bool allExamplesDone = false;

  static const firstSteps = [
    ('ننزل القوس الأول كما هو', '(4 + 2i) - (5 + 4i)', 'لا نغيّر العدد الأول أو إشاراته.'),
    ('نحوّل الطرح إلى جمع', '(4 + 2i) + (5 + 4i)', 'تغيير العملية إلى جمع يجهزنا لتطبيق قاعدة الإشارات.'),
    ('نغيّر إشارات القوس الثاني', '(4 + 2i) + (-5 - 4i)', 'نغيّر الحقيقي 5 إلى -5 والتخيلي 4i إلى -4i.'),
    ('نجمع الحقيقي مع الحقيقي', '4 + (-5) = -1', 'لأن الأعداد الحقيقية تجمع معاً فقط.'),
    ('نجمع التخيلي مع التخيلي', '2i + (-4i) = -2i', 'لأن الأجزاء التخيليّة تحمل الوحدة نفسها i.'),
    ('نكتب الناتج بالشكل القياسي', '-1 - 2i', 'الحقيقي على اليسار والتخيلي على اليمين.'),
  ];

  static const secondSteps = [
    ('ننزل القوس الأول كما هو', '(6 + 3i) - (-2 - 4i)', 'لا نغيّر العدد الأول أو إشاراته.'),
    ('نحوّل الطرح إلى جمع', '(6 + 3i) + (-2 - 4i)', 'استبدلنا علامة الطرح بعلامة الجمع.'),
    ('نغيّر إشارات القوس الثاني', '(6 + 3i) + (2 + 4i)', 'السالب أمام القوس يقلب -2 إلى 2 و-4i إلى 4i.'),
    ('نجمع الحقيقي مع الحقيقي', '6 + 2 = 8', 'لأن 6 و2 جزءان حقيقيان.'),
    ('نجمع التخيلي مع التخيلي', '3i + 4i = 7i', 'لأن 3i و4i جزءان تخيليان متشابهان.'),
    ('نكتب الناتج بالشكل القياسي', '8 + 7i', 'الحقيقي بقي يساراً والتخيلي بقي يميناً.'),
  ];

  @override
  Widget build(BuildContext context) => _LearningScaffold(
    title: 'أمثلة طرح الأعداد المركبة',
    subtitle: 'مثال واحد في كل واجهة، وكل خطوة تحتاج تأكيد فهمك',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LessonIllustration(
          icon: currentExample == 0 ? Icons.edit_note_rounded : Icons.calculate_outlined,
          label: currentExample == 0 ? 'نقلب الإشارات خطوة خطوة' : 'ممتاز، نكمل المثال الثاني',
          color: burgundy,
        ),
        const SizedBox(height: 14),
        _ExampleProgress(currentExample: currentExample, completed: allExamplesDone),
        const SizedBox(height: 14),
        allExamplesDone
            ? const _SubtractionCompleted()
            : _SubtractionExampleCard(
                key: ValueKey(currentExample),
                title: currentExample == 0 ? 'المثال الأول' : 'المثال الثاني',
                expression: currentExample == 0 ? '(4 + 2i) - (5 + 4i)' : '(6 + 3i) - (-2 - 4i)',
                steps: currentExample == 0 ? firstSteps : secondSteps,
                isLastExample: currentExample == 1,
                onCompleted: () => setState(() {
                  if (currentExample == 0) {
                    currentExample = 1;
                  } else {
                    allExamplesDone = true;
                  }
                }),
              ),
      ],
    ),
  );
}

class _SubtractionExampleCard extends StatefulWidget {
  final String title;
  final String expression;
  final List<(String, String, String)> steps;
  final bool isLastExample;
  final VoidCallback onCompleted;
  const _SubtractionExampleCard({super.key, required this.title, required this.expression, required this.steps, required this.isLastExample, required this.onCompleted});

  @override
  State<_SubtractionExampleCard> createState() => _SubtractionExampleCardState();
}

class _SubtractionExampleCardState extends State<_SubtractionExampleCard> {
  int visibleStep = 0;
  final Set<int> simplerSteps = {};
  final Set<int> understoodSteps = {};

  void markStep(bool understood) {
    setState(() {
      if (understood) {
        understoodSteps.add(visibleStep);
        simplerSteps.remove(visibleStep);
      } else {
        simplerSteps.add(visibleStep);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[visibleStep];
    final isUnderstood = understoodSteps.contains(visibleStep);
    return Panel(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 420),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(.08, 0), end: Offset.zero).animate(animation),
            child: child,
          ),
        ),
        child: Column(
          key: ValueKey(visibleStep),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _MathLine(widget.expression),
            const Divider(height: 24),
            Text('الخطوة ${visibleStep + 1} من ${widget.steps.length}', style: const TextStyle(color: burgundy, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(step.$1, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: burgundy)),
            const SizedBox(height: 8),
            _MathLine(step.$2),
            const SizedBox(height: 8),
            Text('السبب: ${step.$3}', style: const TextStyle(color: mutedInk, height: 1.5)),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              child: simplerSteps.contains(visibleStep)
                  ? Text(
                      _simpleStep(step),
                      key: ValueKey('simple-$visibleStep'),
                      style: const TextStyle(color: burgundy, height: 1.5),
                    )
                  : const SizedBox(key: ValueKey('normal-step')),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: () => markStep(true), icon: const Icon(Icons.check), label: const Text('فهمت'))),
              const SizedBox(width: 8),
              Expanded(child: TextButton.icon(onPressed: () => markStep(false), icon: const Icon(Icons.help_outline), label: const Text('لم أفهم'))),
            ]),
            if (isUnderstood) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: visibleStep == widget.steps.length - 1
                    ? widget.onCompleted
                    : () => setState(() => visibleStep++),
                style: FilledButton.styleFrom(backgroundColor: burgundy),
                icon: const Icon(Icons.arrow_back_rounded),
                label: Text(visibleStep == widget.steps.length - 1
                    ? widget.isLastExample ? 'فهمت، إنهاء الأمثلة' : 'فهمت، افتح المثال الثاني'
                    : 'فهمت، الخطوة التالية'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _simpleStep((String, String, String) step) {
    if (step.$1.contains('إشارات')) return 'نقلب علامة كل جزء داخل القوس الثاني فقط، ثم نكمل الجمع.';
    if (step.$1.contains('الطرح')) return 'نبدل - إلى + حتى يصبح الحل جمعاً منظماً.';
    if (step.$1.contains('الحقيقي')) return 'نجمع الأرقام العادية وحدها، من دون i.';
    if (step.$1.contains('التخيلي')) return 'نجمع معاملات i وحدها ونبقي i في الناتج.';
    if (step.$1.contains('القياسي')) return 'ضع الرقم العادي أولاً، ثم الجزء الذي يحتوي i.';
    return 'نكتب القوس كما هو وننتقل بهدوء للخطوة التالية.';
  }
}

class _SubtractionCompleted extends StatelessWidget {
  const _SubtractionCompleted();

  @override
  Widget build(BuildContext context) => const Panel(
    child: Column(children: [
      _LessonIllustration(icon: Icons.emoji_events_outlined, label: 'أحسنت، اكتملت أمثلة الطرح', color: burgundy),
      SizedBox(height: 14),
      Text('تعلمت أن نحول الطرح إلى جمع، ثم نغيّر إشارات القوس الثاني ونحافظ على الشكل القياسي.', textAlign: TextAlign.center, style: TextStyle(color: mutedInk, height: 1.6)),
    ]),
  );
}

class ComplexMultiplicationLessonPage extends StatefulWidget {
  const ComplexMultiplicationLessonPage({super.key});

  @override
  State<ComplexMultiplicationLessonPage> createState() => _ComplexMultiplicationLessonPageState();
}

class _ComplexMultiplicationLessonPageState extends State<ComplexMultiplicationLessonPage> {
  static const notes = [
    (
      'اضرب كل حد في القوس الأول بكل حد في القوس الثاني',
      'نوزّع الضرب على القوسين: الحقيقي في الحقيقي، والحقيقي في التخيلي، والتخيلي في الحقيقي، والتخيلي في التخيلي.',
      'كل حد من القوس الأول يجب أن يصل إلى كل حد من القوس الثاني، فلا نترك أي حاصل ضرب.'
    ),
    (
      'استبدل i² بسالب واحد',
      'عندما نضرب i في i نحصل على i²، ونستبدلها مباشرةً بـ -1 قبل تجميع الحدود.',
      'i × i = i²، وقيمة i² هي -1؛ لذلك يتحول الحد التخيلي المربع إلى حد حقيقي.'
    ),
    (
      'اجمع الحدود المتشابهة واكتب الشكل القياسي',
      'نجمع الحدود الحقيقية معاً، ثم الحدود التي تحتوي i معاً، ونكتب الناتج على صورة a + bi.',
      'العدد الحقيقي يكون يساراً والجزء التخيلي الذي يحتوي i يكون يميناً.'
    ),
  ];

  int understoodNotes = 0;
  final Set<int> simplerNotes = {};
  static const radicalNotes = [
    (
      'الجذور المتشابهة: اجمع أو اطرح المعاملات فقط',
      'إذا كان الجذران متشابهين، نبقي الجذر مرة واحدة ونجمع أو نطرح الأرقام التي قبله. مثال: √3 + √3 = 2√3، ومثال آخر: 2√3 - √3 = √3.',
      'ننظر إلى ما قبل الجذر فقط: 1√3 + 1√3 = 2√3، و2√3 - 1√3 = 1√3.'
    ),
    (
      'الجذور المختلفة: نضرب ما بداخل الجذر',
      'إذا كانت الجذور مختلفة مثل √2 × √5، نضرب العددين داخل الجذر فنحصل على √10.',
      'لا نجمع √2 و√5؛ عند الضرب نضع 2 × 5 تحت جذر واحد، لذلك الناتج √10.'
    ),
  ];
  int understoodRadicalNotes = 0;
  final Set<int> simplerRadicalNotes = {};

  void markNote(int index, bool understood) {
    setState(() {
      if (understood) {
        understoodNotes = math.max(understoodNotes, index + 1);
        simplerNotes.remove(index);
      } else {
        simplerNotes.add(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) => _LearningScaffold(
    title: 'ضرب الأعداد المركبة',
    subtitle: 'درس تفاعلي داخل قسم الأعداد المركبة',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LessonIllustration(
          icon: understoodNotes == notes.length ? Icons.auto_awesome_rounded : Icons.calculate_outlined,
          label: understoodNotes == notes.length ? 'أحسنت، طبّق التوزيع الآن' : 'نوزّع ونحسب ونرتّب',
          color: const Color(0xffc47a22),
        ),
        const SizedBox(height: 14),
        const _LearningHeader(
          icon: Icons.close,
          color: Color(0xffc47a22),
          title: 'ملاحظات ضرب الأعداد المركبة',
          subtitle: 'افهم التوزيع وقاعدة i² ثم ابدأ الأمثلة',
        ),
        const SizedBox(height: 16),
        const _MultiplicationRuleMap(),
        const SizedBox(height: 18),
        const _ConjugateMultiplicationLesson(),
        const SizedBox(height: 18),
        const _LearningHeader(
          icon: Icons.square_foot_rounded,
          color: Color(0xffc47a22),
          title: 'ملاحظات تبسيط الجذور',
          subtitle: 'مهارة مساندة: نعرف متى نجمع المعاملات ومتى نضرب ما داخل الجذر',
        ),
        const SizedBox(height: 14),
        ...List.generate(radicalNotes.length, (index) => _NoteCard(
          number: index + 1,
          title: radicalNotes[index].$1,
          body: radicalNotes[index].$2,
          simplerBody: radicalNotes[index].$3,
          isSimpler: simplerRadicalNotes.contains(index),
          isDone: understoodRadicalNotes > index,
          onUnderstood: () => setState(() {
            understoodRadicalNotes = math.max(understoodRadicalNotes, index + 1);
            simplerRadicalNotes.remove(index);
          }),
          onNotUnderstood: () => setState(() => simplerRadicalNotes.add(index)),
        )),
        const SizedBox(height: 18),
        ...List.generate(notes.length, (index) => _NoteCard(
          number: index + 1,
          title: notes[index].$1,
          body: notes[index].$2,
          simplerBody: notes[index].$3,
          isSimpler: simplerNotes.contains(index),
          isDone: understoodNotes > index,
          onUnderstood: () => markNote(index, true),
          onNotUnderstood: () => markNote(index, false),
        )),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: understoodNotes == notes.length
              ? () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ComplexMultiplicationExamplesPage()),
                )
              : null,
          style: FilledButton.styleFrom(backgroundColor: const Color(0xffc47a22)),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('ابدأ أمثلة الضرب التفاعلية'),
        ),
      ],
    ),
  );
}

class _MultiplicationRuleMap extends StatelessWidget {
  const _MultiplicationRuleMap();

  static const steps = [
    ('1', 'وزّع الضرب على القوسين', '(a + bi)(c + di)', Icons.open_with_rounded),
    ('2', 'اضرب الحدود الأربعة', 'ac + adi + bci + bdi²', Icons.grid_view_rounded),
    ('3', 'استبدل i² بسالب واحد', 'bdi² = -bd', Icons.swap_horiz_rounded),
    ('4', 'اجمع المتشابه واكتب a + bi', '(ac - bd) + (ad + bc)i', Icons.auto_awesome_rounded),
  ];

  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.all(14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Row(children: [
        Icon(Icons.account_tree_outlined, color: Color(0xffc47a22)),
        SizedBox(width: 8),
        Expanded(child: Text('خريطة حل الضرب', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
      ]),
      const SizedBox(height: 12),
      ...List.generate(steps.length, (index) {
        final step = steps[index];
        return Column(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: index.isEven ? const Color(0xfffffaf2) : const Color(0xfff5f9ff),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xffc47a22).withValues(alpha: .2)),
            ),
            child: Row(children: [
              CircleAvatar(radius: 17, backgroundColor: const Color(0xffc47a22), foregroundColor: Colors.white, child: Text(step.$1)),
              const SizedBox(width: 10),
              Icon(step.$4, color: const Color(0xffc47a22), size: 24),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(step.$2, style: const TextStyle(fontWeight: FontWeight.bold, color: ink)),
                const SizedBox(height: 4),
                Directionality(textDirection: TextDirection.ltr, child: Text(step.$3, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xffa56518)))),
              ])),
            ]),
          ),
          if (index < steps.length - 1) const Padding(padding: EdgeInsets.symmetric(vertical: 3), child: Icon(Icons.arrow_downward_rounded, color: Color(0xffc47a22), size: 22)),
        ]);
      }),
      const SizedBox(height: 12),
      const Text(
        'نضرب كل حد في القوس الأول بكل حد في القوس الثاني، ثم نستبدل i² بسالب واحد، ونجمع الحقيقي مع الحقيقي والتخيلي مع التخيلي.',
        textAlign: TextAlign.center,
        style: TextStyle(color: mutedInk, height: 1.6),
      ),
    ]),
  );
}

class _ConjugateMultiplicationLesson extends StatefulWidget {
  const _ConjugateMultiplicationLesson();

  @override
  State<_ConjugateMultiplicationLesson> createState() => _ConjugateMultiplicationLessonState();
}

class _ConjugateMultiplicationLessonState extends State<_ConjugateMultiplicationLesson> {
  static const steps = [
    ('نبدأ بالشكل العام', '(a + bi)(a - bi)', 'هذا هو شكل ضرب العددين المترافقين.'),
    ('نقارن العدد الحقيقي', 'a في القوس الأول و a في القوس الثاني', 'العدد الحقيقي نفسه a ظهر في القوسين.'),
    ('نقارن الجزء التخيلي', 'bi في القوس الأول و bi في القوس الثاني', 'الجزء التخيلي نفسه هو bi في القوسين.'),
    ('نلاحظ الإشارة', '+bi و -bi', 'الاختلاف الوحيد هو الإشارة: موجب في القوس الأول وسالب في القوس الثاني، لذلك نسميهما مترافقين.'),
    ('نستخدم الفرق بين مربعين', '(a + bi)(a - bi) = a² - (bi)²', 'القاعدة تقول: (س + ص)(س - ص) = س² - ص².'),
    ('نتذكر قاعدة i²', 'i² = -1', 'إذا نسيت، اضغط «نسيت» وسنشرحها مرة أخرى هنا.'),
    ('نبدّل i²', 'a² - b²(-1) = a² + b²', 'طرح عدد سالب يحوّل الإشارة إلى جمع.'),
    ('نحسب النتيجة', 'a² + b²', 'نربّع العدد الحقيقي a، ثم نربّع معامل i وهو b، ثم نجمعهما.'),
  ];

  int visibleStep = 0;
  bool showSimple = false;
  bool showWhy = false;
  bool forgotI = false;
  String? selectedAnswer;
  String? answerFeedback;

  void move(int amount) {
    setState(() {
      visibleStep = (visibleStep + amount).clamp(0, steps.length - 1);
      showSimple = false;
      showWhy = false;
      forgotI = false;
      selectedAnswer = null;
      answerFeedback = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final step = steps[visibleStep];
    final isI2Step = visibleStep == 5;
    return Panel(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const _LearningHeader(
          icon: Icons.compare_arrows_rounded,
          color: Color(0xff2563eb),
          title: 'ضرب العددين المترافقين',
          subtitle: 'ملاحظة مهمة، خطوة واحدة في كل مرة',
        ),
        const SizedBox(height: 12),
        Row(children: [
          CircleAvatar(radius: 17, backgroundColor: const Color(0xff2563eb), foregroundColor: Colors.white, child: Text('${visibleStep + 1}')),
          const SizedBox(width: 8),
          Text('الخطوة ${visibleStep + 1} من ${steps.length}', style: const TextStyle(color: Color(0xff2563eb), fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 10),
        Text(step.$1, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xff1d4ed8))),
        const SizedBox(height: 10),
        _MathLine(step.$2),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.arrow_forward_rounded, color: Color(0xff2563eb)),
          const SizedBox(width: 6),
          Flexible(child: Text(step.$3, textAlign: TextAlign.center, style: const TextStyle(color: mutedInk, height: 1.5))),
          const SizedBox(width: 6),
          const Icon(Icons.arrow_back_rounded, color: Color(0xff2563eb)),
        ]),
        if (showWhy) ...[
          const SizedBox(height: 10),
          Text(_whyText(visibleStep), style: const TextStyle(color: Color(0xff1d4ed8), height: 1.5)),
        ],
        if (showSimple) ...[
          const SizedBox(height: 10),
          Text(_simpleText(visibleStep), style: const TextStyle(color: Color(0xffa56518), height: 1.5)),
        ],
        if (forgotI) ...[
          const SizedBox(height: 10),
          const Text('تذكّر: i هو العدد التخيلي، وعندما نضربه في نفسه نحصل على i²، وقاعدة الأعداد المركبة تقول إن i² = -1.', style: TextStyle(color: Color(0xffa56518), height: 1.5)),
        ],
        const SizedBox(height: 12),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(onPressed: () => setState(() { showWhy = true; showSimple = false; }), icon: const Icon(Icons.help_outline), label: const Text('ليش؟')),
          OutlinedButton.icon(onPressed: () => setState(() { showSimple = true; showWhy = false; }), icon: const Icon(Icons.lightbulb_outline), label: const Text('اشرح أبسط')),
          if (isI2Step) OutlinedButton.icon(onPressed: () => setState(() => forgotI = true), icon: const Icon(Icons.refresh), label: const Text('نسيت')),
          OutlinedButton.icon(onPressed: () => setState(() { showSimple = false; showWhy = false; forgotI = false; }), icon: const Icon(Icons.replay), label: const Text('أعد الخطوة')),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextButton.icon(onPressed: visibleStep == 0 ? null : () => move(-1), icon: const Icon(Icons.arrow_back), label: const Text('ارجع خطوة'))),
          const SizedBox(width: 8),
          Expanded(child: FilledButton.icon(onPressed: visibleStep == steps.length - 1 ? null : () => move(1), icon: const Icon(Icons.arrow_forward), label: const Text('التالي'))),
        ]),
        if (visibleStep == steps.length - 1) ...[
          const SizedBox(height: 10),
          const Text('اختر الناتج الصحيح:', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: ['a² - b²', 'a² + b²', '(a + bi)²'].map((answer) => OutlinedButton(
            onPressed: () => setState(() {
              selectedAnswer = answer;
              answerFeedback = answer == 'a² + b²' ? '✓ إجابة صحيحة، أحسنت. نربّع a ونربّع b ثم نجمع.' : 'ليست هذه النتيجة. الخطأ في الإشارة أو في قاعدة i² = -1. حاول مرة أخرى.';
            }),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: selectedAnswer == answer && answerFeedback?.startsWith('✓') == true ? const Color(0xff15803d) : const Color(0xff2563eb)),
            ),
            child: Text(answer, textDirection: TextDirection.ltr),
          )).toList()),
          if (answerFeedback != null) ...[
            const SizedBox(height: 8),
            Text(answerFeedback!, textAlign: TextAlign.center, style: TextStyle(color: answerFeedback!.startsWith('✓') ? const Color(0xff15803d) : const Color(0xffb91c1c), fontWeight: FontWeight.bold)),
          ],
        ],
      ]),
    );
  }

  String _whyText(int step) => switch (step) {
    0 => 'نبدأ بحروف عامة حتى تنجح القاعدة مع أي عددين مترافقين.',
    1 => 'لو كان a مختلفًا في القوسين، فلن يكون العددان مترافقين.',
    2 => 'نفس bi موجود في القوسين؛ الذي سيتغير بعد قليل هو الإشارة فقط.',
    3 => 'مثل العددين 5 و-5: نفس العدد، لكن إشارة مختلفة.',
    4 => 'الحدان الأوسطان يتلاشيان، لذلك تبقى مربعات الحدين.',
    5 => 'هذه القاعدة هي التي تجعل الجزء التخيلي يتحول إلى عدد حقيقي.',
    6 => 'لأن b² مضروب في -1، وطرح الناتج السالب يصبح جمعًا.',
    _ => 'النتيجة لا تحتوي i؛ إنها مجموع مربعين حقيقيين.',
  };

  String _simpleText(int step) => switch (step) {
    0 => 'اقرأها هكذا: نفس القوس تقريبًا، لكن إشارة bi تغيّرت.',
    1 => 'a هو الرقم العادي، وهو لم يتغير.',
    2 => 'bi هو الجزء الذي فيه i، وهو نفسه أيضًا.',
    3 => 'موجب هنا، سالب هناك: لهذا هما مترافقان.',
    4 => 'مربع الأول ناقص مربع الثاني.',
    5 => 'اكتب فقط: i² = -1.',
    6 => 'a² ناقص سالب b² تساوي a² زائد b².',
    _ => 'احسب a × a، ثم b × b، ثم اجمع الناتجين.',
  };
}

class ComplexMultiplicationExamplesPage extends StatefulWidget {
  const ComplexMultiplicationExamplesPage({super.key});

  @override
  State<ComplexMultiplicationExamplesPage> createState() => _ComplexMultiplicationExamplesPageState();
}

class _ComplexMultiplicationExamplesPageState extends State<ComplexMultiplicationExamplesPage> {
  int firstStep = 0;
  bool firstFinished = false;

  @override
  Widget build(BuildContext context) => _LearningScaffold(
    title: 'أمثلة ضرب الأعداد المركبة',
    subtitle: 'ورقة واحدة نكتب عليها بهدوء، خطوة تحت خطوة',
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _LessonIllustration(icon: Icons.menu_book_rounded, label: firstFinished ? 'ممتاز، ننتقل إلى المرافق' : 'نكتب كل خطوة تحت التي قبلها', color: const Color(0xff2563eb)),
      const SizedBox(height: 14),
      _NotebookMultiplicationExample(
        visibleStep: firstStep,
        onNext: () => setState(() => firstStep = math.min(firstStep + 1, 9)),
        onRestart: () => setState(() { firstStep = 0; firstFinished = false; }),
        onFinished: () => setState(() => firstFinished = true),
      ),
      if (firstFinished) ...[
        const SizedBox(height: 18),
        const _ConjugatePracticeLesson(),
        const SizedBox(height: 18),
        const _MultiplicationCompleted(),
      ],
    ]),
  );
}

class _NotebookMultiplicationExample extends StatelessWidget {
  final int visibleStep;
  final VoidCallback onNext;
  final VoidCallback onRestart;
  final VoidCallback onFinished;
  const _NotebookMultiplicationExample({required this.visibleStep, required this.onNext, required this.onRestart, required this.onFinished});

  static const lines = [
    ('نبدأ بالمثال', '(√3 - 2i) × (3√3 + i)', Color(0xff2563eb)),
    ('نوزّع: √3 في 3√3', '√3 × 3√3 = 9', Color(0xff2563eb)),
    ('نوزّع: √3 في i', '√3 × i = √3i', Color(0xff2563eb)),
    ('نوزّع: -2i في 3√3', '-2i × 3√3 = -6√3i', Color(0xff2563eb)),
    ('نوزّع: -2i في i', '-2i × i = -2i²', Color(0xffb45309)),
    ('نجمع النواتج الأربعة', '9 + √3i - 6√3i - 2i²', Color(0xffb45309)),
    ('توقّف هنا: نبدّل i²', '-2i² = -2 × -1 = +2', Color(0xffb91c1c)),
    ('نجمع الأعداد الحقيقية', '9 + 2 = 11', Color(0xff15803d)),
    ('نجمع الحدود التي فيها i', '√3i - 6√3i = -5√3i', Color(0xff15803d)),
    ('الناتج النهائي', '11 - 5√3i', Color(0xff15803d)),
  ];

  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.all(18),
    child: CustomPaint(
      painter: _MultiplicationNotebookPainter(),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        decoration: BoxDecoration(color: const Color(0xfffffdf5), border: Border.all(color: const Color(0xffd9cda8)), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('المثال الأول: نكتب بهدوء', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xff1e3a8a))),
        const SizedBox(height: 8),
        const Text('الأزرق = الأعداد الأصلية، واللون البرتقالي = إشارة تغيّرت', textAlign: TextAlign.center, style: TextStyle(color: mutedInk)),
        const SizedBox(height: 16),
        ...List.generate(visibleStep + 1, (index) => _NotebookLine(index: index, title: lines[index].$1, expression: lines[index].$2, color: lines[index].$3, isPause: index == 6)),
        if (visibleStep == 6) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xffffe4e6), border: Border.all(color: const Color(0xffe11d48), width: 2), borderRadius: BorderRadius.circular(8)),
            child: const Column(children: [
              Text('انتبه جيداً', textAlign: TextAlign.center, style: TextStyle(color: Color(0xffbe123c), fontSize: 19, fontWeight: FontWeight.bold)),
              SizedBox(height: 6),
              Text('أي تربيع لـ i يساوي سالب واحد: i² = -1', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, height: 1.5)),
              Text('لذلك -2i² = -2 × -1 = +2؛ السالب في السالب موجب.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xff9f1239), height: 1.6)),
            ]),
          ),
        ],
        const SizedBox(height: 14),
        if (visibleStep < lines.length - 1)
          FilledButton.icon(onPressed: onNext, style: FilledButton.styleFrom(backgroundColor: const Color(0xff2563eb)), icon: const Icon(Icons.arrow_downward_rounded), label: Text(visibleStep == 6 ? 'فهمت، أكمل الحل' : 'فهمت هذه الخطوة'))
        else
          FilledButton.icon(onPressed: onFinished, style: FilledButton.styleFrom(backgroundColor: const Color(0xff15803d)), icon: const Icon(Icons.arrow_downward_rounded), label: const Text('فهمت، انتقل إلى مثال المرافق')),
        OutlinedButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('لماذا؟ اشرحها أكثر'),
              content: Text(visibleStep == 6 ? 'نحوّل -2i² إلى +2 لأن i² = -1، ثم السالب في السالب يصبح موجباً.' : 'كل سهم يقودنا إلى ناتج ضرب واحد. نكتب الناتج تحت السابق حتى لا نخلط بين الحقيقي والتخيلي.'),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('فهمت هذه الخطوة'))],
            ),
          ),
          icon: const Icon(Icons.help_outline),
          label: const Text('لماذا؟ اشرحها أكثر'),
        ),
        TextButton.icon(onPressed: onRestart, icon: const Icon(Icons.replay), label: const Text('أريد إعادة المثال')),
      ]),
      ),
    ),
  );
}

class _MultiplicationNotebookPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()..color = const Color(0xff93c5fd).withValues(alpha: .22)..strokeWidth = 1;
    for (var y = 42.0; y < size.height; y += 34) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _NotebookLine extends StatelessWidget {
  final int index;
  final String title;
  final String expression;
  final Color color;
  final bool isPause;
  const _NotebookLine({required this.index, required this.title, required this.expression, required this.color, required this.isPause});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (index > 0) const Align(alignment: Alignment.centerRight, child: Icon(Icons.arrow_downward_rounded, color: Color(0xff64748b), size: 20)),
      Text(title, textAlign: TextAlign.right, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Directionality(textDirection: TextDirection.ltr, child: Text(expression, textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold, height: 1.45))),
      if (isPause) const Text('← هنا ننتبه لقاعدة i² قبل أن نكمل', textAlign: TextAlign.center, style: TextStyle(color: Color(0xffbe123c), fontWeight: FontWeight.bold)),
    ]),
  );
}

class _ConjugatePracticeLesson extends StatefulWidget {
  const _ConjugatePracticeLesson();
  @override
  State<_ConjugatePracticeLesson> createState() => _ConjugatePracticeLessonState();
}

class _ConjugatePracticeLessonState extends State<_ConjugatePracticeLesson> {
  int step = 0;
  String? feedback;
  bool showWhy = false;

  @override
  Widget build(BuildContext context) => Panel(
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const _LearningHeader(icon: Icons.compare_arrows_rounded, color: Color(0xff15803d), title: 'مثال المرافق: نمسك الإشارة', subtitle: 'المرافق يغيّر إشارة الجزء التخيلي فقط'),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _LabeledComplex(value: '3 + 2i', label: 'الأصلي', color: const Color(0xff2563eb))),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward_rounded, color: Color(0xff64748b))),
        Expanded(child: _LabeledComplex(value: '3 - 2i', label: 'المرافق', color: const Color(0xff15803d))),
      ]),
      const SizedBox(height: 10),
      const Text('لإيجاد مرافق أي عدد مركب، نغيّر فقط إشارة الجزء التخيلي. الجزء الحقيقي يبقى نفسه.', textAlign: TextAlign.center, style: TextStyle(color: mutedInk, height: 1.6)),
      const Text('3 + 2i  →  3 - 2i   ↑ تغيّرت الإشارة، وبقي 3 كما هو', textAlign: TextAlign.center, style: TextStyle(color: Color(0xff15803d), fontWeight: FontWeight.bold, height: 1.6)),
      const Divider(height: 28),
      Text('نعرف C = 3 + 2i', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xff2563eb), fontSize: 19, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text('مرافق C = 3 - 2i', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xff15803d), fontSize: 19, fontWeight: FontWeight.bold)),
      const SizedBox(height: 14),
      _ConjugateStepBody(step: step),
      if (showWhy) const Padding(padding: EdgeInsets.only(top: 10), child: Text('نقارن الأجزاء المتشابهة: 3 مع 3، و2i مع -2i. لذلك نعرف بالضبط أي إشارة تغيّرت ولماذا.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xff1d4ed8), height: 1.6))),
      if (feedback != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(feedback!, textAlign: TextAlign.center, style: TextStyle(color: feedback!.startsWith('أحسنت') ? const Color(0xff15803d) : const Color(0xffb91c1c), fontWeight: FontWeight.bold, height: 1.5))),
      const SizedBox(height: 12),
      Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
        if (step < 5) FilledButton.icon(onPressed: () => setState(() { step++; feedback = null; }), style: FilledButton.styleFrom(backgroundColor: const Color(0xff15803d)), icon: const Icon(Icons.arrow_downward_rounded), label: const Text('فهمت هذه الخطوة')),
        OutlinedButton.icon(onPressed: () => setState(() => showWhy = true), icon: const Icon(Icons.help_outline), label: const Text('لماذا؟ اشرحها أكثر')),
        TextButton.icon(onPressed: () => setState(() { step = 0; feedback = null; showWhy = false; }), icon: const Icon(Icons.replay), label: const Text('أعد الخطوة')),
      ]),
      if (step == 5) ...[
        const SizedBox(height: 14),
        const Text('سؤال صغير: هل العددان مترافقان؟', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        const SizedBox(height: 8),
        Wrap(alignment: WrapAlignment.center, spacing: 10, children: [
          OutlinedButton(onPressed: () => setState(() => feedback = 'أحسنت! انظر: الجزء الحقيقي 3 بقي نفسه، وإشارة 2i فقط تغيّرت.'), child: const Text('نعم')),
          OutlinedButton(onPressed: () => setState(() => feedback = 'انظر جيداً: لوّن الإشارات والأجزاء الحقيقية والتخيلية. الحقيقي 3 بقي نفسه، والتخيلي فقط بدّل + إلى -. حاول مرة ثانية.'), child: const Text('لا')),
        ]),
      ],
    ]),
  );
}

class _LabeledComplex extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _LabeledComplex({required this.value, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Column(children: [
    Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(6)), child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold))),
    const SizedBox(height: 6),
    Directionality(textDirection: TextDirection.ltr, child: Text(value, style: TextStyle(color: color, fontSize: 23, fontWeight: FontWeight.bold))),
  ]);
}

class _ConjugateStepBody extends StatelessWidget {
  final int step;
  const _ConjugateStepBody({required this.step});
  @override
  Widget build(BuildContext context) {
    final content = switch (step) {
      0 => ('نجمع C مع مرافقه', 'C + مرافق C = (3 + 2i) + (3 - 2i)', 'نرتّب الحقيقي مع الحقيقي، والتخيلي مع التخيلي.'),
      1 => ('نركّز أولاً على الحقيقي', '3 + 3 = 6', 'العددان الحقيقيان 3 و3 جمعا فأعطيا 6.'),
      2 => ('ثم نركّز على التخيلي', '2i + (-2i) = 0i', 'موجب 2i وسالب 2i يلغي أحدهما الآخر.'),
      3 => ('نتيجة الجمع', '6 + 0i = 6', 'اختفى الجزء التخيلي لأنه صار صفراً.'),
      4 => ('نضرب العدد في مرافقه', '(3 + 2i)(3 - 2i) = 3² + 2²', 'إذا كان القوسان مترافقين: الأول تربيع زائد الثاني تربيع.'),
      _ => ('نحسب بهدوء', '3² = 9   ←   2² = 4   ←   9 + 4 = 13', 'إذن (3 + 2i)(3 - 2i) = 13.'),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(content.$1, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xff15803d))),
      const SizedBox(height: 8),
      Directionality(textDirection: TextDirection.ltr, child: Text(content.$2, textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: Color(0xff334155), height: 1.5))),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.arrow_forward_rounded, color: Color(0xff15803d), size: 20), const SizedBox(width: 6), Flexible(child: Text(content.$3, textAlign: TextAlign.center, style: const TextStyle(color: mutedInk, height: 1.5))), const SizedBox(width: 6), const Icon(Icons.arrow_back_rounded, color: Color(0xff15803d), size: 20)]),
    ]);
  }
}

class _MultiplicationExampleCard extends StatefulWidget {
  final String title;
  final String expression;
  final List<(String, String, String)> steps;
  final bool isLastExample;
  final VoidCallback onCompleted;
  const _MultiplicationExampleCard({super.key, required this.title, required this.expression, required this.steps, required this.isLastExample, required this.onCompleted});

  @override
  State<_MultiplicationExampleCard> createState() => _MultiplicationExampleCardState();
}

class _MultiplicationExampleCardState extends State<_MultiplicationExampleCard> {
  int visibleStep = 0;
  final Set<int> understoodSteps = {};
  final Set<int> simplerSteps = {};
  bool showWhy = false;
  bool showWrongHint = false;

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[visibleStep];
    final understood = understoodSteps.contains(visibleStep);
    return Panel(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 420),
        transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: SlideTransition(position: Tween<Offset>(begin: const Offset(.08, 0), end: Offset.zero).animate(animation), child: child)),
        child: Column(key: ValueKey(visibleStep), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _MathLine(widget.expression),
          const Divider(height: 24),
          Text('الخطوة ${visibleStep + 1} من ${widget.steps.length}', style: const TextStyle(color: Color(0xffa56518), fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(step.$1, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xffa56518))),
          const SizedBox(height: 8),
          _MathLine(step.$2),
          const SizedBox(height: 8),
          Text('السبب: ${step.$3}', style: const TextStyle(color: mutedInk, height: 1.5)),
          if (showWhy) ...[
            const SizedBox(height: 10),
            Text(_whyStep(step), style: const TextStyle(color: Color(0xff1d4ed8), height: 1.5)),
          ],
          if (showWrongHint) ...[
            const SizedBox(height: 10),
            const Text('توقّف عند الإشارة: افحص هل i² تحوّل إلى -1، وهل جمعت الحقيقي مع الحقيقي والتخيلي مع التخيلي.', style: TextStyle(color: Color(0xffb91c1c), height: 1.5)),
          ],
          if (simplerSteps.contains(visibleStep)) ...[
            const SizedBox(height: 10),
            Text(_simpleStep(step), style: const TextStyle(color: Color(0xffa56518), height: 1.5)),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => setState(() { understoodSteps.add(visibleStep); simplerSteps.remove(visibleStep); showWrongHint = false; }), icon: const Icon(Icons.check), label: const Text('فهمت'))),
            const SizedBox(width: 8),
            Expanded(child: TextButton.icon(onPressed: () => setState(() { simplerSteps.add(visibleStep); showWrongHint = true; }), icon: const Icon(Icons.help_outline), label: const Text('لم أفهم'))),
          ]),
          const SizedBox(height: 8),
          Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
            TextButton.icon(onPressed: () => setState(() => showWhy = true), icon: const Icon(Icons.question_mark), label: const Text('ليش؟')),
            TextButton.icon(onPressed: () => setState(() { showWhy = false; showWrongHint = false; }), icon: const Icon(Icons.replay), label: const Text('أعد الخطوة')),
          ]),
          if (understood) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: visibleStep == widget.steps.length - 1 ? widget.onCompleted : () => setState(() { visibleStep++; showWhy = false; showWrongHint = false; }),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xffc47a22)),
              icon: const Icon(Icons.arrow_back_rounded),
              label: Text(visibleStep == widget.steps.length - 1 ? widget.isLastExample ? 'فهمت، إنهاء الأمثلة' : 'فهمت، افتح المثال الثاني' : 'فهمت، الخطوة التالية'),
            ),
          ],
        ]),
      ),
    );
  }

  String _simpleStep((String, String, String) step) {
    if (step.$1.contains('i²')) return 'عندما ترى i²، استبدلها مباشرةً بـ -1 ثم أكمل الحساب.';
    if (step.$1.contains('الحدود')) return 'اكتب نواتج الضرب الأربعة جنباً إلى جنب قبل جمع المتشابه.';
    if (step.$1.contains('الحقيقي')) return 'اجمع الأرقام التي لا تحتوي i وحدها.';
    if (step.$1.contains('التخيلي')) return 'اجمع معاملات i وحدها واترك i في الناتج.';
    if (step.$1.contains('النهائي')) return 'اكتب العدد الحقيقي أولاً، ثم الجزء التخيلي الذي يحتوي i.';
    return 'اضرب بهدوء وتابع السهم من الحد الأول إلى كل حدود القوس الثاني.';
  }

  String _whyStep((String, String, String) step) {
    if (step.$1.contains('i²')) return 'لأن i × i يساوي i²، وقاعدة i² = -1 تغيّر هذا الجزء إلى عدد حقيقي.';
    if (step.$1.contains('الحدود')) return 'التوزيع يعني أن كل حد في القوس الأول يلتقي بكل حد في القوس الثاني.';
    if (step.$1.contains('الحقيقي')) return 'الحدود التي لا تحتوي i تبقى حقيقية، لذلك نجمعها وحدها.';
    if (step.$1.contains('التخيلي')) return 'نترك i كما هي ونجمع الأرقام التي قبلها فقط.';
    return 'ننتقل ببطء حتى نرى سبب كل إشارة وكل ناتج قبل الخطوة التالية.';
  }
}

class _MultiplicationCompleted extends StatelessWidget {
  const _MultiplicationCompleted();

  @override
  Widget build(BuildContext context) => const Panel(
    child: Column(children: [
      _LessonIllustration(icon: Icons.emoji_events_outlined, label: 'أحسنت، اكتملت أمثلة الضرب', color: Color(0xffc47a22)),
      SizedBox(height: 14),
      Text('تعلمت توزيع الضرب، واستبدال i² بسالب واحد، ثم جمع الحقيقي والتخيلي بالشكل القياسي.', textAlign: TextAlign.center, style: TextStyle(color: mutedInk, height: 1.6)),
    ]),
  );
}

class _LearningScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  const _LearningScaffold({required this.title, required this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) => Shell(
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 520),
              curve: Curves.easeOutCubic,
              builder: (context, value, animatedChild) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 18 * (1 - value)),
                  child: animatedChild,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: mutedInk, fontSize: 15)),
                  const SizedBox(height: 20),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _LearningHeader extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  const _LearningHeader({required this.icon, required this.color, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Panel(
    child: Row(
      children: [
        CircleAvatar(backgroundColor: color.withValues(alpha: .12), foregroundColor: color, child: Icon(icon)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: mutedInk, height: 1.4)),
        ])),
      ],
    ),
  );
}

class _LessonIllustration extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _LessonIllustration({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 420),
    curve: Curves.easeOutCubic,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: color.withValues(alpha: .18)),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 74,
          height: 58,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedScale(
                scale: 1,
                duration: const Duration(milliseconds: 420),
                child: CircleAvatar(
                  radius: 27,
                  backgroundColor: color.withValues(alpha: .16),
                  child: Icon(icon, color: color, size: 31),
                ),
              ),
              Positioned(
                top: 0,
                right: 4,
                child: Icon(Icons.auto_awesome, color: color.withValues(alpha: .72), size: 17),
              ),
              Positioned(
                bottom: 1,
                left: 3,
                child: Icon(Icons.menu_book_rounded, color: color.withValues(alpha: .62), size: 18),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: Text(
              label,
              key: ValueKey(label),
              style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    ),
  );
}

class _LearningTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;
  const _LearningTile({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap, this.enabled = true});

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : .62,
    child: Panel(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            CircleAvatar(backgroundColor: color.withValues(alpha: .12), foregroundColor: color, child: Icon(icon)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: mutedInk)),
            ])),
            const Icon(Icons.chevron_left_rounded, color: mutedInk),
          ]),
        ),
      ),
    ),
  );
}

class _ChapterTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool active;
  final VoidCallback? onTap;
  const _ChapterTile({required this.title, required this.subtitle, this.active = false, this.onTap});

  @override
  Widget build(BuildContext context) => Panel(
    padding: EdgeInsets.zero,
    child: InkWell(
      onTap: active ? onTap : null,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(active ? Icons.lock_open_rounded : Icons.lock_outline_rounded, color: active ? emerald : mutedInk),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: active ? ink : mutedInk)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: active ? emerald : mutedInk)),
          ])),
          if (active) const Icon(Icons.chevron_left_rounded, color: emerald),
        ]),
      ),
    ),
  );
}

class _NoteCard extends StatelessWidget {
  final int number;
  final String title;
  final String body;
  final String simplerBody;
  final bool isSimpler;
  final bool isDone;
  final VoidCallback onUnderstood;
  final VoidCallback onNotUnderstood;
  const _NoteCard({required this.number, required this.title, required this.body, required this.simplerBody, required this.isSimpler, required this.isDone, required this.onUnderstood, required this.onNotUnderstood});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 360 + number * 80),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(offset: Offset(0, 12 * (1 - value)), child: child),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .92),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isDone ? emerald.withValues(alpha: .45) : const Color(0xffdfe7e1)),
          boxShadow: const [BoxShadow(color: Color(0x120d3b2e), blurRadius: 22, offset: Offset(0, 8))],
        ),
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: CircleAvatar(
              key: ValueKey(isDone),
              radius: 16,
              backgroundColor: isDone ? burgundy : emerald,
              foregroundColor: Colors.white,
              child: Icon(isDone ? Icons.check : Icons.edit_note_rounded, size: 18),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: isDone
                ? const Icon(Icons.check_circle, key: ValueKey('done'), color: emerald)
                : const Icon(Icons.arrow_forward_ios_rounded, key: ValueKey('pending'), color: Color(0xffcbd5e1), size: 16),
          ),
        ]),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 360),
          transitionBuilder: (child, animation) => SizeTransition(
            sizeFactor: animation,
            alignment: Alignment.topCenter,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: Text(
            isSimpler ? simplerBody : body,
            key: ValueKey(isSimpler),
            style: TextStyle(color: isSimpler ? burgundy : mutedInk, height: 1.65),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: onUnderstood, icon: const Icon(Icons.check), label: const Text('فهمت'))),
          const SizedBox(width: 8),
          Expanded(child: TextButton.icon(onPressed: onNotUnderstood, icon: const Icon(Icons.help_outline), label: const Text('لم أفهم'))),
        ]),
      ]),
      ),
    ),
  );
}

class _ExampleProgress extends StatelessWidget {
  final int currentExample;
  final bool completed;
  const _ExampleProgress({required this.currentExample, required this.completed});

  @override
  Widget build(BuildContext context) => Panel(
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.auto_stories_outlined, color: burgundy),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            completed ? 'اكتملت أمثلة الجمع' : 'المثال ${currentExample + 1} من 2',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ),
        Icon(completed ? Icons.verified_rounded : Icons.route_rounded, color: completed ? emerald : burgundy),
      ]),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: LinearProgressIndicator(
          minHeight: 8,
          value: completed ? 1 : (currentExample + 1) / 2,
          backgroundColor: const Color(0xffe2e8f0),
          color: completed ? emerald : burgundy,
        ),
      ),
      const SizedBox(height: 7),
      Text(
        completed ? 'أحسنت، أنهيت كل الأمثلة بالتسلسل.' : 'أكمل خطوات هذا المثال لفتح المثال التالي.',
        style: const TextStyle(color: mutedInk),
      ),
    ]),
  );
}

class _ExamplesCompleted extends StatelessWidget {
  const _ExamplesCompleted({super.key});

  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _LessonIllustration(
          icon: Icons.emoji_events_outlined,
          label: 'رائع، اكتملت أمثلة الجمع',
          color: emerald,
        ),
        const SizedBox(height: 14),
        const Text(
          'أصبحت تعرف كيف تحافظ على الأقواس وتجمع الحقيقي مع الحقيقي والتخيلي مع التخيلي.',
          textAlign: TextAlign.center,
          style: TextStyle(color: mutedInk, height: 1.6),
        ),
        const SizedBox(height: 20),
        const Text(
          'هل تريد الانتقال لتعرف كيف تقوم بطرح الأعداد المركبة؟',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: ink),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const ComplexAdditionLessonPage()),
                ),
                icon: const Icon(Icons.school_outlined),
                label: const Text('نعم'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const HomePage()),
                  (route) => false,
                ),
                icon: const Icon(Icons.home_outlined),
                label: const Text('لا، الرئيسية'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _AdditionExampleCard extends StatefulWidget {
  final String title;
  final String expression;
  final List<(String, String, String)> steps;
  final bool isLastExample;
  final VoidCallback onSkillHelp;
  final VoidCallback onCompleted;
  const _AdditionExampleCard({super.key, required this.title, required this.expression, required this.steps, required this.isLastExample, required this.onSkillHelp, required this.onCompleted});

  @override
  State<_AdditionExampleCard> createState() => _AdditionExampleCardState();
}

class _AdditionExampleCardState extends State<_AdditionExampleCard> {
  int visibleSteps = 1;

  @override
  Widget build(BuildContext context) => Panel(
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      _MathLine(widget.expression),
      const Divider(height: 24),
      AnimatedSize(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: List.generate(visibleSteps, (index) => TweenAnimationBuilder<double>(
            key: ValueKey(index),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(offset: Offset(0, 10 * (1 - value)), child: child),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Icon(Icons.arrow_back_rounded, color: burgundy, size: 18),
                  const SizedBox(width: 6),
                  Expanded(child: Text(widget.steps[index].$1, style: const TextStyle(fontWeight: FontWeight.bold, color: burgundy))),
                ]),
                const SizedBox(height: 5),
                _MathLine(widget.steps[index].$2),
                const SizedBox(height: 5),
                Text('السبب: ${widget.steps[index].$3}', style: const TextStyle(color: mutedInk, height: 1.45)),
              ]),
            ),
          )),
        ),
      ),
      if (visibleSteps < widget.steps.length)
        FilledButton.icon(
          onPressed: () => setState(() => visibleSteps++),
          icon: const Icon(Icons.arrow_downward_rounded),
          label: Text('الخطوة التالية (${visibleSteps + 1} من ${widget.steps.length})'),
        ),
      if (visibleSteps == widget.steps.length)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'إذا فهمت خطوات المثال، اضغط الزر للانتقال.',
              textAlign: TextAlign.center,
              style: TextStyle(color: mutedInk, fontSize: 13),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: widget.onCompleted,
              style: FilledButton.styleFrom(backgroundColor: burgundy),
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: Text(widget.isLastExample ? 'فهمت، إنهاء الأمثلة' : 'فهمت، افتح المثال التالي'),
            ),
          ],
        ),
      OutlinedButton.icon(
        onPressed: widget.onSkillHelp,
        icon: const Icon(Icons.help_outline),
        label: const Text('هل ترغب بشرح هذه الخطوة؟'),
      ),
    ]),
  );
}

class _MathLine extends StatelessWidget {
  final String text;
  const _MathLine(this.text);

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Container(
      constraints: const BoxConstraints(minHeight: 62),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xfffffdf5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xffd8d4c6)),
        boxShadow: const [
          BoxShadow(color: Color(0x120f172a), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: CustomPaint(
        painter: _NotebookPaperPainter(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(38, 15, 14, 15),
          child: Center(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: ink),
            ),
          ),
        ),
      ),
    ),
  );
}

class _NotebookPaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xffcbddea)
      ..strokeWidth = 1;
    for (var y = 15.5; y < size.height; y += 25) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    final marginPaint = Paint()
      ..color = const Color(0xffe7a6a1)
      ..strokeWidth = 1.2;
    canvas.drawLine(const Offset(27, 0), Offset(27, size.height), marginPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MillionQuestion {
  final String category;
  final String text;
  final List<String> options;
  final int answer;
  final String difficulty;

  const MillionQuestion({
    required this.category,
    required this.text,
    required this.options,
    required this.answer,
    this.difficulty = 'متوسط',
  });
}

class MillionRoadPage extends StatefulWidget {
  const MillionRoadPage({super.key});

  @override
  State<MillionRoadPage> createState() => _MillionRoadPageState();
}

class _MillionRoadPageState extends State<MillionRoadPage> {
  static const prizeLadder = [
    10,
    20,
    30,
    40,
    50,
    100,
    200,
    500,
    1000,
    5000,
    10000,
    100000,
    250000,
    500000,
    750000,
    1000000,
  ];

  static const questions = [
    MillionQuestion(category: 'رياضيات', difficulty: 'سهل', text: 'ما قيمة الجذر التربيعي للعدد 144؟', options: ['10', '11', '12', '14'], answer: 2),
    MillionQuestion(category: 'رياضيات', difficulty: 'سهل', text: 'إذا كان 2x = 10، فما قيمة x؟', options: ['2', '5', '10', '20'], answer: 1),
    MillionQuestion(category: 'رياضيات', difficulty: 'متوسط', text: 'ما مشتقة x²؟', options: ['x', '2x', 'x³', '2'], answer: 1),
    MillionQuestion(category: 'رياضيات', difficulty: 'سهل', text: 'ما قيمة 5²؟', options: ['10', '15', '20', '25'], answer: 3),
    MillionQuestion(category: 'رياضيات', difficulty: 'سهل', text: 'أي من الآتي يمثل عدداً أولياً؟', options: ['9', '15', '17', '21'], answer: 2),
    MillionQuestion(category: 'رياضيات', difficulty: 'سهل', text: 'مجموع زوايا المثلث يساوي:', options: ['90°', '180°', '270°', '360°'], answer: 1),
    MillionQuestion(category: 'رياضيات', difficulty: 'سهل', text: 'ما قيمة 3³؟', options: ['9', '18', '27', '81'], answer: 2),
    MillionQuestion(category: 'رياضيات', difficulty: 'سهل', text: 'إذا كان x + 7 = 12، فإن x يساوي:', options: ['3', '4', '5', '6'], answer: 2),
    MillionQuestion(category: 'فيزياء', difficulty: 'سهل', text: 'ما وحدة قياس القوة في النظام الدولي؟', options: ['جول', 'نيوتن', 'واط', 'فولت'], answer: 1),
    MillionQuestion(category: 'فيزياء', difficulty: 'سهل', text: 'ما وحدة قياس الطاقة؟', options: ['جول', 'أمبير', 'متر', 'تسلا'], answer: 0),
    MillionQuestion(category: 'فيزياء', difficulty: 'سهل', text: 'ما وحدة قياس شدة التيار الكهربائي؟', options: ['فولت', 'أوم', 'أمبير', 'واط'], answer: 2),
    MillionQuestion(category: 'فيزياء', difficulty: 'سهل', text: 'الجهاز المستخدم لقياس شدة التيار الكهربائي هو:', options: ['الأميتر', 'الفولتميتر', 'البارومتر', 'الترمومتر'], answer: 0),
    MillionQuestion(category: 'فيزياء', difficulty: 'سهل', text: 'ما وحدة قياس المقاومة الكهربائية؟', options: ['واط', 'أوم', 'جول', 'كولوم'], answer: 1),
    MillionQuestion(category: 'فيزياء', difficulty: 'متوسط', text: 'سرعة الضوء في الفراغ تقارب:', options: ['3×10⁸ m/s', '3×10⁴ m/s', '3×10⁵ m/s', '3×10² m/s'], answer: 0),
    MillionQuestion(category: 'فيزياء', difficulty: 'متوسط', text: 'أي كمية تعبّر عن معدل تغير السرعة بالنسبة للزمن؟', options: ['الكتلة', 'التسارع', 'الطاقة', 'الشغل'], answer: 1),
    MillionQuestion(category: 'فيزياء', difficulty: 'سهل', text: 'وحدة قياس القدرة هي:', options: ['جول', 'نيوتن', 'واط', 'أوم'], answer: 2),
    MillionQuestion(category: 'كيمياء', difficulty: 'سهل', text: 'ما الرمز الكيميائي للأوكسجين؟', options: ['O', 'H', 'N', 'C'], answer: 0),
    MillionQuestion(category: 'كيمياء', difficulty: 'سهل', text: 'ما الرمز الكيميائي للهيدروجين؟', options: ['He', 'H', 'Hg', 'Ho'], answer: 1),
    MillionQuestion(category: 'كيمياء', difficulty: 'سهل', text: 'ما الصيغة الكيميائية للماء؟', options: ['CO₂', 'O₂', 'H₂O', 'NaCl'], answer: 2),
    MillionQuestion(category: 'كيمياء', difficulty: 'سهل', text: 'ما الرمز الكيميائي للصوديوم؟', options: ['S', 'So', 'Na', 'N'], answer: 2),
    MillionQuestion(category: 'كيمياء', difficulty: 'سهل', text: 'ما الرمز الكيميائي للحديد؟', options: ['Ir', 'Fe', 'F', 'H'], answer: 1),
    MillionQuestion(category: 'كيمياء', difficulty: 'سهل', text: 'أي عنصر رمزه C؟', options: ['الكالسيوم', 'الكربون', 'الكلور', 'النحاس'], answer: 1),
    MillionQuestion(category: 'كيمياء', difficulty: 'متوسط', text: 'العدد الذري يمثل عدد:', options: ['البروتونات', 'المركبات', 'الجزيئات', 'الروابط'], answer: 0),
    MillionQuestion(category: 'كيمياء', difficulty: 'سهل', text: 'أي جسيم يحمل شحنة سالبة؟', options: ['البروتون', 'النيوترون', 'الإلكترون', 'النواة'], answer: 2),
    MillionQuestion(category: 'كيمياء', difficulty: 'سهل', text: 'أي جسيم يحمل شحنة موجبة؟', options: ['الإلكترون', 'البروتون', 'النيوترون', 'الفوتون'], answer: 1),
    MillionQuestion(category: 'أحياء', difficulty: 'متوسط', text: 'أين توجد المادة الوراثية DNA بصورة رئيسية في الخلية حقيقية النواة؟', options: ['النواة', 'الغشاء فقط', 'الجدار الخلوي', 'الفجوة'], answer: 0),
    MillionQuestion(category: 'أحياء', difficulty: 'سهل', text: 'ما الوحدة الأساسية لبناء جسم الكائن الحي؟', options: ['النسيج', 'العضو', 'الخلية', 'الجهاز'], answer: 2),
    MillionQuestion(category: 'أحياء', difficulty: 'سهل', text: 'أي عضو مسؤول بصورة رئيسية عن ضخ الدم؟', options: ['الرئة', 'القلب', 'الكلية', 'المعدة'], answer: 1),
    MillionQuestion(category: 'أحياء', difficulty: 'متوسط', text: 'أين يحدث التبادل الغازي في الرئتين؟', options: ['القصبة الهوائية', 'الحويصلات الهوائية', 'الحنجرة', 'البلعوم'], answer: 1),
    MillionQuestion(category: 'أحياء', difficulty: 'سهل', text: 'ما وظيفة كريات الدم الحمراء الأساسية؟', options: ['نقل الأوكسجين', 'هضم الطعام', 'إنتاج البول', 'نقل الإشارات العصبية'], answer: 0),
    MillionQuestion(category: 'أحياء', difficulty: 'متوسط', text: 'ما العضو المسؤول بصورة أساسية عن تنقية الدم وتكوين البول؟', options: ['القلب', 'الكلية', 'البنكرياس', 'الرئة'], answer: 1),
    MillionQuestion(category: 'أحياء', difficulty: 'سهل', text: 'أي جزيء يحمل المعلومات الوراثية؟', options: ['DNA', 'H₂O', 'NaCl', 'O₂'], answer: 0),
    MillionQuestion(category: 'English', difficulty: 'سهل', text: 'ما معنى كلمة Student؟', options: ['معلم', 'طالب', 'طبيب', 'مهندس'], answer: 1),
    MillionQuestion(category: 'English', difficulty: 'سهل', text: 'ما الماضي من الفعل go؟', options: ['goed', 'gone', 'went', 'going'], answer: 2),
    MillionQuestion(category: 'English', difficulty: 'سهل', text: 'ما جمع كلمة child؟', options: ['childs', 'children', 'childes', 'child'], answer: 1),
    MillionQuestion(category: 'English', difficulty: 'سهل', text: 'أي كلمة تعني كتاب بالإنجليزية؟', options: ['Book', 'Door', 'Table', 'School'], answer: 0),
    MillionQuestion(category: 'English', difficulty: 'سهل', text: 'ما عكس كلمة big؟', options: ['tall', 'small', 'long', 'high'], answer: 1),
    MillionQuestion(category: 'English', difficulty: 'سهل', text: 'أكمل: I ___ a student.', options: ['is', 'are', 'am', 'be'], answer: 2),
    MillionQuestion(category: 'English', difficulty: 'سهل', text: 'أكمل: He ___ to school every day.', options: ['go', 'goes', 'going', 'gone'], answer: 1),
    MillionQuestion(category: 'English', difficulty: 'سهل', text: 'أي ضمير يُستخدم عادةً للإشارة إلى مجموعة من الأشخاص؟', options: ['He', 'She', 'It', 'They'], answer: 3),
    MillionQuestion(category: 'مهارات الدراسة', difficulty: 'سهل', text: 'أي من التالي يُعد طريقة جيدة للاستعداد للامتحان؟', options: ['المراجعة المنظمة', 'ترك جميع المواد لليلة الأخيرة', 'عدم حل الأسئلة', 'عدم النوم مطلقاً'], answer: 0),
    MillionQuestion(category: 'مهارات الدراسة', difficulty: 'متوسط', text: 'عند مواجهة مسألة رياضية صعبة، ما التصرف الأفضل؟', options: ['تركها دائماً', 'تحليل المعطيات ومحاولة تطبيق القوانين', 'اختيار جواب عشوائي مباشرة', 'حذف السؤال'], answer: 1),
    MillionQuestion(category: 'مهارات الدراسة', difficulty: 'سهل', text: 'ما الذي يساعد الطالب على اكتشاف نقاط ضعفه؟', options: ['الاختبارات والمراجعة', 'عدم حل الأسئلة', 'تجاهل الأخطاء', 'عدم الدراسة'], answer: 0),
    MillionQuestion(category: 'مهارات الدراسة', difficulty: 'متوسط', text: 'ما أفضل طريقة لتثبيت قانون فيزيائي؟', options: ['فهمه وتطبيقه على مسائل', 'قراءته مرة واحدة', 'تجاهله', 'حفظ اسمه فقط'], answer: 0),
    MillionQuestion(category: 'مهارات الدراسة', difficulty: 'سهل', text: 'لماذا يُنصح بمراجعة الأخطاء بعد الاختبار؟', options: ['لمعرفة سبب الخطأ وعدم تكراره', 'لزيادة الأخطاء', 'لتجنب الدراسة', 'لا توجد فائدة'], answer: 0),
    MillionQuestion(category: 'مهارات الدراسة', difficulty: 'سهل', text: 'ما فائدة الجدول الدراسي؟', options: ['تنظيم الوقت والمواد', 'إلغاء الدراسة', 'زيادة المشتتات', 'منع المراجعة'], answer: 0),
    MillionQuestion(category: 'مهارات الدراسة', difficulty: 'متوسط', text: 'عند دراسة عدة مواد، الأفضل هو:', options: ['تنظيم الوقت بينها حسب الحاجة', 'دراسة جميعها في اللحظة نفسها', 'ترك المواد الصعبة', 'عدم تحديد وقت'], answer: 0),
    MillionQuestion(category: 'مهارات الدراسة', difficulty: 'سهل', text: 'أيهما أفضل لفهم الرياضيات؟', options: ['حل المسائل والتدريب', 'قراءة أسماء القوانين فقط', 'عدم استخدام القوانين', 'حفظ الإجابات دون فهم'], answer: 0),
    MillionQuestion(category: 'مهارات الدراسة', difficulty: 'سهل', text: 'ما فائدة أخذ استراحات مناسبة أثناء الدراسة الطويلة؟', options: ['المساعدة على استعادة التركيز', 'نسيان جميع المعلومات', 'إلغاء الحاجة للنوم', 'الاستغناء عن المراجعة'], answer: 0),
    MillionQuestion(category: 'مهارات الدراسة', difficulty: 'متوسط', text: 'إذا اكتشف الطالب أن لديه ضعفاً في فصل معين، ما الأفضل؟', options: ['تجاهله', 'مراجعته وحل أسئلة إضافية عليه', 'ترك المادة بالكامل', 'الانتظار إلى يوم الامتحان'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'سهل', text: 'ما هي الدالة الرئيسية التي يبدأ منها تنفيذ برنامج C++؟', options: ['start()', 'run()', 'main()', 'begin()'], answer: 2),
    MillionQuestion(category: 'C++', difficulty: 'سهل', text: 'أي رمز يُستخدم لإنهاء التعليمة في C++؟', options: [':', ';', ',', '.'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'سهل', text: 'أي نوع بيانات يُستخدم لتخزين الأعداد الصحيحة؟', options: ['int', 'string', 'bool', 'char'], answer: 0),
    MillionQuestion(category: 'C++', difficulty: 'سهل', text: 'أي نوع بيانات يُستخدم عادةً لتخزين عدد عشري؟', options: ['char', 'bool', 'float', 'int'], answer: 2),
    MillionQuestion(category: 'C++', difficulty: 'سهل', text: 'أي أمر يُستخدم لإظهار البيانات على الشاشة؟', options: ['cin', 'cout', 'input', 'scan'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'سهل', text: 'أي أمر يُستخدم لاستقبال البيانات من المستخدم؟', options: ['cout', 'print', 'cin', 'output'], answer: 2),
    MillionQuestion(category: 'C++', difficulty: 'سهل', text: 'ما الرمز المستخدم لعملية الجمع؟', options: ['-', '*', '+', '/'], answer: 2),
    MillionQuestion(category: 'C++', difficulty: 'سهل', text: 'ما الرمز المستخدم لعملية الضرب؟', options: ['*', '+', '%', '='], answer: 0),
    MillionQuestion(category: 'C++', difficulty: 'سهل', text: 'ما العامل المستخدم للتحقق من تساوي قيمتين؟', options: ['=', '==', '!=', '>='], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'سهل', text: 'أي كلمة تُستخدم لإنشاء شرط؟', options: ['for', 'while', 'if', 'return'], answer: 2),
    MillionQuestion(category: 'C++', difficulty: 'سهل', text: 'أي كلمة تُستخدم لتنفيذ كود عندما يكون شرط if غير صحيح؟', options: ['else', 'case', 'break', 'continue'], answer: 0),
    MillionQuestion(category: 'C++', difficulty: 'سهل', text: 'أي حلقة مناسبة عندما نعرف عدد مرات التكرار؟', options: ['if', 'for', 'switch', 'else'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'سهل', text: 'أي حلقة تستمر بالتكرار ما دام الشرط صحيحاً؟', options: ['while', 'if', 'switch', 'return'], answer: 0),
    MillionQuestion(category: 'C++', difficulty: 'سهل', text: 'أي نوع بيانات يُستخدم لتخزين حرف واحد؟', options: ['int', 'char', 'float', 'bool'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'سهل', text: 'أي نوع يُستخدم لتخزين قيمة true أو false؟', options: ['string', 'double', 'bool', 'char'], answer: 2),
    MillionQuestion(category: 'C++', difficulty: 'سهل', text: 'أي كلمة تُستخدم للخروج من الحلقة مباشرةً؟', options: ['stop', 'exit', 'break', 'close'], answer: 2),
    MillionQuestion(category: 'C++', difficulty: 'سهل', text: 'ما الرمز المستخدم لكتابة تعليق من سطر واحد؟', options: ['//', '##', '--', '**'], answer: 0),
    MillionQuestion(category: 'C++', difficulty: 'سهل', text: 'أي عامل يُستخدم للحصول على باقي القسمة؟', options: ['/', '%', '*', '+'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'سهل', text: 'أي كلمة تُستخدم لإرجاع قيمة من الدالة؟', options: ['break', 'return', 'cout', 'void'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'سهل', text: 'أي مكتبة تُستخدم عادةً مع cin وcout؟', options: ['<math>', '<string>', '<iostream>', '<input>'], answer: 2),
    MillionQuestion(category: 'C++', difficulty: 'سهل', text: 'أي كلمة تُستخدم لتعريف ثابت لا تتغير قيمته؟', options: ['fixed', 'const', 'static', 'final'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'سهل', text: 'ما نوع البيانات المناسب لتخزين نص؟', options: ['string', 'char', 'bool', 'short'], answer: 0),
    MillionQuestion(category: 'C++', difficulty: 'سهل', text: 'أي عامل يُستخدم لإسناد قيمة إلى متغير؟', options: ['==', '=', '=>', '!='], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'سهل', text: 'ما نتيجة التعبير 7 % 3؟', options: ['1', '2', '3', '0'], answer: 0),
    MillionQuestion(category: 'C++', difficulty: 'سهل', text: 'أي كلمة تُستخدم لاختيار حالة من عدة حالات؟', options: ['select', 'switch', 'choose', 'caseof'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'سهل', text: 'أي كلمة تُستخدم مع switch لتحديد خيار؟', options: ['when', 'option', 'case', 'branch'], answer: 2),
    MillionQuestion(category: 'C++', difficulty: 'سهل', text: 'أي كلمة تمنع المرور إلى الحالة التالية في switch؟', options: ['stop', 'break', 'next', 'leave'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'متوسط', text: 'ما الفهرس الأول في مصفوفة C++؟', options: ['0', '1', '-1', 'حسب حجمها'], answer: 0),
    MillionQuestion(category: 'C++', difficulty: 'متوسط', text: 'أي صيغة تنشئ مصفوفة من 5 أعداد صحيحة؟', options: ['int a(5);', 'int a[5];', 'array int a;', 'int[5] a;'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'متوسط', text: 'ما الدالة التي تعيد حجم string؟', options: ['length()', 'sizeOf()', 'count()', 'capacityOf()'], answer: 0),
    MillionQuestion(category: 'C++', difficulty: 'متوسط', text: 'أي حاوية تكبر حجمها تلقائياً؟', options: ['array', 'vector', 'tuple', 'pair'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'متوسط', text: 'ما الرمز المستخدم للوصول إلى عضو عبر مؤشر؟', options: ['.', '::', '->', '&'], answer: 2),
    MillionQuestion(category: 'C++', difficulty: 'متوسط', text: 'ما الرمز الذي يعيد عنوان متغير؟', options: ['*', '&', '#', '@'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'متوسط', text: 'ما الرمز الذي يفك إشارة المؤشر؟', options: ['*', '&', '->', '::'], answer: 0),
    MillionQuestion(category: 'C++', difficulty: 'متوسط', text: 'ماذا تعني كلمة void في نوع إرجاع الدالة؟', options: ['تعيد رقماً', 'لا تعيد قيمة', 'تعمل مرة واحدة', 'تقبل void فقط'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'متوسط', text: 'ما فائدة default في switch؟', options: ['تكرار الحالة', 'الخيار عند عدم تطابق أي حالة', 'إنهاء البرنامج', 'تعريف متغير'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'متوسط', text: 'أي عامل منطقي يعني AND؟', options: ['||', '&&', '!', '&'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'متوسط', text: 'أي عامل منطقي يعني OR؟', options: ['&&', '||', '!', '|'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'متوسط', text: 'ما نتيجة !false؟', options: ['false', 'true', '0 فقط', 'خطأ تجميع'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'متوسط', text: 'ما الكلمة التي تنشئ كائناً في الذاكرة الديناميكية؟', options: ['create', 'new', 'alloc', 'make'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'متوسط', text: 'ما الكلمة التي تحرر كائناً أنشئ بـ new؟', options: ['free', 'remove', 'delete', 'clear'], answer: 2),
    MillionQuestion(category: 'C++', difficulty: 'متوسط', text: 'ما وظيفة namespace؟', options: ['تسريع البرنامج', 'تجنب تعارض الأسماء', 'حجز الذاكرة', 'إنشاء حلقة'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'متوسط', text: 'ما الكلمة المستخدمة لتعريف صنف؟', options: ['object', 'class', 'structural', 'typeclass'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'متوسط', text: 'ما الدالة التي تعمل تلقائياً عند إنشاء الكائن؟', options: ['starter', 'constructor', 'builder', 'initiate'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'متوسط', text: 'ما الدالة التي تعمل عند تدمير الكائن؟', options: ['destructor', 'destroyer', 'remove', 'finalizer'], answer: 0),
    MillionQuestion(category: 'C++', difficulty: 'متوسط', text: 'أي محدد وصول يجعل العضو متاحاً من خارج الصنف؟', options: ['private', 'hidden', 'public', 'external'], answer: 2),
    MillionQuestion(category: 'C++', difficulty: 'متوسط', text: 'أي محدد وصول يجعل العضو متاحاً داخل الصنف والوريث؟', options: ['protected', 'shared', 'internal', 'safe'], answer: 0),
    MillionQuestion(category: 'C++', difficulty: 'صعب', text: 'ماذا تسمى إعادة تعريف دالة في صنف مشتق؟', options: ['overloading', 'overriding', 'wrapping', 'hiding'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'صعب', text: 'ماذا تسمى دالتان بالاسم نفسه ومعاملات مختلفة؟', options: ['overloading', 'overriding', 'inheritance', 'casting'], answer: 0),
    MillionQuestion(category: 'C++', difficulty: 'صعب', text: 'أي مفهوم يسمح للصنف المشتق باستخدام خصائص الصنف الأساسي؟', options: ['التغليف', 'الوراثة', 'التجريد', 'التحويل'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'صعب', text: 'ما الهدف الأساسي من الدالة الافتراضية virtual؟', options: ['منع الإنشاء', 'دعم تعدد الأشكال وقت التشغيل', 'تسريع الحلقة', 'حذف المؤشر'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'صعب', text: 'أي كلمة تمنع توريث الصنف أو إعادة تعريف الدالة؟', options: ['sealed', 'stop', 'final', 'closed'], answer: 2),
    MillionQuestion(category: 'C++', difficulty: 'صعب', text: 'ما الذي تمثله RAII في C++؟', options: ['إدارة الموارد بعمر الكائن', 'نوع حلقة', 'خوارزمية بحث', 'تنسيق نص'], answer: 0),
    MillionQuestion(category: 'C++', difficulty: 'صعب', text: 'أي قالب STL يربط مفتاحاً بقيمة مرتبة؟', options: ['vector', 'set', 'map', 'stack'], answer: 2),
    MillionQuestion(category: 'C++', difficulty: 'صعب', text: 'أي حاوية تخزن عناصر فريدة مرتبة؟', options: ['set', 'vector', 'queue', 'list'], answer: 0),
    MillionQuestion(category: 'C++', difficulty: 'صعب', text: 'ما تعقيد البحث المعتاد في std::map؟', options: ['O(1)', 'O(log n)', 'O(n²)', 'O(2ⁿ)'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'صعب', text: 'ما فائدة template في C++؟', options: ['كتابة كود عام لأنواع متعددة', 'تشغيل الخيوط', 'ضغط الملفات', 'إنشاء تعليق'], answer: 0),
    MillionQuestion(category: 'C++', difficulty: 'صعب', text: 'أي استثناء قياسي يدل غالباً على فهرس خارج النطاق؟', options: ['std::out_of_range', 'std::bad_index', 'std::outside', 'std::range_error_only'], answer: 0),
    MillionQuestion(category: 'C++', difficulty: 'صعب', text: 'ما الفرق الأساسي بين reference وpointer؟', options: ['لا فرق إطلاقاً', 'المرجع لا يكون فارغاً عادةً ولا يعاد ربطه', 'المؤشر لا يخزن عنواناً', 'المرجع يستخدم للأعداد فقط'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'صعب', text: 'أي كلمة تستخدم لمعالجة الاستثناءات؟', options: ['try/catch', 'check/handle', 'error/solve', 'test/fix'], answer: 0),
    MillionQuestion(category: 'C++', difficulty: 'صعب', text: 'أي خوارزمية STL ترتب نطاقاً من العناصر؟', options: ['std::order', 'std::sort', 'std::arrange', 'std::organize'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'صعب', text: 'ما معنى const correctness؟', options: ['استخدام const لحماية القيم التي لا يجب تعديلها', 'منع كل الدوال', 'استخدام الثوابت فقط', 'حذف المؤشرات'], answer: 0),
    MillionQuestion(category: 'C++', difficulty: 'متوسط', text: 'أي مكتبة تحتوي عادةً على std::vector؟', options: ['<vector>', '<arraylist>', '<collection>', '<dynamic>'], answer: 0),
    MillionQuestion(category: 'C++', difficulty: 'متوسط', text: 'ما وظيفة std::cin؟', options: ['الإخراج', 'الإدخال', 'الترتيب', 'إنشاء ملف'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'متوسط', text: 'أي نوع يخزن عدداً عشرياً بدقة أعلى من float غالباً؟', options: ['char', 'bool', 'double', 'short'], answer: 2),
    MillionQuestion(category: 'C++', difficulty: 'متوسط', text: 'أي كلمة تعرّف متغيراً محلياً لا يتغير بعد تهيئته؟', options: ['const', 'fixed', 'unchange', 'readonly'], answer: 0),
    MillionQuestion(category: 'C++', difficulty: 'صعب', text: 'ما النتيجة المعتادة لمحاولة الوصول إلى مؤشر null؟', options: ['قراءة صفر', 'سلوك غير صالح أو عطل', 'تحويله إلى نص', 'زيادة المؤشر'], answer: 1),
    MillionQuestion(category: 'C++', difficulty: 'صعب', text: 'ما المقصود بـ lvalue؟', options: ['تعبير له موقع يمكن الإسناد إليه غالباً', 'قيمة عشرية فقط', 'دالة لا تعيد قيمة', 'نوع من الحلقات'], answer: 0),
    MillionQuestion(category: 'C++', difficulty: 'صعب', text: 'أي أداة تستخدم لبناء مشروع C++ وإدارة ملفاته؟', options: ['CMake', 'CImage', 'CMarkup', 'CBuildOnly'], answer: 0),
    MillionQuestion(category: 'C++', difficulty: 'صعب', text: 'ما فائدة std::unique_ptr؟', options: ['ملكية حصرية لمورد ديناميكي', 'تخزين عدة مفاتيح', 'ترتيب النصوص', 'تشغيل حلقة'], answer: 0),
    MillionQuestion(category: 'Python', difficulty: 'سهل', text: 'أي دالة تُستخدم لطباعة النص على الشاشة في Python؟', options: ['echo()', 'print()', 'cout()', 'show()'], answer: 1),
    MillionQuestion(category: 'Python', difficulty: 'سهل', text: 'أي دالة تُستخدم لاستقبال إدخال من المستخدم؟', options: ['input()', 'scan()', 'cin()', 'read()'], answer: 0),
    MillionQuestion(category: 'Python', difficulty: 'سهل', text: 'أي نوع بيانات يُستخدم لتخزين نص؟', options: ['int', 'bool', 'str', 'float'], answer: 2),
    MillionQuestion(category: 'Python', difficulty: 'سهل', text: 'أي نوع بيانات يمثل عدداً صحيحاً؟', options: ['int', 'str', 'float', 'list'], answer: 0),
    MillionQuestion(category: 'Python', difficulty: 'سهل', text: 'أي نوع بيانات يمثل عدداً عشرياً؟', options: ['bool', 'float', 'str', 'tuple'], answer: 1),
    MillionQuestion(category: 'Python', difficulty: 'سهل', text: 'ما الرمز المستخدم لكتابة تعليق من سطر واحد؟', options: ['//', '#', '/*', '--'], answer: 1),
    MillionQuestion(category: 'Python', difficulty: 'سهل', text: 'أي كلمة تُستخدم لإنشاء شرط؟', options: ['if', 'for', 'def', 'print'], answer: 0),
    MillionQuestion(category: 'Python', difficulty: 'سهل', text: 'ما الكلمة المستخدمة إذا لم يتحقق شرط if؟', options: ['then', 'otherwise', 'else', 'case'], answer: 2),
    MillionQuestion(category: 'Python', difficulty: 'سهل', text: 'أي حلقة تُستخدم عادةً للتكرار على مجموعة من العناصر؟', options: ['if', 'for', 'def', 'try'], answer: 1),
    MillionQuestion(category: 'Python', difficulty: 'سهل', text: 'أي حلقة تستمر ما دام الشرط صحيحاً؟', options: ['while', 'switch', 'if', 'case'], answer: 0),
    MillionQuestion(category: 'Python', difficulty: 'سهل', text: 'أي كلمة تُستخدم لتعريف دالة في Python؟', options: ['function', 'fun', 'define', 'def'], answer: 3),
    MillionQuestion(category: 'Python', difficulty: 'سهل', text: 'أي عامل يُستخدم للجمع؟', options: ['*', '/', '+', '%'], answer: 2),
    MillionQuestion(category: 'Python', difficulty: 'سهل', text: 'أي عامل يُستخدم للتحقق من تساوي قيمتين؟', options: ['=', '==', '!=', '+='], answer: 1),
    MillionQuestion(category: 'Python', difficulty: 'سهل', text: 'أي رمز يُستخدم للحصول على باقي القسمة؟', options: ['%', '/', '//', '*'], answer: 0),
    MillionQuestion(category: 'Python', difficulty: 'سهل', text: 'أي نوع بيانات يخزن القيم True أو False؟', options: ['int', 'str', 'bool', 'float'], answer: 2),
    MillionQuestion(category: 'Python', difficulty: 'سهل', text: 'أي كلمة تُستخدم لإيقاف الحلقة؟', options: ['stop', 'exit', 'end', 'break'], answer: 3),
    MillionQuestion(category: 'Python', difficulty: 'سهل', text: 'أي كلمة تُستخدم لتجاوز الدورة الحالية والانتقال للدورة التالية؟', options: ['continue', 'break', 'return', 'next'], answer: 0),
    MillionQuestion(category: 'Python', difficulty: 'سهل', text: 'أي من التالي يمثل قائمة List صحيحة في Python؟', options: ['(1, 2, 3)', '[1, 2, 3]', '{1:2:3}', '<1, 2, 3>'], answer: 1),
    MillionQuestion(category: 'Python', difficulty: 'سهل', text: 'أي دالة تعطي عدد العناصر الموجودة في قائمة؟', options: ['size()', 'countall()', 'len()', 'length()'], answer: 2),
    MillionQuestion(category: 'Python', difficulty: 'سهل', text: 'ما امتداد ملفات Python المعتاد؟', options: ['.cpp', '.java', '.html', '.py'], answer: 3),
    MillionQuestion(category: 'Java', difficulty: 'متوسط', text: 'أي دالة يبدأ منها تنفيذ برنامج Java؟', options: ['start()', 'main()', 'run()', 'begin()'], answer: 1),
    MillionQuestion(category: 'Java', difficulty: 'متوسط', text: 'أي نوع بيانات يُستخدم لتخزين عدد صحيح؟', options: ['String', 'boolean', 'int', 'double'], answer: 2),
    MillionQuestion(category: 'Java', difficulty: 'متوسط', text: 'أي نوع بيانات يُستخدم لتخزين نص في Java؟', options: ['String', 'char', 'int', 'boolean'], answer: 0),
    MillionQuestion(category: 'Java', difficulty: 'متوسط', text: 'أي نوع بيانات يُستخدم لتخزين حرف واحد؟', options: ['String', 'char', 'float', 'int'], answer: 1),
    MillionQuestion(category: 'Java', difficulty: 'متوسط', text: 'أي نوع بيانات يخزن true أو false؟', options: ['int', 'String', 'boolean', 'char'], answer: 2),
    MillionQuestion(category: 'Java', difficulty: 'متوسط', text: 'أي أمر يُستخدم لطباعة سطر على الشاشة؟', options: ['print()', 'cout', 'System.out.println()', 'echo()'], answer: 2),
    MillionQuestion(category: 'Java', difficulty: 'متوسط', text: 'ما الرمز المستخدم لإنهاء التعليمة في Java؟', options: [':', ';', ',', '#'], answer: 1),
    MillionQuestion(category: 'Java', difficulty: 'متوسط', text: 'ما الرمز المستخدم لكتابة تعليق من سطر واحد؟', options: ['#', '--', '//', '**'], answer: 2),
    MillionQuestion(category: 'Java', difficulty: 'متوسط', text: 'أي كلمة تُستخدم لإنشاء شرط؟', options: ['if', 'loop', 'class', 'import'], answer: 0),
    MillionQuestion(category: 'Java', difficulty: 'متوسط', text: 'أي كلمة تُستخدم عندما لا يتحقق شرط if؟', options: ['other', 'else', 'case', 'default'], answer: 1),
    MillionQuestion(category: 'Java', difficulty: 'متوسط', text: 'أي حلقة مناسبة عندما يكون عدد مرات التكرار معروفاً؟', options: ['if', 'for', 'switch', 'try'], answer: 1),
    MillionQuestion(category: 'Java', difficulty: 'متوسط', text: 'أي حلقة تستمر طالما الشرط صحيح؟', options: ['while', 'if', 'class', 'import'], answer: 0),
    MillionQuestion(category: 'Java', difficulty: 'متوسط', text: 'ما العامل المستخدم للتحقق من تساوي قيمتين؟', options: ['=', '==', '+=', '!='], answer: 1),
    MillionQuestion(category: 'Java', difficulty: 'متوسط', text: 'ما العامل المستخدم للحصول على باقي القسمة؟', options: ['/', '*', '%', '+'], answer: 2),
    MillionQuestion(category: 'Java', difficulty: 'متوسط', text: 'أي كلمة تُستخدم لإنشاء Class؟', options: ['object', 'new', 'class', 'create'], answer: 2),
    MillionQuestion(category: 'Java', difficulty: 'متوسط', text: 'أي كلمة تُستخدم لإنشاء كائن جديد؟', options: ['make', 'new', 'create', 'object'], answer: 1),
    MillionQuestion(category: 'Java', difficulty: 'متوسط', text: 'أي كلمة تُستخدم للخروج من الحلقة؟', options: ['break', 'stop', 'close', 'end'], answer: 0),
    MillionQuestion(category: 'Java', difficulty: 'متوسط', text: 'أي كلمة تُستخدم لإرجاع قيمة من Method؟', options: ['print', 'break', 'return', 'output'], answer: 2),
    MillionQuestion(category: 'Java', difficulty: 'متوسط', text: 'ما امتداد ملف Java المصدري؟', options: ['.py', '.cpp', '.java', '.js'], answer: 2),
    MillionQuestion(category: 'Java', difficulty: 'متوسط', text: 'أي كلمة تُستخدم لاستيراد مكتبة أو Class في Java؟', options: ['include', 'using', 'require', 'import'], answer: 3),
    MillionQuestion(category: 'Java', difficulty: 'صعب', text: 'ما الفرق الأساسي بين interface وabstract class في Java؟', options: ['لا يوجد فرق', 'الواجهة تحدد عقداً ويمكن للصنف تطبيق أكثر من واجهة', 'الواجهة لا تحتوي أي دوال', 'الصنف المجرد لا يمكن توريثه'], answer: 1),
    MillionQuestion(category: 'Java', difficulty: 'صعب', text: 'أي كلمة تمنع توريث الصنف أو إعادة تعريف الدالة؟', options: ['sealed', 'final', 'static', 'private'], answer: 1),
    MillionQuestion(category: 'Java', difficulty: 'صعب', text: 'أي مجموعة تحفظ ترتيب الإدخال وتسمح بالتكرار؟', options: ['HashSet', 'TreeSet', 'ArrayList', 'HashMap'], answer: 2),
    MillionQuestion(category: 'Java', difficulty: 'صعب', text: 'ما تعقيد الوصول إلى عنصر في ArrayList باستخدام الفهرس؟', options: ['O(1)', 'O(log n)', 'O(n)', 'O(n²)'], answer: 0),
    MillionQuestion(category: 'Java', difficulty: 'صعب', text: 'أي استثناء يحدث غالباً عند القسمة الصحيحة على صفر؟', options: ['IOException', 'NullPointerException', 'ArithmeticException', 'IndexOutOfBoundsException'], answer: 2),
    MillionQuestion(category: 'Java', difficulty: 'صعب', text: 'ماذا تعني كلمة synchronized غالباً؟', options: ['منع إنشاء الكائن', 'تنظيم الوصول المتزامن إلى مورد مشترك', 'تسريع البرنامج', 'تحويل النص'], answer: 1),
    MillionQuestion(category: 'Java', difficulty: 'صعب', text: 'ما وظيفة Garbage Collector؟', options: ['ترجمة الكود', 'تحرير الذاكرة للكائنات غير المستخدمة', 'إدارة قواعد البيانات', 'تشفير النصوص'], answer: 1),
    MillionQuestion(category: 'Java', difficulty: 'صعب', text: 'أي مفهوم يسمح للدالة نفسها بسلوك مختلف حسب الكائن؟', options: ['التغليف', 'تعدد الأشكال', 'التحويل', 'التجميع'], answer: 1),
    MillionQuestion(category: 'Java', difficulty: 'صعب', text: 'ما فائدة Optional في Java الحديثة؟', options: ['تمثيل قيمة قد تكون موجودة أو غائبة', 'إنشاء خيط جديد', 'ترتيب مصفوفة', 'حذف الاستثناءات'], answer: 0),
    MillionQuestion(category: 'Java', difficulty: 'صعب', text: 'أي بنية تربط مفتاحاً بقيمة في Java؟', options: ['List', 'Set', 'Map', 'QueueOnly'], answer: 2),
    MillionQuestion(
      category: 'ثقافة عامة',
      text: 'أي من الآتي يُعد من الكواكب الداخلية في المجموعة الشمسية؟',
      options: ['المريخ', 'المشتري', 'زحل', 'نبتون'],
      answer: 1,
      difficulty: 'سهل',
    ),
    MillionQuestion(
      category: 'رياضيات',
      text: 'إذا كان محيط مربع 24 سم، فما طول ضلعه؟',
      options: ['4 سم', '6 سم', '8 سم', '12 سم'],
      answer: 1,
      difficulty: 'متوسط',
    ),
    MillionQuestion(
      category: 'برمجة',
      text: 'أي وسم HTML يستخدم لإنشاء رابط؟',
      options: ['<p>', '<img>', '<a>', '<link>'],
      answer: 2,
      difficulty: 'سهل',
    ),
    MillionQuestion(
      category: 'علوم',
      text: 'ما الغاز الذي تحتاجه النباتات في عملية البناء الضوئي؟',
      options: ['الأكسجين', 'الهيدروجين', 'النيتروجين', 'ثاني أكسيد الكربون'],
      answer: 3,
      difficulty: 'متوسط',
    ),
    MillionQuestion(
      category: 'منطق',
      text: 'إذا كان كل مربع مستطيلاً، فما العبارة الصحيحة؟',
      options: ['كل مستطيل مربع', 'بعض المربعات ليست مستطيلات', 'كل مربع مستطيل', 'لا علاقة بينهما'],
      answer: 2,
      difficulty: 'صعب',
    ),
    MillionQuestion(
      category: 'تقنية',
      text: 'ما الوحدة التي تقيس سرعة المعالج غالبًا؟',
      options: ['جيجابايت', 'جيجاهرتز', 'بكسل', 'لتر'],
      answer: 1,
      difficulty: 'متوسط',
    ),
    MillionQuestion(
      category: 'ثقافة عامة',
      text: 'ما عاصمة العراق؟',
      options: ['البصرة', 'الموصل', 'بغداد', 'أربيل'],
      answer: 2,
    ),
    MillionQuestion(
      category: 'رياضيات',
      text: 'ما العدد الأولي من الخيارات التالية؟',
      options: ['21', '27', '29', '33'],
      answer: 2,
    ),
    MillionQuestion(
      category: 'علوم',
      text: 'أي عضو يضخ الدم إلى أنحاء الجسم؟',
      options: ['الرئة', 'القلب', 'الكبد', 'الكلية'],
      answer: 1,
    ),
    MillionQuestion(
      category: 'برمجة',
      text: 'ما نوع البيانات الذي يمثل true أو false؟',
      options: ['String', 'Integer', 'Boolean', 'Double'],
      answer: 2,
    ),
    MillionQuestion(
      category: 'منطق',
      text: 'ما العدد التالي في النمط: 2، 4، 8، 16، ؟',
      options: ['18', '24', '30', '32'],
      answer: 3,
    ),
    MillionQuestion(
      category: 'تقنية',
      text: 'ما الجهاز المستخدم لإدخال النص إلى الحاسوب؟',
      options: ['الشاشة', 'لوحة المفاتيح', 'السماعة', 'الطابعة'],
      answer: 1,
    ),
    MillionQuestion(
      category: 'علوم',
      text: 'ما اسم القوة التي تجذب الأجسام نحو سطح الأرض؟',
      options: ['الاحتكاك', 'الجاذبية', 'الطفو', 'المغناطيسية'],
      answer: 1,
      difficulty: 'متوسط',
    ),
    MillionQuestion(
      category: 'رياضيات',
      text: 'إذا كان مجموع عددين 18 والفرق بينهما 4، فما العدد الأكبر؟',
      options: ['7', '9', '11', '14'],
      answer: 2,
      difficulty: 'صعب',
    ),
    MillionQuestion(
      category: 'منطق وتقنية',
      text: 'أي بنية بيانات تعمل وفق مبدأ آخر داخل أول خارج؟',
      options: ['Queue', 'Stack', 'Tree', 'Graph'],
      answer: 1,
      difficulty: 'صعب',
    ),
  ];

  late List<MillionQuestion> gameQuestions;
  final answerPlayer = AudioPlayer(playerId: 'million-answer');
  final questionPlayer = AudioPlayer(playerId: 'million-question');
  final optionSequencePlayer = AudioPlayer(playerId: 'million-option-sequence');
  final countdownPlayer = AudioPlayer(playerId: 'million-countdown');
  Future<void> countdownStopQueue = Future<void>.value();
  Timer? countdownTickTimer;
  Timer? questionTimer;
  final List<Timer> optionRevealTimers = [];
  DateTime? questionDeadline;
  int questionCycle = 0;

  static const questionDuration = Duration(seconds: 34);
  static const optionRevealDelays = [
    Duration(milliseconds: 500),
    Duration(milliseconds: 1150),
    Duration(milliseconds: 1800),
    Duration(milliseconds: 2450),
  ];

  int current = 0;
  int secondsRemaining = 35;
  bool timerStarted = false;
  int revealedOptionCount = 4;
  int score = 0;
  int diamondBalance = 0;
  int bestScore = 0;
  int? selected;
  bool answered = false;
  bool finished = false;
  bool attemptLost = false;
  int wrongAnswers = 0;
  bool fiftyUsed = false;
  bool friendUsed = false;
  bool pollUsed = false;
  Set<int> hiddenOptions = {};
  List<int> history = [];
  Set<String> shownQuestionKeys = {};
  String currentUser = 'guest';

  MillionQuestion get question => gameQuestions[current % gameQuestions.length];

  int prizeForQuestion(int index) {
    return prizeLadder[prizeIndexForQuestion(index)];
  }

  int prizeIndexForQuestion(int index) {
    return index.clamp(0, prizeLadder.length - 1);
  }

  @override
  void initState() {
    super.initState();
    final remainingQuestions = [...questions.skip(2)]..shuffle(math.Random());
    gameQuestions = [...questions.take(2), ...remainingQuestions];
    _startQuestionCycle();
    _loadProgress();
  }

  String _questionKey(MillionQuestion value) => '${value.category}|${value.text}';

  void _startQuestionCycle() {
    _cancelQuestionCycle();
    unawaited(answerPlayer.stop());
    final cycle = ++questionCycle;
    final startedAt = DateTime.now();
    questionDeadline = startedAt.add(questionDuration);
    setState(() {
      secondsRemaining = questionDuration.inSeconds;
      timerStarted = false;
      revealedOptionCount = 0;
    });
    _startQuestionPresentation(cycle);
  }

  void _startQuestionPresentation(int cycle) {
    for (var index = 0; index < optionRevealDelays.length; index++) {
      final revealIndex = index + 1;
      optionRevealTimers.add(Timer(optionRevealDelays[index], () {
        if (!_isQuestionCycleActive(cycle)) return;
        setState(() => revealedOptionCount = revealIndex);
        unawaited(_playOptionSequence(cycle));
        if (revealIndex == optionRevealDelays.length) _startQuestionTimer(cycle);
      }));
    }
  }

  bool _isQuestionCycleActive(int cycle) => mounted && cycle == questionCycle && !answered && !finished && !attemptLost;

  Future<void> _playQuestionSound(int cycle) async {
    try {
      await questionPlayer.stop();
      await questionPlayer.setReleaseMode(ReleaseMode.loop);
      if (!_isQuestionCycleActive(cycle)) return;
      await questionPlayer.play(AssetSource('audio/question.mp3'));
    } catch (_) {}
  }

  Future<void> _playOptionSequence(int cycle) async {
    try {
      await optionSequencePlayer.stop();
      if (!_isQuestionCycleActive(cycle)) return;
      await optionSequencePlayer.play(AssetSource('audio/option_tap.mp3'));
    } catch (_) {}
  }

  void _startQuestionTimer(int cycle) {
    if (!_isQuestionCycleActive(cycle)) return;
    questionTimer?.cancel();
    questionDeadline = DateTime.now().add(questionDuration);
    setState(() => timerStarted = true);
    unawaited(_startCountdownSound(cycle));
    questionTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_isQuestionCycleActive(cycle)) return;
      final deadline = questionDeadline;
      if (deadline == null) return;
      final millisecondsLeft = deadline.difference(DateTime.now()).inMilliseconds;
      if (millisecondsLeft <= 0) {
        _timeExpired();
      } else {
        final nextSeconds = (millisecondsLeft / 1000).ceil();
        if (nextSeconds != secondsRemaining) {
          setState(() => secondsRemaining = nextSeconds);
          if (nextSeconds <= 1) unawaited(questionPlayer.stop());
        }
      }
    });
  }

  void _cancelQuestionCycle() {
    questionCycle++;
    questionTimer?.cancel();
    questionTimer = null;
    for (final timer in optionRevealTimers) {
      timer.cancel();
    }
    optionRevealTimers.clear();
    questionDeadline = null;
    unawaited(_stopQuestionAudio());
  }

  Future<void> _stopQuestionAudio() async {
    countdownTickTimer?.cancel();
    countdownTickTimer = null;
    _queueCountdownStop();
    try {
      await Future.wait([
        questionPlayer.stop(),
        optionSequencePlayer.stop(),
      ]);
    } catch (_) {}
  }

  void _queueCountdownStop() {
    countdownStopQueue = countdownStopQueue.then<void>((_) async {
      try {
        await countdownPlayer.stop();
      } catch (_) {}
    });
  }

  Future<void> _startCountdownSound(int cycle) async {
    try {
      await countdownStopQueue;
      await countdownPlayer.setReleaseMode(ReleaseMode.release);
      if (!_isQuestionCycleActive(cycle) || !timerStarted) return;
      unawaited(_playCountdownTick(cycle));
      countdownTickTimer?.cancel();
      countdownTickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_isQuestionCycleActive(cycle) || !timerStarted || secondsRemaining <= 0) {
          countdownTickTimer?.cancel();
          countdownTickTimer = null;
          return;
        }
        unawaited(_playCountdownTick(cycle));
      });
    } catch (_) {}
  }

  Future<void> _playCountdownTick(int cycle) async {
    try {
      await countdownPlayer.stop();
      if (!_isQuestionCycleActive(cycle) || !timerStarted || secondsRemaining <= 0) return;
      await countdownPlayer.play(AssetSource('audio/34.mp3'));
    } catch (_) {}
  }

  void _timeExpired() {
    if (answered || finished || attemptLost) return;
    _cancelQuestionCycle();
    unawaited(_playAnswerSound(false));
    setState(() {
      answered = true;
      wrongAnswers++;
    });
    _saveProgress();
    Future.delayed(const Duration(milliseconds: 1300), () {
      if (!mounted || !answered || selected != null) return;
      setState(() => attemptLost = true);
      _saveProgress();
    });
  }

  Future<void> _loadProgress() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        bestScore = preferences.getInt('million_best') ?? 0;
        currentUser = preferences.getString('million_current_user') ?? 'guest';
        final seenKey = 'million_seen_questions_$currentUser';
        shownQuestionKeys = preferences.getStringList(seenKey)?.toSet() ?? {};
        _prepareQuestionOrder();
        current = (preferences.getInt('million_current') ?? 0).clamp(0, gameQuestions.length - 1);
        score = preferences.getInt('million_score') ?? 0;
        diamondBalance = preferences.getInt('million_diamonds') ?? 0;
        wrongAnswers = preferences.getInt('million_wrong_answers') ?? 0;
        attemptLost = wrongAnswers >= 2;
        history = preferences.getStringList('million_history')
                ?.map(int.parse)
                .toList() ??
            [];
        _markCurrentQuestionShown();
      });
      if (mounted) {
        if (attemptLost) {
          _cancelQuestionCycle();
        } else {
          _startQuestionCycle();
        }
      }
    } catch (_) {}
  }

  Future<void> _saveProgress() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setInt('million_best', bestScore);
      await preferences.setInt('million_current', current);
      await preferences.setInt('million_score', score);
      await preferences.setInt('million_diamonds', diamondBalance);
      await preferences.setInt('million_wrong_answers', wrongAnswers);
      await preferences.setStringList(
        'million_history',
        history.take(10).map((value) => value.toString()).toList(),
      );
      await preferences.setStringList(
        'million_seen_questions_$currentUser',
        shownQuestionKeys.toList(),
      );
    } catch (_) {}
  }

  void _prepareQuestionOrder() {
    final unseen = questions.where((item) => !shownQuestionKeys.contains(_questionKey(item))).toList();
    if (unseen.isEmpty) {
      shownQuestionKeys.clear();
      unseen.addAll(questions);
    }
    unseen.shuffle(math.Random());
    final easy = unseen.where((item) => item.difficulty == 'سهل').toList();
    final firstQuestions = <MillionQuestion>[];
    for (final item in easy) {
      if (firstQuestions.length == 2) break;
      firstQuestions.add(item);
    }
    final remaining = [...unseen]..removeWhere(firstQuestions.contains);
    gameQuestions = [...firstQuestions, ...remaining];
    if (gameQuestions.length < 2) {
      final fallback = [...questions]..shuffle(math.Random());
      gameQuestions = [...fallback.take(2), ...gameQuestions];
    }
  }

  void _markCurrentQuestionShown() {
    if (gameQuestions.isNotEmpty && current < gameQuestions.length) {
      shownQuestionKeys.add(_questionKey(gameQuestions[current]));
    }
  }

  void choose(int index) {
    if (answered || hiddenOptions.contains(index) || revealedOptionCount < 4) return;
    _cancelQuestionCycle();
    final correct = index == question.answer;
    unawaited(_playAnswerSound(correct));
    setState(() {
      selected = index;
      answered = true;
      if (!correct) wrongAnswers++;
      if (correct) {
        score = prizeForQuestion(current);
        diamondBalance += prizeForQuestion(current);
      }
    });
    _saveProgress();
    Future.delayed(const Duration(milliseconds: 1300), () {
      if (!mounted || !answered || selected != index) return;
      if (wrongAnswers >= 2) {
        setState(() => attemptLost = true);
        _saveProgress();
      } else if (current == gameQuestions.length - 1) {
        _finishRound();
      } else {
        nextQuestion();
      }
    });
  }

  Future<void> _playAnswerSound(bool correct) async {
    try {
      await answerPlayer.stop();
      await answerPlayer.setVolume(.45);
      await answerPlayer.play(
        BytesSource(
          correct ? MillionSoundEffects.correct : MillionSoundEffects.wrong,
          mimeType: 'audio/wav',
        ),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _cancelQuestionCycle();
    answerPlayer.dispose();
    questionPlayer.dispose();
    optionSequencePlayer.dispose();
    countdownPlayer.dispose();
    super.dispose();
  }

  void nextQuestion() {
    if (!answered) return;
    setState(() {
      current++;
      selected = null;
      answered = false;
      hiddenOptions = {};
      _markCurrentQuestionShown();
    });
    _startQuestionCycle();
    _saveProgress();
  }

  void _finishRound() {
    final finalScore = score;
    setState(() {
      finished = true;
      bestScore = finalScore > bestScore ? finalScore : bestScore;
      history = [finalScore, ...history].take(10).toList();
    });
    _saveProgress();
  }

  void restart() {
    setState(() {
      current = 0;
      score = 0;
      selected = null;
      answered = false;
      finished = false;
      fiftyUsed = false;
      friendUsed = false;
      pollUsed = false;
      hiddenOptions = {};
      wrongAnswers = 0;
    });
    _startQuestionCycle();
    _saveProgress();
  }

  void returnToHomeAfterLoss() {
    setState(() {
      current = 0;
      score = 0;
      selected = null;
      answered = false;
      attemptLost = false;
      finished = false;
      wrongAnswers = 0;
      fiftyUsed = false;
      friendUsed = false;
      pollUsed = false;
      hiddenOptions = {};
    });
    _cancelQuestionCycle();
    _saveProgress();
    Navigator.pop(context);
  }

  void exitGame() {
    setState(() {
      current = 0;
      score = 0;
      selected = null;
      answered = false;
      attemptLost = false;
      finished = false;
      wrongAnswers = 0;
      fiftyUsed = false;
      friendUsed = false;
      pollUsed = false;
      hiddenOptions = {};
    });
    _saveProgress();
    Navigator.pop(context);
  }

  Future<void> showDiamondShop() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.diamond_outlined, color: loginTeal),
            SizedBox(width: 8),
            Text('متجر الماسات'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('رصيدك الحالي: $diamondBalance ماسة'),
            const SizedBox(height: 12),
            for (final package in const [
              ('حزمة البداية', '500 ماسة', Icons.inventory_2_outlined),
              ('حزمة التقدم', '2500 ماسة', Icons.auto_awesome_outlined),
              ('حزمة القمة', '10000 ماسة', Icons.workspace_premium_outlined),
            ])
              ListTile(
                dense: true,
                leading: Icon(package.$3, color: loginTeal),
                title: Text(package.$1),
                subtitle: Text(package.$2),
                trailing: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('سيتم تفعيل الدفع الآمن عند ربط المتجر بالحساب')),
                    );
                  },
                  child: const Text('شراء'),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  void useFifty() {
    if (fiftyUsed || answered) return;
    final wrong = <int>[];
    for (var i = 0; i < question.options.length; i++) {
      if (i != question.answer) wrong.add(i);
    }
    setState(() {
      fiftyUsed = true;
      hiddenOptions = {wrong[0], wrong[1]};
    });
  }

  Future<void> useFriend() async {
    if (friendUsed || answered) return;
    setState(() => friendUsed = true);
    final confidence = 54 + (current % 4) * 5;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('رأي الصديق'),
        content: Text(
          'أظن أن الإجابة الأقرب هي الخيار ${String.fromCharCode(65 + question.answer)} باحتمال $confidence٪، لكنني غير متأكد تمامًا.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('فهمت')),
        ],
      ),
    );
  }

  Future<void> usePoll() async {
    if (pollUsed || answered) return;
    setState(() => pollUsed = true);
    final percentages = List<int>.filled(4, 0);
    percentages[question.answer] = 62;
    var remaining = 38;
    for (var i = 0; i < percentages.length; i++) {
      if (i == question.answer) continue;
      final value = i == 3 ? remaining : (remaining / 2).round();
      percentages[i] = value;
      remaining -= value;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تصويت الجمهور'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            4,
            (index) => ListTile(
              dense: true,
              title: Text('${String.fromCharCode(65 + index)}: ${question.options[index]}'),
              trailing: Text('${percentages[index]}%'),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Shell(
    showBack: false,
    child: SafeArea(
      child: attemptLost
          ? _buildAttemptLost()
          : finished
          ? _buildResult()
          : _buildGame(),
    ),
  );

  Widget _buildGame() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
    child: SingleChildScrollView(
      child: Column(
        children: [
      Row(
        children: [
          IconButton.filled(
            tooltip: 'خروج',
            onPressed: exitGame,
            style: IconButton.styleFrom(
              backgroundColor: emerald,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.emoji_events_rounded, color: Color(0xffd4a72c), size: 30),
          const SizedBox(width: 8),
          const Text('طريق المليون', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text('أفضل: $bestScore', style: const TextStyle(color: mutedInk, fontSize: 12)),
        ],
      ),
      const SizedBox(height: 8),
      Panel(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                Text('السؤال ${current + 1} من ${gameQuestions.length}', style: const TextStyle(color: mutedInk)),
                const Spacer(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.diamond_outlined, color: loginTeal, size: 18),
                    const SizedBox(width: 4),
                    Text('الجولة: $score', style: const TextStyle(color: loginTeal, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 12),
                              IconButton.filledTonal(
                                tooltip: 'متجر الماسات',
                                onPressed: showDiamondShop,
                                icon: const Icon(Icons.storefront_outlined, size: 19),
                              ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.diamond_outlined, color: Color(0xffb48616), size: 18),
                  const SizedBox(width: 4),
                  Text(
                    'الهدف التالي: ${prizeForQuestion(current)} ماسة',
                    style: const TextStyle(color: Color(0xffb48616), fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (current + 1) / gameQuestions.length,
                minHeight: 8,
                color: loginTeal,
                backgroundColor: const Color(0xffe2e8f0),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      _buildLadder(),
      const SizedBox(height: 8),
      Panel(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(question.category, style: const TextStyle(color: loginTeal, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xffecfeff), borderRadius: BorderRadius.circular(20)),
                  child: Text('المستوى: ${question.difficulty}', style: const TextStyle(color: loginTeal, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(question.text, key: ValueKey(current), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.4)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Stack(
        alignment: Alignment.center,
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 6,
            childAspectRatio: 5.6,
            children: List.generate(4, _buildOption),
          ),
          IgnorePointer(
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: !timerStarted || secondsRemaining <= 10 ? const Color(0xfffef2f2) : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: !timerStarted || secondsRemaining <= 10 ? const Color(0xffdc2626) : loginTeal,
                  width: 3,
                ),
                boxShadow: const [
                  BoxShadow(color: Color(0x220f172a), blurRadius: 8, offset: Offset(0, 3)),
                ],
              ),
              child: Center(
                child: Text(
                  timerStarted ? '$secondsRemaining' : '…',
                  style: TextStyle(
                    color: !timerStarted || secondsRemaining <= 10 ? const Color(0xffdc2626) : loginTeal,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      if (answered) ...[
        const SizedBox(height: 3),
        Text(
          selected == question.answer ? 'إجابة صحيحة' : 'إجابة خاطئة، الإجابة الصحيحة: ${String.fromCharCode(65 + question.answer)}',
          style: TextStyle(color: selected == question.answer ? const Color(0xff059669) : const Color(0xffdc2626), fontWeight: FontWeight.bold, fontSize: 16),
        ),
        if (selected == question.answer && current < gameQuestions.length - 1)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SizedBox(width: double.infinity, height: 50, child: FilledButton.icon(onPressed: nextQuestion, icon: const Icon(Icons.arrow_forward), label: const Text('السؤال التالي'))),
          ),
      ],
      const SizedBox(height: 4),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _helpButton(Icons.content_cut, 'حذف إجابتين', fiftyUsed, useFifty),
          _helpButton(Icons.phone_in_talk_outlined, 'صديق', friendUsed, useFriend),
          _helpButton(Icons.bar_chart_rounded, 'تصويت', pollUsed, usePoll),
        ],
      ),
        ],
      ),
    ),
  );

  Widget _buildOption(int index) {
    if (hiddenOptions.contains(index) || index >= revealedOptionCount) return const SizedBox.shrink();
    final isCorrect = answered && index == question.answer;
    final isWrong = answered && index == selected && index != question.answer;
    final color = isCorrect
        ? const Color(0xff059669)
        : isWrong
        ? const Color(0xffdc2626)
        : const Color(0xffe2e8f0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(color: color.withValues(alpha: isCorrect || isWrong ? .12 : 1), borderRadius: BorderRadius.circular(14), border: Border.all(color: color, width: isCorrect || isWrong ? 2 : 1)),
        child: Material(color: Colors.transparent, child: InkWell(onTap: answered ? null : () => choose(index), borderRadius: BorderRadius.circular(14), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), child: Row(children: [CircleAvatar(radius: 10, backgroundColor: color, child: Text(String.fromCharCode(65 + index), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))), const SizedBox(width: 7), Expanded(child: Text(question.options[index], maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: ink))), if (isCorrect) const Icon(Icons.check_circle, size: 16, color: Color(0xff059669)), if (isWrong) const Icon(Icons.cancel, size: 16, color: Color(0xffdc2626))])))),
      ),
    );
  }

  Widget _helpButton(IconData icon, String label, bool used, VoidCallback action) => Column(
    children: [
      IconButton.filledTonal(onPressed: used || answered ? null : action, icon: Icon(icon)),
      Text(label, style: TextStyle(color: used ? mutedInk : ink, fontSize: 11)),
    ],
  );

  Widget _buildLadder() => SizedBox(
    height: 45,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      reverse: true,
      itemCount: prizeLadder.length,
      separatorBuilder: (_, __) => const SizedBox(width: 6),
      itemBuilder: (_, index) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 12),
        decoration: BoxDecoration(color: index == prizeIndexForQuestion(current) ? const Color(0xffd4a72c) : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: index == prizeIndexForQuestion(current) ? const Color(0xffd4a72c) : const Color(0xffe2e8f0))),
        child: Text('${prizeLadder[index]}', style: TextStyle(color: index == prizeIndexForQuestion(current) ? Colors.white : mutedInk, fontSize: 11, fontWeight: FontWeight.bold)),
      ),
    ),
  );

  Widget _buildResult() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Panel(
        child: Column(
          children: [
            const Icon(Icons.emoji_events_rounded, color: Color(0xffd4a72c), size: 72),
            const SizedBox(height: 12),
            const Text('انتهت الجولة', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.diamond_outlined, color: loginTeal, size: 26),
                const SizedBox(width: 6),
                    Text('$diamondBalance ماسة', style: const TextStyle(color: loginTeal, fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            Text('أفضل نتيجة: $bestScore', style: const TextStyle(color: mutedInk)),
            const SizedBox(height: 22),
            SizedBox(width: double.infinity, height: 50, child: FilledButton.icon(onPressed: restart, icon: const Icon(Icons.refresh), label: const Text('إعادة اللعب'))),
            if (history.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Align(alignment: AlignmentDirectional.centerStart, child: Text('سجل النتائج', style: TextStyle(fontWeight: FontWeight.bold))),
              const SizedBox(height: 8),
              ...history.take(5).map((value) => ListTile(dense: true, leading: const Icon(Icons.diamond_outlined, color: loginTeal), title: Text('$value ماسة'))),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _buildAttemptLost() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Panel(
        child: Column(
          children: [
            const Icon(Icons.lock_clock_rounded, color: Color(0xffd4a72c), size: 72),
            const SizedBox(height: 18),
            const Text(
              'انتهت محاولتك في طريق المليون. لقد استنفدت فرصتي الإجابة المسموح بهما خلال هذه الجولة. نتمنى لك حظاً أفضل في المحاولة القادمة.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, height: 1.6),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: returnToHomeAfterLoss,
                icon: const Icon(Icons.home_rounded),
                label: const Text('فهمت'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class HealthHubPage extends StatefulWidget {
  const HealthHubPage({super.key});

  @override
  State<HealthHubPage> createState() => _HealthHubPageState();
}

class _HealthHubPageState extends State<HealthHubPage>
    with SingleTickerProviderStateMixin {
  late final TabController tabController;
  int selectedTab = 0;
  bool deviceConnected = false;
  final List<double> glucoseReadings = [98, 105, 101, 110, 104, 99, 106];

  @override
  void initState() {
    super.initState();
    tabController = TabController(length: 3, vsync: this);
    tabController.addListener(() {
      if (tabController.index != selectedTab) {
        setState(() => selectedTab = tabController.index);
      }
    });
  }

  @override
  void dispose() {
    tabController.dispose();
    super.dispose();
  }

  void addVitalReading() {
    setState(() {
      glucoseReadings.add(100 + (glucoseReadings.length * 3) % 14);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ القراءة الجديدة في السجل الزمني')),
    );
  }

  @override
  Widget build(BuildContext context) => Shell(
    child: SafeArea(
      child: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverToBoxAdapter(child: _healthHeader()),
          SliverPersistentHeader(
            pinned: true,
            delegate: _HealthTabBarDelegate(
              TabBar(
                controller: tabController,
                isScrollable: true,
                indicatorColor: cyan,
                labelColor: emerald,
                unselectedLabelColor: mutedInk,
                tabs: const [
                  Tab(icon: Icon(Icons.bloodtype), text: 'التبرع بالدم'),
                  Tab(icon: Icon(Icons.favorite), text: 'فحص عضلة القلب'),
                  Tab(
                    icon: Icon(Icons.monitor_heart),
                    text: 'المؤشرات الحيوية',
                  ),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: tabController,
          children: [
            _DonationTab(onCreateRequest: () => _showRequestDialog(context)),
            _HeartTestTab(
              connected: deviceConnected,
              onConnect: () => setState(() => deviceConnected = true),
            ),
            _VitalsTab(
              readings: glucoseReadings,
              onAddReading: addVitalReading,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _healthHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xff2dd4bf).withValues(alpha: .16),
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xff2dd4bf).withValues(alpha: .5),
            ),
          ),
          child: const Icon(
            Icons.health_and_safety,
            color: Color(0xff5eead4),
            size: 34,
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'صحتي',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              Text(
                'مركزك الصحي في منصة ثيودور',
                style: TextStyle(color: mutedInk),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'التقارير الطبية',
          onPressed: () {},
          icon: const Icon(Icons.description_outlined),
        ),
      ],
    ),
  );

  Future<void> _showRequestDialog(BuildContext context) async {
    final nameController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('طلب دم جديد'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'اسم المريض أو المستشفى',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('تم تسجيل الطلب وسيظهر لفريق المطابقة'),
                ),
              );
            },
            child: const Text('إرسال الطلب'),
          ),
        ],
      ),
    );
    nameController.dispose();
  }
}

class _HealthTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _HealthTabBarDelegate(this.tabBar);
  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Container(color: bg, child: tabBar);
  @override
  bool shouldRebuild(covariant _HealthTabBarDelegate oldDelegate) => false;
}

class _HealthSection extends StatelessWidget {
  final Widget child;
  const _HealthSection({required this.child});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Panel(child: child),
  );
}

class _DonationTab extends StatelessWidget {
  final VoidCallback onCreateRequest;
  const _DonationTab({required this.onCreateRequest});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.only(bottom: 24),
    children: [
      _HealthSection(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'شبكة إنقاذ الأرواح',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'إدارة المتبرعين وطلبات الدم والحملات من لوحة واحدة.',
              style: TextStyle(color: mutedInk),
            ),
            const SizedBox(height: 18),
            Row(
              children: const [
                _MetricTile(
                  value: '1,284',
                  label: 'متبرع نشط',
                  color: Color(0xffff6b81),
                ),
                SizedBox(width: 10),
                _MetricTile(value: '36', label: 'طلب مفتوح', color: gold),
                SizedBox(width: 10),
                _MetricTile(value: '12', label: 'حملة قادمة', color: cyan),
              ],
            ),
          ],
        ),
      ),
      _HealthSection(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'عمليات سريعة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: onCreateRequest,
                  icon: const Icon(Icons.add),
                  label: const Text('طلب دم'),
                ),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('تسجيل متبرع'),
                ),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.campaign_outlined),
                  label: const Text('الحملات'),
                ),
              ],
            ),
          ],
        ),
      ),
      _HealthSection(
        child: _StatusRow(
          icon: Icons.bloodtype,
          color: Color(0xffff6b81),
          title: 'طلب عاجل - مستشفى المدينة',
          detail: 'O+  •  يحتاج 4 وحدات',
          status: 'مطابقة جارية',
        ),
      ),
      _HealthSection(
        child: _StatusRow(
          icon: Icons.event_available,
          color: cyan,
          title: 'حملة تبرع: محطة النور',
          detail: '28 أغسطس  •  09:00 صباحًا',
          status: 'مسجل',
        ),
      ),
    ],
  );
}

class _HeartTestTab extends StatelessWidget {
  final bool connected;
  final VoidCallback onConnect;
  const _HeartTestTab({required this.connected, required this.onConnect});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.only(bottom: 24),
    children: [
      _HealthSection(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'محطة فحص عضلة القلب',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                  ),
                ),
                Icon(
                  Icons.circle,
                  size: 11,
                    color: connected ? emerald : const Color(0xffc5cec8),
                ),
                const SizedBox(width: 6),
                Text(
                  connected ? 'متصل' : 'غير متصل',
                  style: TextStyle(
                    color: connected ? emerald : mutedInk,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'استقبل بيانات الجهاز، راجع القياسات، وأصدر تقريرًا طبيًا قابلًا للحفظ.',
              style: TextStyle(color: mutedInk),
            ),
            const SizedBox(height: 18),
            if (!connected)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onConnect,
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text('ربط جهاز الفحص'),
                ),
              )
            else ...[
              const _HeartReading(
                label: 'كفاءة الضخ EF',
                value: '62%',
                icon: Icons.favorite,
                color: Color(0xffff6b81),
              ),
              const SizedBox(height: 10),
              const _HeartReading(
                label: 'إيقاع القلب',
                value: 'منتظم',
                icon: Icons.monitor_heart,
                color: cyan,
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('إنشاء تقرير الفحص'),
              ),
            ],
          ],
        ),
      ),
      _HealthSection(
        child: _StatusRow(
          icon: Icons.history,
          color: violet,
          title: 'آخر فحص محفوظ',
          detail: '19 أغسطس 2026  •  ملف المريض الرئيسي',
          status: 'سليم',
        ),
      ),
    ],
  );
}

class _VitalsTab extends StatelessWidget {
  final List<double> readings;
  final VoidCallback onAddReading;
  const _VitalsTab({required this.readings, required this.onAddReading});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.only(bottom: 24),
    children: [
      _HealthSection(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'المؤشرات الحيوية',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'صورة زمنية واضحة لصحتك اليومية.',
              style: TextStyle(color: mutedInk),
            ),
            const SizedBox(height: 16),
            Row(
              children: const [
                _MetricTile(value: '104', label: 'سكر mg/dL', color: gold),
                SizedBox(width: 10),
                _MetricTile(value: '118/76', label: 'ضغط mmHg', color: cyan),
                SizedBox(width: 10),
                _MetricTile(
                  value: '72',
                  label: 'نبض / دقيقة',
                  color: Color(0xffff6b81),
                ),
              ],
            ),
          ],
        ),
      ),
      _HealthSection(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'تاريخ سكر الدم',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  onPressed: onAddReading,
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة قراءة'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 150,
              child: CustomPaint(painter: _VitalsChartPainter(readings)),
            ),
            const SizedBox(height: 8),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('منذ 7 أيام', style: TextStyle(color: mutedInk)),
                Text('اليوم', style: TextStyle(color: mutedInk)),
              ],
            ),
          ],
        ),
      ),
      _HealthSection(
        child: _StatusRow(
          icon: Icons.schedule,
          color: gold,
          title: 'آخر قراءة اليوم 08:40',
          detail: 'سكر 104  •  ضغط 118/76  •  نبض 72',
          status: 'طبيعي',
        ),
      ),
    ],
  );
}

class _MetricTile extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _MetricTile({
    required this.value,
    required this.label,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: mutedInk),
          ),
        ],
      ),
    ),
  );
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final String status;
  const _StatusRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.status,
  });
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(
      backgroundColor: color.withValues(alpha: .16),
      child: Icon(icon, color: color),
    ),
    title: Text(title),
    subtitle: Text(detail, style: const TextStyle(color: mutedInk)),
    trailing: Text(status, style: TextStyle(color: color, fontSize: 12)),
  );
}

class _HeartReading extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _HeartReading({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: color, size: 30),
    title: Text(label),
    trailing: Text(
      value,
      style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold),
    ),
  );
}

class _VitalsChartPainter extends CustomPainter {
  final List<double> values;
  _VitalsChartPainter(this.values);
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = cyan
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = cyan.withValues(alpha: .12)
      ..style = PaintingStyle.fill;
    final path = Path();
    final area = Path();
    final min = values.reduce((a, b) => a < b ? a : b) - 8;
    final max = values.reduce((a, b) => a > b ? a : b) + 8;
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1 ? 0.0 : i * size.width / (values.length - 1);
      final y = (size.height - ((values[i] - min) / (max - min) * size.height))
          .toDouble();
      if (i == 0) {
        path.moveTo(x, y);
        area.moveTo(x, size.height);
        area.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        area.lineTo(x, y);
      }
    }
    area.lineTo(size.width, size.height);
    area.close();
    canvas.drawPath(area, fill);
    canvas.drawPath(path, line);
    final dot = Paint()..color = Colors.white;
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1 ? 0.0 : i * size.width / (values.length - 1);
      final y = (size.height - ((values[i] - min) / (max - min) * size.height))
          .toDouble();
      canvas.drawCircle(Offset(x, y), 4, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _VitalsChartPainter oldDelegate) =>
      oldDelegate.values != values;
}

class LibraryBook {
  final String title;
  final String author;
  final String category;
  final String description;
  final Color color;
  final IconData icon;
  final bool available;

  const LibraryBook({
    required this.title,
    required this.author,
    required this.category,
    required this.description,
    required this.color,
    required this.icon,
    this.available = true,
  });
}

class ModernLibraryPage extends StatefulWidget {
  const ModernLibraryPage({super.key});

  @override
  State<ModernLibraryPage> createState() => _ModernLibraryPageState();
}

class _ModernLibraryPageState extends State<ModernLibraryPage> {
  final searchController = TextEditingController();
  String selectedCategory = 'الكل';
  String query = '';
  final borrowedBooks = <String>{};

  static const books = [
    LibraryBook(
      title: 'مدخل إلى التقنيات الحديثة',
      author: 'د. ليان السالم',
      category: 'علوم',
      description: 'دليل مبسط لاكتشاف المجرات والظواهر الكونية الحديثة.',
      color: cyan,
      icon: Icons.public,
    ),
    LibraryBook(
      title: 'أساسيات البرمجة',
      author: 'مروان حداد',
      category: 'تقنية',
      description: 'منطق البرمجة والخوارزميات من الصفر إلى بناء المشاريع.',
      color: violet,
      icon: Icons.code,
    ),
    LibraryBook(
      title: 'مختبر الإنسان',
      author: 'د. نور عادل',
      category: 'صحة',
      description: 'دليل عملي لفهم جسم الإنسان والعادات الصحية اليومية.',
      color: Color(0xff2dd4bf),
      icon: Icons.biotech,
    ),
    LibraryBook(
      title: 'فن التفكير',
      author: 'سارة منصور',
      category: 'تطوير',
      description: 'أدوات عملية لبناء عقل ناقد واتخاذ قرارات أفضل.',
      color: gold,
      icon: Icons.lightbulb_outline,
    ),
    LibraryBook(
      title: 'أطلس الحضارات',
      author: 'يوسف الكيلاني',
      category: 'تاريخ',
      description: 'خرائط وقصص مختارة من الحضارات التي شكلت عالمنا.',
      color: Color(0xffff8a65),
      icon: Icons.account_balance,
      available: false,
    ),
    LibraryBook(
      title: 'مختارات الأدب',
      author: 'مجموعة مؤلفين',
      category: 'أدب',
      description: 'نصوص قصيرة من الأدب العربي والعالمي في مجلد واحد.',
      color: Color(0xff60a5fa),
      icon: Icons.auto_stories,
    ),
  ];

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  List<LibraryBook> get filteredBooks => books.where((book) {
    final matchesCategory = selectedCategory == 'الكل' ||
        book.category == selectedCategory;
    final normalizedQuery = query.trim();
    final matchesQuery = normalizedQuery.isEmpty ||
        book.title.contains(normalizedQuery) ||
        book.author.contains(normalizedQuery) ||
        book.category.contains(normalizedQuery);
    return matchesCategory && matchesQuery;
  }).toList();

  @override
  Widget build(BuildContext context) => Shell(
    child: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 700;
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _libraryHeader(isCompact)),
              SliverToBoxAdapter(child: _libraryStats(isCompact)),
              SliverToBoxAdapter(child: _libraryControls(isCompact)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                sliver: filteredBooks.isEmpty
                    ? SliverToBoxAdapter(child: _emptyState())
                    : SliverGrid(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _BookCard(
                            book: filteredBooks[index],
                            borrowed: borrowedBooks.contains(
                              filteredBooks[index].title,
                            ),
                            onOpen: () => _showBookDetails(filteredBooks[index]),
                          ),
                          childCount: filteredBooks.length,
                        ),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: isCompact ? 1 : 3,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: isCompact ? 2.1 : .92,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _libraryHeader(bool isCompact) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xff60a5fa).withValues(alpha: .16),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xff60a5fa).withValues(alpha: .5)),
          ),
          child: const Icon(Icons.local_library, color: Color(0xff93c5fd), size: 34),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('المكتبة الحديثة', style: TextStyle(fontSize: 29, fontWeight: FontWeight.bold)),
              Text('معرفة مرتبة في مركز تقني واحد', style: TextStyle(color: mutedInk)),
            ],
          ),
        ),
        if (!isCompact)
          FilledButton.tonalIcon(
            onPressed: () {},
            icon: const Icon(Icons.add),
            label: const Text('إضافة كتاب'),
          ),
      ],
    ),
  );

  Widget _libraryStats(bool isCompact) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Row(
      children: [
        const _LibraryStat(value: '2,486', label: 'كتاب متاح', color: cyan),
        const SizedBox(width: 10),
        const _LibraryStat(value: '128', label: 'قارئ نشط', color: violet),
        const SizedBox(width: 10),
        _LibraryStat(value: '${borrowedBooks.length}', label: 'إعاراتي', color: gold),
      ],
    ),
  );

  Widget _libraryControls(bool isCompact) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
    child: Column(
      children: [
        TextField(
          controller: searchController,
          onChanged: (value) => setState(() => query = value),
          decoration: InputDecoration(
            hintText: 'ابحث باسم الكتاب أو المؤلف...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'مسح البحث',
                    onPressed: () {
                      searchController.clear();
                      setState(() => query = '');
                    },
                    icon: const Icon(Icons.clear),
                  ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xffd8e0db)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: ['الكل', 'علوم', 'تقنية', 'صحة', 'تطوير', 'تاريخ', 'أدب']
                .map(
                  (category) => Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(category),
                      selected: selectedCategory == category,
                      onSelected: (_) => setState(() => selectedCategory = category),
                      selectedColor: const Color(0xff60a5fa).withValues(alpha: .35),
                      side: const BorderSide(color: Color(0xffd8e0db)),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    ),
  );

  Widget _emptyState() => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      children: const [
        Icon(Icons.search_off, size: 48, color: mutedInk),
        SizedBox(height: 12),
        Text('لا توجد كتب مطابقة للبحث', style: TextStyle(color: mutedInk)),
      ],
    ),
  );

  Future<void> _showBookDetails(LibraryBook book) async {
    final alreadyBorrowed = borrowedBooks.contains(book.title);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(backgroundColor: book.color, radius: 27, child: Icon(book.icon)),
                const SizedBox(width: 14),
                Expanded(child: Text(book.title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold))),
              ]),
              const SizedBox(height: 18),
              Text('تأليف ${book.author}  •  ${book.category}', style: const TextStyle(color: mutedInk)),
              const SizedBox(height: 12),
              Text(book.description, style: const TextStyle(fontSize: 16, height: 1.5)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: !book.available || alreadyBorrowed
                      ? null
                      : () {
                          setState(() => borrowedBooks.add(book.title));
                          Navigator.pop(sheetContext);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('تمت إعارة «${book.title}» إلى حسابك')),
                          );
                        },
                  icon: Icon(alreadyBorrowed ? Icons.check : Icons.bookmark_add),
                  label: Text(alreadyBorrowed ? 'الكتاب في إعاراتي' : book.available ? 'استعارة الكتاب' : 'غير متاح حاليًا'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryStat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _LibraryStat({required this.value, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Panel(
      child: Column(
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(color: mutedInk, fontSize: 11)),
        ],
      ),
    ),
  );
}

class _BookCard extends StatelessWidget {
  final LibraryBook book;
  final bool borrowed;
  final VoidCallback onOpen;
  const _BookCard({required this.book, required this.borrowed, required this.onOpen});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onOpen,
    borderRadius: BorderRadius.circular(22),
    child: Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: book.color.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: book.color.withValues(alpha: .4)),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(book.icon, size: 72, color: book.color),
                  PositionedDirectional(
                    top: 8,
                    end: 8,
                    child: Chip(
                      label: Text(book.category, style: const TextStyle(fontSize: 11)),
                      backgroundColor: Colors.black26,
                      side: BorderSide.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(book.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: mutedInk, fontSize: 12)),
          const SizedBox(height: 10),
          Row(children: [
            Icon(book.available ? Icons.check_circle : Icons.schedule, size: 15, color: book.available ? Colors.greenAccent : gold),
            const SizedBox(width: 5),
            Expanded(child: Text(borrowed ? 'في إعاراتي' : book.available ? 'متاح للاستعارة' : 'قائمة انتظار', style: TextStyle(color: borrowed ? cyan : book.available ? Colors.greenAccent : gold, fontSize: 12))),
            const Icon(Icons.arrow_forward_ios, size: 14, color: mutedInk),
          ]),
        ],
      ),
    ),
  );
}

class ProgrammingPage extends StatelessWidget {
  const ProgrammingPage({super.key});
  @override
  Widget build(BuildContext context) => Shell(
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'تعليم البرمجة',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
          ),
          const Text(
            'اختر اللغة ثم الدورة والمستوى والدرس',
            style: TextStyle(color: mutedInk),
          ),
          const SizedBox(height: 20),
          const LanguageTile(
            name: 'Python',
            icon: Icons.auto_awesome,
            color: cyan,
          ),
          const LanguageTile(name: 'C++', icon: Icons.memory, color: violet),
        ],
      ),
    ),
  );
}

class LanguageTile extends StatelessWidget {
  final String name;
  final IconData icon;
  final Color color;
  const LanguageTile({
    required this.name,
    required this.icon,
    required this.color,
    super.key,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => CoursePage(language: name))),
        child: Panel(
          child: ListTile(
            leading: CircleAvatar(backgroundColor: color, child: Icon(icon)),
            title: Text(
              name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('اضغط لفتح الدورات والمستويات'),
            trailing: const Icon(Icons.arrow_forward_ios),
          ),
        ),
      ),
    ),
  );
}

class CoursePage extends StatelessWidget {
  final String language;
  const CoursePage({required this.language, super.key});
  @override
  Widget build(BuildContext context) => Shell(
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            'دورات $language',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const Text(
            'لغة ← دورة ← مستوى ← درس ← فيديو',
            style: TextStyle(color: mutedInk),
          ),
          const SizedBox(height: 18),
          CourseCard(language: language, title: 'أساسيات اللغة', vip: false),
          CourseCard(
            language: language,
            title: 'المسار الاحترافي VIP',
            vip: true,
          ),
        ],
      ),
    ),
  );
}

class CourseCard extends StatelessWidget {
  final String language;
  final String title;
  final bool vip;
  const CourseCard({
    required this.language,
    required this.title,
    required this.vip,
    super.key,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Panel(
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CourseContentPage(language: language, vip: vip),
          ),
        ),
        leading: Icon(
          Icons.play_circle_fill,
          color: vip ? gold : cyan,
          size: 34,
        ),
        title: Text(title),
        subtitle: Text(vip ? 'محتوى خاص للمشتركين' : 'محتوى عام متاح للجميع'),
        trailing: vip
            ? const Chip(label: Text('VIP'))
            : const Icon(Icons.arrow_forward_ios),
      ),
    ),
  );
}

class VideoItem {
  final int? id;
  final String language;
  final String title;
  final String url;
  final bool vip;
  final DateTime addedAt;
  VideoItem({
    this.id,
    required this.language,
    required this.title,
    required this.url,
    required this.vip,
  }) : addedAt = DateTime.now();

  VideoItem.fromJson(Map<String, dynamic> json)
    : id = json['id'] as int?,
      language = json['language'] as String,
      title = json['title'] as String,
      url = _resolveVideoUrl(json['url'] as String? ?? ''),
      vip = json['vip'] as bool? ?? json['access'] == 'vip',
      addedAt =
          DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'language': language,
    'title': title,
    'url': url,
    'vip': vip,
    'addedAt': addedAt.toIso8601String(),
  };
}

String _resolveVideoUrl(String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  if (url.startsWith('/')) return '$apiBaseUrl$url';
  return url;
}

final ValueNotifier<List<VideoItem>> videoCatalog =
    ValueNotifier<List<VideoItem>>([]);

const videoCatalogKey = 'video_catalog';

Future<void> loadVideoCatalog() async {
  var serverAvailable = false;
  var remoteVideos = <VideoItem>[];
  try {
    final remote = await TheodoreApi.authenticatedGet('/public/videos');
    if (remote.isNotEmpty || remote.isEmpty) {
      remoteVideos = remote
          .map((item) => VideoItem.fromJson(item as Map<String, dynamic>))
          .toList();
      serverAvailable = true;
    }
  } catch (_) {}
  var localVideos = <VideoItem>[];
  try {
    final saved = await const MethodChannel('com.alkawn.storage')
        .invokeMethod<String>('loadVideos');
    if (saved != null && saved.isNotEmpty) {
      localVideos = (jsonDecode(saved) as List)
          .map((item) => VideoItem.fromJson(item as Map<String, dynamic>))
          .where((video) => video.id != null)
          .toList();
    }
  } on MissingPluginException {
    // Web has no native storage channel; the catalog remains available in memory.
  }
  videoCatalog.value = _mergeVideos(remoteVideos, localVideos);
  if (serverAvailable) await syncPendingVideos();
}

List<VideoItem> _mergeVideos(
  Iterable<VideoItem> first,
  Iterable<VideoItem> second,
) {
  final merged = <String, VideoItem>{};
  for (final video in [...first, ...second]) {
    merged.putIfAbsent(
      '${video.language}|${video.title}|${video.vip}',
      () => video,
    );
  }
  return merged.values.toList();
}

Future<void> syncPendingVideos() async {
  final pending = videoCatalog.value
      .where(
        (video) =>
            video.id == null &&
            video.url.isNotEmpty &&
            !video.url.startsWith('http://') &&
            !video.url.startsWith('https://'),
      )
      .toList();
  for (final video in pending) {
    try {
      final published = await publishVideo(
        file: XFile(video.url),
        language: video.language,
        title: video.title,
        vip: video.vip,
      );
      videoCatalog.value = [
        ...videoCatalog.value.where((item) => item.url != video.url),
        published,
      ];
    } catch (_) {}
  }
  await saveVideoCatalog();
}

Future<void> saveVideoCatalog() async {
  try {
    await const MethodChannel('com.alkawn.storage').invokeMethod<void>(
      'saveVideos',
      jsonEncode(videoCatalog.value.map((item) => item.toJson()).toList()),
    );
  } on MissingPluginException {
    // Web has no native storage channel.
  }
}

Future<VideoItem> publishVideo({
  required XFile file,
  required String language,
  required String title,
  required bool vip,
}) async {
  final token = await TheodoreApi._token();
  final presign = await http.post(Uri.parse('$apiBaseUrl/admin/videos/presign'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode({'filename': file.name, 'content_type': 'video/mp4'})).timeout(const Duration(seconds: 8));
  if (presign.statusCode != 200) throw Exception('تعذر تجهيز رفع الفيديو');
  final presignData = jsonDecode(presign.body) as Map<String, dynamic>;
  final upload = await http.put(Uri.parse(presignData['upload_url'] as String), headers: {'Content-Type': 'video/mp4'}, body: await file.readAsBytes()).timeout(const Duration(minutes: 5));
  if (upload.statusCode < 200 || upload.statusCode >= 300) throw Exception('تعذر رفع الفيديو إلى R2');
  final publish = await http.post(Uri.parse('$apiBaseUrl/admin/videos/publish'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode({'language': language, 'title': title, 'object_key': presignData['key'], 'access': vip ? 'vip' : 'public'})).timeout(const Duration(seconds: 8));
  if (publish.statusCode != 200) throw Exception('تعذر نشر معلومات الفيديو');
  final data = jsonDecode(publish.body) as Map<String, dynamic>;
  return VideoItem.fromJson(data);
}

String normalizedTitle(String title) =>
    title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff]+'), '');

bool hasSimilarTitle(
  String title,
  String language,
  bool vip,
  Iterable<VideoItem> videos,
) {
  final normalized = normalizedTitle(title);
  return videos.any((video) {
    if (video.language != language || video.vip != vip) {
      return false;
    }
    final existing = normalizedTitle(video.title);
    return normalized.isNotEmpty &&
        (existing.contains(normalized) || normalized.contains(existing));
  });
}

class CourseContentPage extends StatefulWidget {
  final String language;
  final bool vip;
  final bool isAdmin;
  const CourseContentPage({
    required this.language,
    required this.vip,
    this.isAdmin = false,
    super.key,
  });
  @override
  State<CourseContentPage> createState() => _CourseContentPageState();
}

class _CourseContentPageState extends State<CourseContentPage> {
  final searchController = TextEditingController();
  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Shell(
    child: SafeArea(
      child: ValueListenableBuilder<List<VideoItem>>(
        valueListenable: videoCatalog,
        builder: (context, videos, _) {
          final query = searchController.text.trim().toLowerCase();
          final visibleVideos =
              videos
                  .where(
                    (video) =>
                        video.language == widget.language &&
                        video.vip == widget.vip &&
                        video.title.toLowerCase().contains(query),
                  )
                  .toList()
                ..sort((a, b) => a.addedAt.compareTo(b.addedAt));
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Text(
                widget.vip ? 'المسار الاحترافي VIP' : 'أساسيات اللغة',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${widget.language}  •  ${visibleVideos.length} مقطع',
                style: const TextStyle(color: mutedInk),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'ابحث في عناوين المقاطع',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  searchController.clear();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.clear),
                              ),
                      ),
                    ),
                  ),
                  if (widget.isAdmin) ...[
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'رفع مقطع جديد',
                      style: IconButton.styleFrom(
                        backgroundColor: gold,
                        foregroundColor: Colors.black,
                        minimumSize: const Size(52, 52),
                      ),
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => AddVideoDialog(
                          language: widget.language,
                          vip: widget.vip,
                        ),
                      ),
                      icon: const Icon(Icons.video_call),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 18),
              if (visibleVideos.isEmpty)
                Panel(
                  child: Column(
                    children: [
                      Icon(
                        Icons.video_library_outlined,
                        color: widget.vip ? gold : cyan,
                        size: 52,
                      ),
                      const SizedBox(height: 10),
                      const Text('لا توجد مقاطع مطابقة للبحث بعد.'),
                      const SizedBox(height: 4),
                      const Text(
                        'سيظهر المحتوى هنا بعد نشره من لوحة المدير.',
                        style: TextStyle(color: mutedInk),
                      ),
                    ],
                  ),
                )
              else
                ...visibleVideos.asMap().entries.map(
                  (entry) => VideoCard(
                    video: entry.value,
                    number: entry.key + 1,
                    isAdmin: widget.isAdmin,
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class VideoCard extends StatelessWidget {
  final VideoItem video;
  final int number;
  final bool isAdmin;
  const VideoCard({
    required this.video,
    required this.number,
    this.isAdmin = false,
    super.key,
  });

  Future<void> deleteVideo(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المقطع؟'),
        content: Text('سيتم حذف «${video.title}» من قائمة النشر.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (video.id != null) {
      try {
        await TheodoreApi.adminDelete('/admin/videos/${video.id}');
      } catch (_) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر حذف الفيديو من السيرفر')));
        return;
      }
    }
    videoCatalog.value = videoCatalog.value
        .where((item) => item.id != video.id)
        .toList();
    await saveVideoCatalog();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Panel(
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => VideoPlayerPage(video: video)),
        ),
        leading: CircleAvatar(
          backgroundColor: video.vip ? gold : cyan,
          child: Text('$number'),
        ),
        title: Text(video.title),
        subtitle: const Text('اضغط للتشغيل والتحكم بالتقديم'),
        trailing: isAdmin
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'تعديل النشر',
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => EditVideoDialog(video: video),
                    ),
                    icon: const Icon(Icons.edit),
                  ),
                  IconButton(
                    tooltip: 'حذف الفيديو',
                    onPressed: () => deleteVideo(context),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              )
            : const Icon(Icons.play_arrow),
      ),
    ),
  );
}

class VideoPlayerPage extends StatefulWidget {
  final VideoItem video;
  const VideoPlayerPage({required this.video, super.key});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? controller;
  Timer? controlsTimer;
  bool loading = true;
  String? error;
  bool fullscreen = false;
  bool controlsVisible = true;
  bool autoRotate = true;
  String quality = 'تلقائي';

  List<VideoItem> get playlist =>
      videoCatalog.value
          .where(
            (item) =>
                item.language == widget.video.language &&
                item.vip == widget.video.vip,
          )
          .toList()
        ..sort((a, b) => a.addedAt.compareTo(b.addedAt));

  int get currentIndex =>
      playlist.indexWhere((item) => item.id == widget.video.id);

  @override
  void initState() {
    super.initState();
    openVideo();
  }

  Future<void> openVideo() async {
    try {
      final source = widget.video.id == null
          ? widget.video.url
          : await TheodoreApi.signedVideoUrl(widget.video.id!);
      final created = await createVideoController(source);
      await created.initialize();
      if (!mounted) {
        await created.dispose();
        return;
      }
      setState(() {
        controller = created;
        loading = false;
      });
      created.addListener(videoChanged);
      showControls();
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'تعذر تشغيل هذا الفيديو';
        });
      }
    }
  }

  void videoChanged() {
    if (mounted) setState(() {});
  }

  void showControls() {
    controlsTimer?.cancel();
    if (!mounted) return;
    setState(() => controlsVisible = true);
    if (controller?.value.isPlaying == true) {
      controlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => controlsVisible = false);
      });
    }
  }

  Future<void> seekBy(Duration amount) async {
    final player = controller;
    if (player == null) return;
    final target = player.value.position + amount;
    final maximum = player.value.duration;
    await player.seekTo(
      target < Duration.zero
          ? Duration.zero
          : target > maximum
          ? maximum
          : target,
    );
  }

  Future<void> toggleFullscreen() async {
    setState(() => fullscreen = !fullscreen);
    await SystemChrome.setEnabledSystemUIMode(
      fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    showControls();
  }

  Future<void> toggleAutoRotate() async {
    setState(() => autoRotate = !autoRotate);
    await SystemChrome.setPreferredOrientations(
      autoRotate ? <DeviceOrientation>[] : [DeviceOrientation.portraitUp],
    );
  }

  void moveVideo(int offset) {
    final index = currentIndex + offset;
    if (index >= 0 && index < playlist.length) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => VideoPlayerPage(video: playlist[index]),
        ),
      );
    }
  }

  Widget buildVideoSurface() {
    final player = controller!;
    final video = VideoPlayer(player);
    return AspectRatio(aspectRatio: player.value.aspectRatio, child: video);
  }

  Widget buildFullscreenVideo() {
    final player = controller!;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: showControls,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: Colors.black,
            child: Center(
              child: AspectRatio(
                aspectRatio: player.value.aspectRatio,
                child: VideoPlayer(player),
              ),
            ),
          ),
          if (controlsVisible)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: ColoredBox(
                color: Colors.black54,
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'رجوع',
                        onPressed: toggleFullscreen,
                        icon: const Icon(Icons.arrow_back),
                      ),
                      Expanded(
                        child: Text(
                          widget.video.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                  ),
                ),
              ),
            ),
          if (controlsVisible)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ColoredBox(
                color: Colors.black54,
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      VideoProgressIndicator(
                        player,
                        allowScrubbing: true,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        colors: const VideoProgressColors(
                          playedColor: gold,
                          bufferedColor: Colors.white38,
                          backgroundColor: Colors.white12,
                        ),
                      ),
                      buildControls(),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget buildControls() => Wrap(
    alignment: WrapAlignment.center,
    spacing: 4,
    children: [
      IconButton(
        tooltip: 'الفيديو السابق',
        onPressed: currentIndex > 0 ? () => moveVideo(-1) : null,
        icon: const Icon(Icons.skip_previous),
      ),
      IconButton(
        tooltip: 'تأخير 5 ثوانٍ',
        onPressed: () => seekBy(const Duration(seconds: -5)),
        icon: const Icon(Icons.replay_5),
      ),
      IconButton.filled(
        tooltip: 'تشغيل أو إيقاف',
        onPressed: () async {
          if (controller!.value.isPlaying) {
            await controller!.pause();
          } else {
            await controller!.play();
          }
          showControls();
        },
        icon: Icon(
          controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
        ),
      ),
      IconButton(
        tooltip: 'تقديم 5 ثوانٍ',
        onPressed: () => seekBy(const Duration(seconds: 5)),
        icon: const Icon(Icons.forward_5),
      ),
      IconButton(
        tooltip: 'الفيديو التالي',
        onPressed: currentIndex >= 0 && currentIndex < playlist.length - 1
            ? () => moveVideo(1)
            : null,
        icon: const Icon(Icons.skip_next),
      ),
      IconButton(
        tooltip: 'إيقاف وإرجاع للبداية',
        onPressed: () async {
          await controller!.pause();
          await controller!.seekTo(Duration.zero);
        },
        icon: const Icon(Icons.stop),
      ),
      IconButton(
        tooltip: fullscreen ? 'تصغير الفيديو' : 'تكبير الفيديو',
        onPressed: toggleFullscreen,
        icon: Icon(fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
      ),
      IconButton(
        tooltip: autoRotate
            ? 'إيقاف التدوير التلقائي'
            : 'تفعيل التدوير التلقائي',
        onPressed: toggleAutoRotate,
        icon: Icon(
          autoRotate ? Icons.screen_rotation : Icons.screen_lock_rotation,
        ),
      ),
      PopupMenuButton<String>(
        tooltip: 'دقة الفيديو',
        initialValue: quality,
        onSelected: (value) => setState(() => quality = value),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'تلقائي', child: Text('الدقة: تلقائي')),
          PopupMenuItem(value: '480p', child: Text('الدقة: 480p')),
          PopupMenuItem(value: '720p', child: Text('الدقة: 720p')),
          PopupMenuItem(value: '1080p', child: Text('الدقة: 1080p')),
        ],
        child: Chip(label: Text(quality)),
      ),
    ],
  );

  @override
  void dispose() {
    controlsTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([]);
    controller?.removeListener(videoChanged);
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (error != null) {
      content = Panel(child: Text(error!));
    } else if (fullscreen) {
      content = Scaffold(
        backgroundColor: Colors.black,
        body: buildFullscreenVideo(),
      );
    } else {
      content = ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            widget.video.title,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 18),
          Panel(
            child: Column(
              children: [
                GestureDetector(
                  onTap: showControls,
                  child: buildVideoSurface(),
                ),
                if (controlsVisible)
                  VideoProgressIndicator(
                    controller!,
                    allowScrubbing: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    colors: const VideoProgressColors(
                      playedColor: gold,
                      bufferedColor: Colors.white38,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                if (controlsVisible) buildControls(),
              ],
            ),
          ),
        ],
      );
    }
    return fullscreen ? content : Shell(child: SafeArea(child: content));
  }
}

class AdminPage extends StatelessWidget {
  const AdminPage({super.key});
  @override
  Widget build(BuildContext context) => Shell(
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'لوحة المدير',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
          ),
          const Text(
            'إضافة مقاطع عامة أو خاصة VIP',
            style: TextStyle(color: mutedInk),
          ),
          const SizedBox(height: 18),
          _adminButton(context, 'لوحة الإحصائيات', Icons.dashboard_outlined, const AdminDashboardPage()),
          _adminButton(context, 'إدارة المستخدمين والرتب', Icons.manage_accounts_outlined, const AdminUsersPage()),
          _adminButton(context, 'ظهور الآيتمات والصلاحيات', Icons.visibility_outlined, const AdminItemsPage()),
          _adminButton(context, 'إدارة مقاطع الفيديو', Icons.video_library, const AdminVideoSpacesPage()),
          const SizedBox(height: 20),
          ValueListenableBuilder<List<VideoItem>>(
            valueListenable: videoCatalog,
            builder: (context, videos, _) => Text(
              'تم نشر ${videos.length} مقطعًا. تظهر المقاطع في مسارها بعد المزامنة.',
              style: const TextStyle(color: mutedInk),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _adminButton(BuildContext context, String title, IconData icon, Widget page) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)), icon: Icon(icon), label: Text(title))),
  );
}

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});
  @override
  Widget build(BuildContext context) => _AdminApiPage(title: 'لوحة الإحصائيات', path: '/admin/dashboard', builder: (data) => GridView.count(shrinkWrap: true, crossAxisCount: 2, children: [
    _AdminStat('إجمالي الحسابات', '${data['accounts']}'), _AdminStat('المستخدمون', '${data['users']}'), _AdminStat('المشرفون', '${data['supervisors']}'), _AdminStat('المديرون', '${data['admins']}'),
  ]));
}

class _AdminStat extends StatelessWidget {
  final String title; final String value;
  const _AdminStat(this.title, this.value);
  @override
  Widget build(BuildContext context) => Card(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: burgundy)), Text(title)]));
}

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});
  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}
class _AdminUsersPageState extends State<AdminUsersPage> {
  late Future<dynamic> users;
  @override
  void initState() { super.initState(); users = TheodoreApi.adminGet('/admin/users'); }
  @override
  Widget build(BuildContext context) => _AdminApiPage(title: 'إدارة المستخدمين', future: users, builder: (data) => Column(children: [for (final user in data) ListTile(
    title: Text(user['username']), subtitle: Text(user['is_original'] == true ? 'superadmin ثابت' : 'الرتبة: ${user['role']}'),
    trailing: user['is_original'] == true ? const Icon(Icons.lock, color: mutedInk) : DropdownButton<String>(value: user['role'] == 'admin' ? 'admin' : 'user', items: const [DropdownMenuItem(value: 'user', child: Text('user')), DropdownMenuItem(value: 'admin', child: Text('admin'))], onChanged: (role) async { if (role == null) return; await TheodoreApi.adminPut('/admin/users/${user['id']}/role', {'role': role}); setState(() { users = TheodoreApi.adminGet('/admin/users'); }); }),
  )]));
}

class AdminItemsPage extends StatefulWidget {
  const AdminItemsPage({super.key});
  @override
  State<AdminItemsPage> createState() => _AdminItemsPageState();
}
class _AdminItemsPageState extends State<AdminItemsPage> {
  late Future<dynamic> items;
  @override
  void initState() { super.initState(); items = TheodoreApi.adminGet('/admin/items'); }
  @override
  Widget build(BuildContext context) => _AdminApiPage(title: 'ظهور الآيتمات', future: items, builder: (data) => Column(children: [for (final item in data) ExpansionTile(title: Text(item['title']), children: [for (final role in const ['user', 'admin', 'superadmin']) SwitchListTile(title: Text(role), value: (item['roles'] as Map<String, dynamic>)[role] == true, onChanged: role == 'superadmin' ? null : (enabled) async { await TheodoreApi.adminPut('/admin/items/${item['key']}', {'role': role, 'enabled': enabled}); setState(() { items = TheodoreApi.adminGet('/admin/items'); }); })])]));
}

class _AdminApiPage extends StatelessWidget {
  final String title; final String? path; final Future<dynamic>? future; final Widget Function(dynamic) builder;
  const _AdminApiPage({required this.title, this.path, this.future, required this.builder});
  @override
  Widget build(BuildContext context) => _LearningScaffold(title: title, subtitle: 'إدارة مستقلة محفوظة على السيرفر', child: Panel(child: FutureBuilder<dynamic>(future: future ?? TheodoreApi.adminGet(path!), builder: (context, snapshot) { if (snapshot.hasError) return const Text('تعذر تحميل البيانات من السيرفر'); if (!snapshot.hasData) return const Center(child: CircularProgressIndicator()); return builder(snapshot.data); })));
}

class AdminVideoSpacesPage extends StatelessWidget {
  const AdminVideoSpacesPage({super.key});
  @override
  Widget build(BuildContext context) => Shell(
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'مقاطع الفيديو',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const Text(
            'اختر المسار لإضافة مقطع من زر الرفع بجانب البحث.',
            style: TextStyle(color: mutedInk),
          ),
          const SizedBox(height: 16),
          for (final space in const [
            ('Python', false),
            ('Python', true),
            ('C++', false),
            ('C++', true),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Panel(
                child: ListTile(
                  leading: Icon(
                    space.$2 ? Icons.workspace_premium : Icons.code,
                    color: space.$2 ? gold : cyan,
                  ),
                  title: Text('${space.$1} - ${space.$2 ? 'VIP' : 'عام'}'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CourseContentPage(
                        language: space.$1,
                        vip: space.$2,
                        isAdmin: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class AddVideoDialog extends StatefulWidget {
  final String language;
  final bool vip;
  const AddVideoDialog({this.language = 'Python', this.vip = false, super.key});
  @override
  State<AddVideoDialog> createState() => _AddVideoDialogState();
}

class EditVideoDialog extends StatefulWidget {
  final VideoItem video;
  const EditVideoDialog({required this.video, super.key});

  @override
  State<EditVideoDialog> createState() => _EditVideoDialogState();
}

class _EditVideoDialogState extends State<EditVideoDialog> {
  late final titleController = TextEditingController(text: widget.video.title);
  late String type = widget.video.vip ? 'VIP' : 'عام';

  @override
  void dispose() {
    titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('تعديل نشر الفيديو'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: titleController,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'عنوان الفيديو'),
        ),
        DropdownButtonFormField<String>(
          initialValue: type,
          items: const [
            DropdownMenuItem(value: 'عام', child: Text('عام')),
            DropdownMenuItem(value: 'VIP', child: Text('خاص VIP')),
          ],
          onChanged: (value) => setState(() => type = value!),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        onPressed: titleController.text.trim().isEmpty
            ? null
            : () async {
                final updatedVip = type == 'VIP';
                final others = videoCatalog.value.where(
                  (item) => item.url != widget.video.url,
                );
                if (hasSimilarTitle(
                  titleController.text.trim(),
                  widget.video.language,
                  updatedVip,
                  others,
                )) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('يوجد مقطع بعنوان مطابق أو مشابه بالفعل'),
                    ),
                  );
                  return;
                }
                videoCatalog.value = videoCatalog.value.map((item) {
                  if (item.url != widget.video.url) return item;
                  return VideoItem(
                    id: item.id,
                    language: item.language,
                    title: titleController.text.trim(),
                    url: item.url,
                    vip: updatedVip,
                  );
                }).toList();
                await saveVideoCatalog();
                if (context.mounted) Navigator.pop(context);
              },
        child: const Text('حفظ التعديل'),
      ),
    ],
  );
}

class _AddVideoDialogState extends State<AddVideoDialog> {
  final titleController = TextEditingController();
  String? selectedVideoPath;
  XFile? selectedFile;
  bool pickingVideo = false;
  bool publishing = false;
  late String language = widget.language;
  late String type = widget.vip ? 'VIP' : 'عام';
  @override
  void dispose() {
    titleController.dispose();
    super.dispose();
  }

  Future<void> pickVideo() async {
    setState(() => pickingVideo = true);
    try {
      const videoTypeGroup = XTypeGroup(
        label: 'videos',
        extensions: ['mp4', 'mov', 'webm', 'mkv', 'avi'],
      );
      final file = await openFile(acceptedTypeGroups: [videoTypeGroup]);
      if (!mounted || file == null) return;
      setState(() {
        selectedFile = file;
        selectedVideoPath = file.path;
      });
    } finally {
      if (mounted) setState(() => pickingVideo = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('إضافة مقطع'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: titleController,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'عنوان الفيديو'),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                selectedVideoPath == null
                    ? 'اختر فيديو من الجهاز'
                    : selectedVideoPath!.split(RegExp(r'[/\\]')).last,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'اختيار فيديو من الجهاز',
              onPressed: pickingVideo ? null : pickVideo,
              style: IconButton.styleFrom(
                backgroundColor: gold,
                foregroundColor: Colors.black,
                minimumSize: const Size(52, 52),
              ),
              icon: pickingVideo
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
            ),
          ],
        ),
        DropdownButtonFormField<String>(
          initialValue: language,
          items: const [
            DropdownMenuItem(value: 'Python', child: Text('Python')),
            DropdownMenuItem(value: 'C++', child: Text('C++')),
          ],
          onChanged: (value) => setState(() => language = value!),
        ),
        DropdownButtonFormField<String>(
          initialValue: type,
          items: const [
            DropdownMenuItem(value: 'عام', child: Text('عام')),
            DropdownMenuItem(value: 'VIP', child: Text('خاص VIP')),
          ],
          onChanged: (value) => setState(() => type = value!),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        onPressed:
            titleController.text.trim().isEmpty || selectedVideoPath == null
            ? null
            : publishing
            ? null
            : () async {
                final title = titleController.text.trim();
                final selectedVip = type == 'VIP';
                if (hasSimilarTitle(
                  title,
                  language,
                  selectedVip,
                  videoCatalog.value,
                )) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('يوجد مقطع بعنوان مطابق أو مشابه بالفعل'),
                    ),
                  );
                  return;
                }
                setState(() => publishing = true);
                try {
                  final published = await publishVideo(
                    file: selectedFile!,
                    language: language,
                    title: title,
                    vip: selectedVip,
                  );
                  videoCatalog.value = [...videoCatalog.value, published];
                  await saveVideoCatalog();
                  if (context.mounted) Navigator.pop(context);
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر رفع الفيديو ونشره على السيرفر')));
                  }
                } finally {
                  if (mounted) setState(() => publishing = false);
                }
              },
        child: Text(publishing ? 'جار النشر...' : 'نشر'),
      ),
    ],
  );
}
