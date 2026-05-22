import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../constants.dart';
import 'dashboard_screen.dart';
import 'package:flutter/cupertino.dart'; 

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  
  bool _isLogin = true;
  bool _showPassword = false;
  bool _loading = false;
  String _error = '';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Future<void> _handleGoogleSignIn() async {
    setState(() { _error = ''; _loading = true; });
    try {
      // Force account selection by signing out first
      await _googleSignIn.signOut();
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _loading = false);
        return; // aborted by user
      }
      final googleAuth = await googleUser.authentication;
      final OAuthCredential cred = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await _auth.signInWithCredential(cred);
      _goHome();
    } catch (e) {
      setState(() => _error = 'Failed to sign in with Google. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleSubmit() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) return;
    
    setState(() { _error = ''; _loading = true; });
    try {
      if (_isLogin) {
        await _auth.signInWithEmailAndPassword(email: email, password: pass);
      } else {
        await _auth.createUserWithEmailAndPassword(email: email, password: pass);
      }
      _goHome();
    } on FirebaseAuthException catch (e) {
      String msg = 'An error occurred. Please try again.';
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        msg = _isLogin ? 'Account not found or password incorrect.' : 'Failed to create account.';
      } else if (e.code == 'email-already-in-use') {
        msg = 'Email is already registered. Try signing in.';
      } else if (e.code == 'weak-password') {
        msg = 'Password should be at least 6 characters.';
      } else if (e.code == 'invalid-email') {
        msg = 'Invalid email address format.';
      }
      setState(() => _error = msg);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DashboardScreen())
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: Image.network(
              'https://images.unsplash.com/photo-1526778548025-fa2f459cd5ce?q=80&w=2606&auto=format&fit=crop',
              fit: BoxFit.cover,
            ),
          ),
          // Blur & Radial Gradient Overlay
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.5,
                    colors: [
                      Colors.white.withOpacity(0.2),
                      const Color(0xFFF8FAFC).withOpacity(0.95),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          // Auth Card
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 420),
                    padding: const EdgeInsets.all(40),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: Colors.white.withOpacity(0.6)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 30)
                      ]
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Brand Logo Icon
                        Container(
                          width: 80,
                          height: 80,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(color: kPrimary.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 8))
                            ]
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.asset('assets/icon.png', fit: BoxFit.cover),
                          ),
                        ),
                        const SizedBox(height: 32),
                        
                        Text(
                          _isLogin ? 'KM Tracker' : 'Explore with KM',
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: kTextMain, letterSpacing: -1.2),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _isLogin ? 'Sign in to record your path' : 'Join the next generation of tracking',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: kTextMuted, letterSpacing: -0.2),
                        ),
                        const SizedBox(height: 32),

                        if (_error.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              color: kDanger.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: kDanger.withOpacity(0.1)),
                            ),
                            child: Text(_error, style: const TextStyle(color: kDanger, fontWeight: FontWeight.w500, fontSize: 14), textAlign: TextAlign.center,),
                          ),

                        // Form Inputs
                        TextField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            hintText: 'Email Address',
                            prefixIcon: Icon(CupertinoIcons.mail),
                          ),
                          enabled: !_loading,
                          style: const TextStyle(color: kTextMain),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _passCtrl,
                          obscureText: !_showPassword,
                          decoration: InputDecoration(
                            hintText: 'Password',
                            prefixIcon: const Icon(CupertinoIcons.lock),
                            suffixIcon: IconButton(
                              icon: Icon(_showPassword ? CupertinoIcons.eye_slash : CupertinoIcons.eye),
                              onPressed: () => setState(() => _showPassword = !_showPassword),
                            ),
                          ),
                          enabled: !_loading,
                          style: const TextStyle(color: kTextMain),
                        ),

                        if (_isLogin)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () {}, 
                              child: const Text('Forgot password?', style: TextStyle(color: kPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                            ),
                          )
                        else 
                          const SizedBox(height: 32),

                        // Primary Button
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [kPrimary, kPrimaryL]),
                            borderRadius: BorderRadius.circular(16)
                          ),
                          child: ElevatedButton(
                            onPressed: _loading ? null : _handleSubmit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: _loading 
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(_isLogin ? 'Sign In' : 'Create Account', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                                    if (_isLogin) const Icon(CupertinoIcons.arrow_right, color: Colors.white, size: 18).paddingOnly(left: 8),
                                  ],
                                ),
                          ),
                        ),

                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(child: Container(height: 1, color: Colors.black12)),
                            const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('OR', style: TextStyle(color: kTextMuted, fontWeight: FontWeight.w700, fontSize: 12))),
                            Expanded(child: Container(height: 1, color: Colors.black12)),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Google Sign In
                        OutlinedButton(
                          onPressed: _loading ? null : _handleGoogleSignIn,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            side: const BorderSide(color: Colors.black12),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            minimumSize: const Size(double.infinity, 0),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Google G Logo (basic stand-in)
                              Icon(CupertinoIcons.at, color: kTextMain), 
                              SizedBox(width: 12),
                              Text('Continue with Google', style: TextStyle(color: kTextMain, fontSize: 15, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_isLogin ? 'New explorer? ' : 'Already tracking? ', style: const TextStyle(color: kTextMuted, fontWeight: FontWeight.w500)),
                            GestureDetector(
                              onTap: () {
                                if (!_loading) setState(() => _isLogin = !_isLogin);
                              },
                              child: Text(_isLogin ? 'Create account' : 'Sign in', style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w600)),
                            )
                          ],
                        )
                      ],
                    ),
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

extension PaddingExtension on Widget {
  Widget paddingOnly({double left = 0, double top = 0, double right = 0, double bottom = 0}) {
    return Padding(padding: EdgeInsets.only(left: left, top: top, right: right, bottom: bottom), child: this);
  }
}
