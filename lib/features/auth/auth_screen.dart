import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/farmland_background.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/brand_mark.dart';
import '../../widgets/pill_button.dart';

class AuthScreen extends StatefulWidget {
  final bool startOnSignUp;
  const AuthScreen({super.key, this.startOnSignUp = false});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late bool _signUp = widget.startOnSignUp;
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;
  String _role = 'farmer';

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok = _signUp
        ? await auth.register(
            username: _username.text, email: _email.text, password: _password.text, role: _role)
        : await auth.login(_username.text, _password.text);
    if (!mounted) return;
    if (ok) {
      context.go('/home');
    } else if (auth.error != null) {
      showToast(context, auth.error!);
    }
  }

  Future<void> _google() async {
    if (!AppConfig.googleConfigured) {
      showToast(context, "Google sign-in isn't set up yet.");
      return;
    }
    final auth = context.read<AuthProvider>();
    final ok = await auth.loginWithGoogle();
    if (!mounted) return;
    if (ok) {
      context.go('/home');
    } else if (auth.error != null) {
      showToast(context, auth.error!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: FarmlandBackground(
        showPins: false,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BrandMark(markSize: 38, nameSize: 21),
                    const SizedBox(height: 26),
                    Text.rich(
                      TextSpan(
                        style: const TextStyle(
                            fontFamily: 'Fraunces',
                            fontWeight: FontWeight.w900,
                            fontSize: 34,
                            height: 1.05,
                            color: Colors.white),
                        children: [
                          TextSpan(text: _signUp ? 'Create ' : 'Welcome '),
                          TextSpan(
                            text: _signUp ? 'account.' : 'back.',
                            style: const TextStyle(
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.w500,
                                color: AppColors.gold),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                        _signUp
                            ? 'Join the agricultural revolution.'
                            : 'Log in to your farm dashboard.',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.9))),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _toggle(),
                          const SizedBox(height: 20),
                          _label('Username'),
                          TextFormField(
                            controller: _username,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                                hintText: 'your_username',
                                prefixIcon: Icon(Icons.person_outline)),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty) ? 'Enter your username' : null,
                          ),
                          if (_signUp) ...[
                            const SizedBox(height: 14),
                            _label('Email'),
                            TextFormField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                  hintText: 'you@example.com',
                                  prefixIcon: Icon(Icons.mail_outline)),
                              validator: (v) {
                                if (!_signUp) return null;
                                if (v == null || v.trim().isEmpty) return 'Enter your email';
                                if (!v.contains('@')) return 'Enter a valid email';
                                return null;
                              },
                            ),
                          ],
                          const SizedBox(height: 14),
                          _label('Password'),
                          TextFormField(
                            controller: _password,
                            obscureText: _obscure,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              hintText: '........',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) {
                              final min = _signUp ? 6 : 1;
                              if (v == null || v.length < min) {
                                return _signUp ? 'Use at least 6 characters' : 'Enter your password';
                              }
                              return null;
                            },
                          ),
                          if (_signUp) ...[
                            const SizedBox(height: 16),
                            _label('I am a'),
                            const SizedBox(height: 4),
                            _roles(),
                          ],
                          const SizedBox(height: 22),
                          PillButton(
                              label: _signUp ? 'Create account' : 'Sign in',
                              loading: auth.busy,
                              fullWidth: true,
                              onPressed: _submit),
                          const SizedBox(height: 16),
                          Row(children: const [
                            Expanded(child: Divider(color: AppColors.line)),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Text('or',
                                  style: TextStyle(fontFamily: 'Inter', color: AppColors.slate500)),
                            ),
                            Expanded(child: Divider(color: AppColors.line)),
                          ]),
                          const SizedBox(height: 16),
                          _googleButton(auth.busy ? null : _google),
                          const SizedBox(height: 12),
                          Center(
                            child: TextButton(
                              onPressed: () => setState(() => _signUp = !_signUp),
                              child: Text.rich(
                                TextSpan(
                                  text: _signUp
                                      ? 'Already have an account? '
                                      : "Don't have an account? ",
                                  style: const TextStyle(
                                      fontFamily: 'Inter', color: AppColors.slate600, fontSize: 14),
                                  children: [
                                    TextSpan(
                                      text: _signUp ? 'Sign in' : 'Sign up',
                                      style: const TextStyle(
                                          color: AppColors.g700, fontWeight: FontWeight.w800),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(t,
              style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.slate700)),
        ),
      );

  Widget _toggle() {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration:
          BoxDecoration(color: const Color(0xFFF1F3EE), borderRadius: BorderRadius.circular(14)),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
            alignment: _signUp ? Alignment.centerRight : Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                    gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(11)),
              ),
            ),
          ),
          Row(children: [
            _seg('Sign In', !_signUp, () => setState(() => _signUp = false)),
            _seg('Sign Up', _signUp, () => setState(() => _signUp = true)),
          ]),
        ],
      ),
    );
  }

  Widget _seg(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Text(label,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : AppColors.slate600)),
        ),
      ),
    );
  }

  Widget _roles() {
    const roles = [
      ['farmer', 'Farmer'],
      ['retailer', 'Buyer'],
      ['specialized', 'Professional'],
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: roles.map((r) {
        final active = _role == r[0];
        return ChoiceChip(
          label: Text(r[1]),
          selected: active,
          onSelected: (_) => setState(() => _role = r[0]),
          selectedColor: AppColors.green,
          labelStyle: TextStyle(
              fontFamily: 'Inter',
              color: active ? Colors.white : AppColors.inkWarm,
              fontWeight: FontWeight.w600),
          backgroundColor: AppColors.cream,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.line)),
        );
      }).toList(),
    );
  }

  Widget _googleButton(VoidCallback? onPressed) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line)),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('G',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: Color(0xFF4285F4))),
              SizedBox(width: 10),
              Text('Continue with Google',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Color(0xFF3C4043))),
            ],
          ),
        ),
      ),
    );
  }
}
