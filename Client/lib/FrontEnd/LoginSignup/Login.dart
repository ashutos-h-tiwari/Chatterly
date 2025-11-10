import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:ui';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'Signup.dart';
import '../HomePage/HomePage.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();

  // Login endpoint
  static const String kLoginUrl = 'https://chatterly-auth-api.onrender.com/api/auth/login';

  bool _showPortal = true;
  bool _showIntro = false;
  bool _isLoading = false;
  bool _obscure = true;

  late AnimationController _introController;
  late Animation<double> _sutraScale;
  late Animation<double> _sutraOpacity;
  late Animation<double> _taglineOpacity;

  String _welcomeName = "";

  @override
  void initState() {
    super.initState();

    _introController = AnimationController(vsync: this, duration: const Duration(seconds: 1));
    _sutraScale = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _introController, curve: Curves.easeOutExpo),
    );
    _sutraOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _introController, curve: Curves.easeOutExpo),
    );
    _taglineOpacity = Tween<double>(begin: 0, end: 0.92).animate(
      CurvedAnimation(parent: _introController, curve: const Interval(0.15, 1.0, curve: Curves.easeIn)),
    );

    _introController.addStatusListener((status) async {
      if (status == AnimationStatus.completed) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomePage()),
        );
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    _introController.dispose();
    super.dispose();
  }

  // --- NEW: decode JWT to extract userId (sub/id/userId) ---
  String? _extractUserIdFromJwt(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;

      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final map = jsonDecode(payload) as Map<String, dynamic>;

      final id = map['sub'] ?? map['id'] ?? map['userId'];
      return id?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _threadIn() async {
    final email = _nameController.text.trim();
    final pass = _passwordController.text.trim();

    if (email.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill in all fields")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final uri = Uri.parse(kLoginUrl);

      final resp = await http
          .post(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: jsonEncode({"email": email, "password": pass}),
      )
          .timeout(const Duration(seconds: 20));

      Map<String, dynamic>? data;
      try {
        data = jsonDecode(resp.body) as Map<String, dynamic>?;
      } catch (_) {}

      if (resp.statusCode == 200) {
        final token = data?["token"]?.toString();
        if (token == null || token.isEmpty) {
          _showError("Login failed: token missing");
        } else {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString("token", token);

          // NEW: derive & store my userId for rooms/messages etc.
          final myId = _extractUserIdFromJwt(token);
          if (myId != null && myId.isNotEmpty) {
            await prefs.setString("userId", myId);
          }

          if (!mounted) return;
          setState(() {
            _welcomeName = email; // you can replace with /me later
            _showPortal = false;
            _showIntro = true;
          });
          _introController.forward();
        }
      } else if (resp.statusCode == 401) {
        _showError(data?["message"] ?? "Invalid email or password");
      } else {
        _showError(data?["message"] ?? "Server error: ${resp.statusCode}");
      }
    } catch (e) {
      _showError("Network error: $e");
    } finally {
      if (mounted && !_showIntro) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final mutedColor = const Color(0xFFEAF2FF);
    final goldStrong = const Color(0xFFFFCC4D);
    final bgDeep1 = const Color(0xFF070416);
    final portalDiameter = min(
      MediaQuery.of(context).size.width * 0.9,
      MediaQuery.of(context).size.height * 0.61,
    );

    return Scaffold(
      backgroundColor: bgDeep1,
      body: Stack(
        children: [
          const Positioned.fill(child: StarryBackground()),

          // Outer glow portal ring
          Positioned.fill(
            child: Center(
              child: Container(
                width: portalDiameter * 1.32,
                height: portalDiameter * 1.32,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Color.fromRGBO(255, 215, 100, 0.20),
                      Color.fromRGBO(255, 215, 100, 0.09),
                      Colors.transparent,
                    ],
                    stops: [0.0, 0.6, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color.fromRGBO(255, 215, 100, 0.23),
                      blurRadius: 64,
                      spreadRadius: 12,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Portal Login Form
          if (_showPortal)
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(portalDiameter / 2),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    width: portalDiameter,
                    height: portalDiameter,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(portalDiameter / 2),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.02),
                          Colors.white.withOpacity(0.01),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      border: Border.all(color: Colors.white.withOpacity(0.04)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color.fromRGBO(6, 8, 20, 0.6),
                          offset: Offset(0, 30),
                          blurRadius: 80,
                        ),
                      ],
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Align(
                          alignment: Alignment.center,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18.0),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "Enter the Thread",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 22,
                                      color: mutedColor,
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    "Weave into Sutra — one warm connection",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: mutedColor.withOpacity(0.78),
                                    ),
                                  ),
                                  const SizedBox(height: 20),

                                  // Email field (API expects email)
                                  TextField(
                                    controller: _nameController,
                                    style: TextStyle(color: mutedColor),
                                    textInputAction: TextInputAction.next,
                                    decoration: InputDecoration(
                                      hintText: "Email",
                                      filled: true,
                                      fillColor: Colors.white.withOpacity(0.02),
                                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(999),
                                        borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(999),
                                        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),

                                  // Password field
                                  TextField(
                                    controller: _passwordController,
                                    obscureText: _obscure,
                                    onSubmitted: (_) => _isLoading ? null : _threadIn(),
                                    style: TextStyle(color: mutedColor),
                                    decoration: InputDecoration(
                                      hintText: "Secret thread",
                                      filled: true,
                                      fillColor: Colors.white.withOpacity(0.02),
                                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(999),
                                        borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(999),
                                        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                                      ),
                                      suffixIcon: IconButton(
                                        onPressed: () => setState(() => _obscure = !_obscure),
                                        icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // Login button
                                  SizedBox(
                                    width: portalDiameter * 0.7,
                                    height: 42,
                                    child: ElevatedButton(
                                      onPressed: _isLoading ? null : _threadIn,
                                      style: ElevatedButton.styleFrom(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        backgroundColor: goldStrong,
                                        shadowColor: Colors.orange.withOpacity(0.08),
                                        elevation: 10,
                                      ),
                                      child: _isLoading
                                          ? const SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(
                                          color: Colors.black,
                                          strokeWidth: 3,
                                        ),
                                      )
                                          : Text(
                                        "Thread-In →",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: Colors.brown[900],
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Intro Animation (SUTRA)
          if (_showIntro)
            Center(
              child: FadeTransition(
                opacity: _sutraOpacity,
                child: ScaleTransition(
                  scale: _sutraScale,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "SUTRA",
                        style: TextStyle(
                          fontSize: 64,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 6,
                          color: Color(0xFF4DA6FF),
                        ),
                      ),
                      const SizedBox(height: 14),
                      FadeTransition(
                        opacity: _taglineOpacity,
                        child: Text(
                          "threads that talk.",
                          style: TextStyle(
                            fontSize: 15,
                            color: mutedColor.withOpacity(0.92),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Signup button
          if (_showPortal)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => SignupPage()),
                    );
                  },
                  child: Text(
                    "Don't have an account? Signup",
                    style: TextStyle(
                      color: goldStrong,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// STAR BACKGROUND (unchanged)
class StarryBackground extends StatefulWidget {
  const StarryBackground({super.key});

  @override
  State<StarryBackground> createState() => _StarryBackgroundState();
}

class _StarryBackgroundState extends State<StarryBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  List<_Star> stars = [];
  final int starCount = 70;
  Size lastSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 30))
      ..addListener(() => setState(() {}))
      ..repeat();
  }

  void _initStars(Size size) {
    final random = Random();
    stars = List.generate(starCount, (index) {
      return _Star(
        x: random.nextDouble() * size.width,
        y: random.nextDouble() * size.height,
        r: 1.6 + random.nextDouble() * 2.2,
        baseAlpha: 0.25 + random.nextDouble() * 0.65,
        phase: random.nextDouble() * pi * 2,
        dx: (random.nextDouble() - 0.5) * 0.15,
        dy: (random.nextDouble() - 0.5) * 0.15,
      );
    });
  }

  void _updateStars(Size size) {
    if (stars.isEmpty || lastSize != size) {
      _initStars(size);
      lastSize = size;
    }
    for (var star in stars) {
      star.phase += 0.007;
      star.x += star.dx;
      star.y += star.dy;
      if (star.x < -5) star.x = size.width + 5;
      if (star.x > size.width + 5) star.x = -5;
      if (star.y < -5) star.y = size.height + 5;
      if (star.y > size.height + 5) star.y = -5;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        _updateStars(size);
        return CustomPaint(size: size, painter: _StarPainter(stars));
      },
    );
  }
}

class _Star {
  double x, y, r, baseAlpha, phase, dx, dy;
  _Star({
    required this.x,
    required this.y,
    required this.r,
    required this.baseAlpha,
    required this.phase,
    required this.dx,
    required this.dy,
  });
}

class _StarPainter extends CustomPainter {
  final List<_Star> stars;
  _StarPainter(this.stars);

  @override
  void paint(Canvas canvas, Size size) {
    for (var star in stars) {
      final twinkle = (star.baseAlpha + sin(star.phase) * 0.28).clamp(0.18, 0.9);
      final glowPaint = Paint()
        ..color = Color.fromARGB((twinkle * 140).toInt(), 255, 230, 140)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, star.r * 2.4);
      canvas.drawCircle(Offset(star.x, star.y), star.r * 2.4, glowPaint);
      final paint = Paint()
        ..color = Color.fromARGB((twinkle * 255).toInt(), 255, 237, 120);
      canvas.drawCircle(Offset(star.x, star.y), star.r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StarPainter oldDelegate) => true;
}
