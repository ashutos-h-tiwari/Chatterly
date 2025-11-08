import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:ui';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../HomePage/HomePage.dart';
import 'Login.dart';

class SignupPage extends StatefulWidget {
  @override
  _SignupPageState createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  String email = '';
  String password = '';
  String confirmPassword = '';
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final String signupUrl = 'https://chatterly-auth-api.onrender.com/api/auth/signup';

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse(signupUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': _emailController.text,
          'password': _passwordController.text
        }),
      );
      print(response.body); // Debug network result
      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Success'),
            content: Text('User registered successfully!'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                },
                child: Text('OK'),
              ),
            ],
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => HomePage()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message'] ?? 'Signup failed')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Signup failed: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mutedColor = Color(0xFFEAF2FF);
    final goldStrong = Color(0xFFFFCC4D);

    double portalDiameter = min(MediaQuery.of(context).size.width * 0.82,
        MediaQuery.of(context).size.height * 0.63);

    return Scaffold(
      backgroundColor: Color(0xFF070416),
      body: Stack(
        children: [
          Positioned.fill(child: StarryBackground()),

          // Portal Glow
          Positioned.fill(
            child: Center(
              child: Container(
                width: portalDiameter * 1.25,
                height: portalDiameter * 1.25,
                decoration: BoxDecoration(
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

          // Centered Signup Circle
          Align(
            alignment: Alignment.center,
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
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withOpacity(0.02),
                        Colors.white.withOpacity(0.01),
                      ],
                    ),
                    border: Border.all(color: Colors.white.withOpacity(0.04)),
                    boxShadow: [
                      BoxShadow(
                        color: Color.fromRGBO(6, 8, 20, 0.6),
                        offset: Offset(0, 30),
                        blurRadius: 80,
                      )
                    ],
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(portalDiameter / 2),
                          gradient: RadialGradient(
                            colors: [
                              Color.fromRGBO(255, 200, 90, 0.14),
                              Color.fromRGBO(255, 140, 30, 0.06),
                              Colors.transparent,
                            ],
                            stops: [0.0, 0.35, 0.55],
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.center,
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: portalDiameter * 0.09,
                                vertical: portalDiameter * 0.035
                            ),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "Create Account",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                      color: mutedColor,
                                    ),
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    "Sign up to get started",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: mutedColor.withOpacity(0.78),
                                    ),
                                  ),
                                  SizedBox(height: 13),
                                  SizedBox(
                                    height: 36,
                                    child: TextFormField(
                                      controller: _emailController,
                                      keyboardType: TextInputType.emailAddress,
                                      style: TextStyle(color: mutedColor, fontSize: 13),
                                      decoration: InputDecoration(
                                        hintText: "Your email...",
                                        filled: true,
                                        fillColor: Colors.white.withOpacity(0.02),
                                        contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(99),
                                          borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(99),
                                          borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                                        ),
                                      ),
                                      validator: (value) {
                                        if (value == null || value.trim().isEmpty) {
                                          return 'Please enter your email';
                                        }
                                        if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                                          return 'Enter a valid email';
                                        }
                                        return null;
                                      },
                                      onSaved: (val) => email = val!.trim(),
                                    ),
                                  ),
                                  SizedBox(height: 6),
                                  SizedBox(
                                    height: 36,
                                    child: TextFormField(
                                      controller: _passwordController,
                                      obscureText: _obscurePassword,
                                      style: TextStyle(color: mutedColor, fontSize: 13),
                                      decoration: InputDecoration(
                                        hintText: "Create password",
                                        filled: true,
                                        fillColor: Colors.white.withOpacity(0.02),
                                        contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(99),
                                          borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(99),
                                          borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                                        ),
                                        suffixIcon: IconButton(
                                          icon: Icon(
                                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                            color: goldStrong, size: 19,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _obscurePassword = !_obscurePassword;
                                            });
                                          },
                                        ),
                                      ),
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Please enter your password';
                                        }
                                        if (value.length < 6) {
                                          return 'Password must be at least 6 characters';
                                        }
                                        return null;
                                      },
                                      onSaved: (val) => password = val!,
                                    ),
                                  ),
                                  SizedBox(height: 6),
                                  SizedBox(
                                    height: 36,
                                    child: TextFormField(
                                      obscureText: _obscureConfirmPassword,
                                      style: TextStyle(color: mutedColor, fontSize: 13),
                                      decoration: InputDecoration(
                                        hintText: "Confirm password",
                                        filled: true,
                                        fillColor: Colors.white.withOpacity(0.02),
                                        contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(99),
                                          borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(99),
                                          borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                                        ),
                                        suffixIcon: IconButton(
                                          icon: Icon(
                                            _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                                            color: goldStrong, size: 19,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _obscureConfirmPassword = !_obscureConfirmPassword;
                                            });
                                          },
                                        ),
                                      ),
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Please confirm your password';
                                        }
                                        if (value != _passwordController.text) {
                                          return 'Passwords do not match';
                                        }
                                        return null;
                                      },
                                      onSaved: (val) => confirmPassword = val!,
                                    ),
                                  ),
                                  SizedBox(height: 10),
                                  SizedBox(
                                    width: portalDiameter * 0.8,
                                    height: 40,
                                    child: ElevatedButton(
                                      child: _isLoading
                                          ? CircularProgressIndicator(color: Colors.black, strokeWidth: 2)
                                          : Text('Sign Up', style: TextStyle(fontSize: 15)),
                                      style: ElevatedButton.styleFrom(
                                        foregroundColor: Colors.black,
                                        backgroundColor: goldStrong,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        padding: EdgeInsets.symmetric(horizontal: 0),
                                      ),
                                      onPressed: _isLoading ? null : _signUp,
                                    ),
                                  ),

                                ],
                              ),
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

          // Log-in prompt ALWAYS at the bottom of the screen
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: 36),
              child: TextButton(
                child: Text(
                  "Already have an account? Log-in",
                  style: TextStyle(
                      color: goldStrong, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => LoginPage()),
                  );
                },
              ),
            ),
          ),

          // Loading overlay
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.2),
                child: Center(
                  child: CircularProgressIndicator(
                    color: goldStrong,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

  }
}
