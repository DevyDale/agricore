import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/prefs_service.dart';
import '../../widgets/farmland_background.dart';
import '../../widgets/brand_mark.dart';
import '../../widgets/pill_button.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _scroll = ScrollController();
  final _featuresKey = GlobalKey();

  Future<void> _go() async {
    await PrefsService.setOnboardingSeen();
    if (mounted) context.go('/login');
  }

  void _seeInside() {
    final ctx = _featuresKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: SingleChildScrollView(
        controller: _scroll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _hero(context, h),
            _introSection(),
            _featuresSection(),
            _stepsSection(),
            _ctaBand(),
            _footer(),
          ],
        ),
      ),
    );
  }

  // ----- HERO -----
  Widget _hero(BuildContext context, double h) {
    return SizedBox(
      height: h * 0.96,
      child: FarmlandBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const BrandMark(markSize: 40, nameSize: 22),
                    _frostedPill(
                      onTap: _go,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text('Sign in',
                              style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Colors.white)),
                          SizedBox(width: 6),
                          Icon(Icons.arrow_forward, size: 15, color: Colors.white),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                _kicker(),
                const SizedBox(height: 18),
                Text.rich(
                  TextSpan(
                    style: const TextStyle(
                        fontFamily: 'Fraunces',
                        fontWeight: FontWeight.w900,
                        fontSize: 52,
                        height: 1.02,
                        letterSpacing: -1.5,
                        color: Colors.white),
                    children: const [
                      TextSpan(text: 'Grow more.\n'),
                      TextSpan(
                          text: 'Sell',
                          style: TextStyle(
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w500,
                              color: AppColors.gold)),
                      TextSpan(text: ' smarter.'),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'One digital platform to manage your farms, trade produce, '
                  'connect with professionals, and unlock AI-powered insights — '
                  'built for the way Africa farms.',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15.5,
                      height: 1.6,
                      color: Colors.white.withValues(alpha: 0.92)),
                ),
                const SizedBox(height: 26),
                PillButton(
                    label: 'Get started now',
                    trailingIcon: Icons.arrow_forward,
                    fullWidth: true,
                    onPressed: _go),
                const SizedBox(height: 10),
                PillButton(label: "See what's inside", ghost: true, fullWidth: true, onPressed: _seeInside),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF86EFAC)),
                    const SizedBox(width: 8),
                    Text('No credit card required · Free to start',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12.5,
                            color: Colors.white.withValues(alpha: 0.85))),
                  ],
                ),
                const Spacer(),
                Center(
                  child: Icon(Icons.keyboard_arrow_down_rounded,
                      color: Colors.white.withValues(alpha: 0.7), size: 28),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF86EFAC),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF86EFAC).withValues(alpha: 0.8), blurRadius: 8)
                  ])),
          const SizedBox(width: 8),
          Text('AFRICAN AGRICULTURAL COMMERCE',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: Colors.white.withValues(alpha: 0.85))),
        ],
      ),
    );
  }

  Widget _frostedPill({required Widget child, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.34)),
        ),
        child: child,
      ),
    );
  }

  // ----- INTRO -----
  Widget _introSection() {
    return Container(
      color: AppColors.cream,
      padding: const EdgeInsets.fromLTRB(22, 64, 22, 56),
      child: Column(
        children: [
          _sectionHead(
            'WHAT IS AGRICORE',
            'Everything your farm business needs, in one place',
            'Manage, grow, and scale your agricultural operation with a single connected platform — no spreadsheets, no scattered tools.',
          ),
          const SizedBox(height: 28),
          _introCard(Icons.home_outlined, const Color(0xFFE7F4EC), const Color(0xFF0F7A4B),
              'Farm Management',
              'Organise unlimited farms, track produce, monitor inventory, and keep every operation in view.'),
          const SizedBox(height: 14),
          _introCard(Icons.storefront_outlined, const Color(0xFFF7EED6), const Color(0xFFA9791D),
              'Digital Marketplace',
              'Buy and sell with transparent pricing, secure escrow payments, and verified buyers and sellers.'),
          const SizedBox(height: 14),
          _introCard(Icons.groups_outlined, const Color(0xFFF6E6DF), const Color(0xFFB15A36),
              'Professional Network',
              'Connect with skilled professionals for logistics, processing, quality control, and expert advice.'),
        ],
      ),
    );
  }

  Widget _introCard(IconData icon, Color bg, Color fg, String title, String body) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line),
        boxShadow: [BoxShadow(color: const Color(0x14142819), blurRadius: 30, offset: const Offset(0, 12))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(17)),
            child: Icon(icon, color: fg, size: 28),
          ),
          const SizedBox(height: 16),
          Text(title,
              style: const TextStyle(
                  fontFamily: 'Fraunces',
                  fontWeight: FontWeight.w700,
                  fontSize: 21,
                  color: AppColors.inkWarm)),
          const SizedBox(height: 7),
          Text(body,
              style: const TextStyle(
                  fontFamily: 'Inter', fontSize: 14.5, height: 1.55, color: AppColors.slate600)),
        ],
      ),
    );
  }

  // ----- FEATURES -----
  Widget _featuresSection() {
    final feats = <_Feat>[
      _Feat(Icons.home_outlined, 'green', 'Multi-Farm Management',
          'Create unlimited farms and manage produce individually, with full control over inventory and sales.'),
      _Feat(Icons.sell_outlined, 'gold', 'Dynamic Offers & Bids',
          'List produce, receive buyer offers, negotiate transparently, and close deals in real time.'),
      _Feat(Icons.storefront_outlined, 'clay', 'Your Digital Store',
          'Build an online storefront, link it to your farms, and transfer produce to your catalog seamlessly.'),
      _Feat(Icons.tune, 'sage', 'Store Management',
          'Control products, track performance, manage orders and payments, and respond to reviews.'),
      _Feat(Icons.shopping_cart_outlined, 'amber', 'Buy Agricultural Products',
          'Browse seeds, fertilisers, equipment, and livestock from verified sellers across the network.'),
      _Feat(Icons.groups_outlined, 'teal', 'Connect with Professionals',
          'Network with experts across veterinary, transport, labour, and consulting services.'),
      _Feat(Icons.work_outline, 'plum', 'Find Work Opportunities',
          'Build a professional profile, showcase skills, apply for jobs, and grow your career.'),
      _Feat(Icons.chat_bubble_outline, 'sky', 'Real-Time Chat',
          'Message buyers, sellers, professionals, and team members through integrated live chat.'),
      _Feat(Icons.show_chart, 'rose', 'Analytics & Insights',
          'Track revenue, orders, and conversion, and spot trends to make data-driven decisions.'),
    ];
    return Container(
      key: _featuresKey,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(22, 60, 22, 56),
      child: Column(
        children: [
          _sectionHead('POWERFUL FEATURES', 'Tools that make farming easier and more profitable',
              'A comprehensive toolkit designed for every step of your agricultural journey.'),
          const SizedBox(height: 26),
          ...feats.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _featCard(f),
              )),
        ],
      ),
    );
  }

  Widget _featCard(_Feat f) {
    final c = _chip(f.color);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(14)),
            child: Icon(f.icon, color: c[1], size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.title,
                    style: const TextStyle(
                        fontFamily: 'Fraunces',
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        color: AppColors.inkWarm)),
                const SizedBox(height: 4),
                Text(f.body,
                    style: const TextStyle(
                        fontFamily: 'Inter', fontSize: 13.5, height: 1.5, color: AppColors.slate600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Color> _chip(String k) {
    switch (k) {
      case 'green': return const [Color(0xFFE7F4EC), Color(0xFF0F7A4B)];
      case 'gold': return const [Color(0xFFF7EED6), Color(0xFFA9791D)];
      case 'clay': return const [Color(0xFFF6E6DF), Color(0xFFB15A36)];
      case 'sage': return const [Color(0xFFEEF2E2), Color(0xFF5C7A2E)];
      case 'amber': return const [Color(0xFFFDECD2), Color(0xFFB45309)];
      case 'teal': return const [Color(0xFFD9F2EE), Color(0xFF0F766E)];
      case 'plum': return const [Color(0xFFEFE7F4), Color(0xFF7C4FA0)];
      case 'sky': return const [Color(0xFFE4EEF6), Color(0xFF2F6F9E)];
      case 'rose': return const [Color(0xFFFBE7EE), Color(0xFFB13A63)];
      default: return const [Color(0xFFE7F4EC), Color(0xFF0F7A4B)];
    }
  }

  // ----- STEPS -----
  Widget _stepsSection() {
    final steps = <_Step>[
      _Step('1', 'Create Account', 'Sign up, verify your email, and choose your role.',
          ['Email verification', 'Choose your role', 'Set up profile']),
      _Step('2', 'Register Farms', 'Add your farms and list available produce.',
          ['Add farm details', 'List your produce', 'Upload images']),
      _Step('3', 'Create Store', 'Build your storefront and link your farms.',
          ['Set store branding', 'Configure pricing', 'Link verified farms']),
      _Step('4', 'Manage & Grow', 'Process orders with AI-powered insights.',
          ['AI recommendations', 'Real-time inventory', 'Sales analytics']),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 60, 22, 56),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            colors: [Color(0xFFF3EFE4), Color(0xFFEEF5EE)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter),
      ),
      child: Column(
        children: [
          _sectionHead('HOW IT WORKS', 'Up and running in four simple steps',
              'Follow these steps to unlock the full potential of smart farming with Agricore.'),
          const SizedBox(height: 26),
          ...steps.map((s) => Padding(padding: const EdgeInsets.only(bottom: 14), child: _stepCard(s))),
        ],
      ),
    );
  }

  Widget _stepCard(_Step s) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
        boxShadow: [BoxShadow(color: const Color(0x14142819), blurRadius: 30, offset: const Offset(0, 12))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(gradient: AppColors.emeraldGrad, shape: BoxShape.circle),
                child: Text(s.no,
                    style: const TextStyle(
                        fontFamily: 'Fraunces',
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                        color: Colors.white)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.title,
                        style: const TextStyle(
                            fontFamily: 'Fraunces',
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color: AppColors.inkWarm)),
                    const SizedBox(height: 3),
                    Text(s.lead,
                        style: const TextStyle(
                            fontFamily: 'Inter', fontSize: 13.5, height: 1.45, color: AppColors.slate600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...s.points.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check, size: 16, color: AppColors.g600),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(p,
                          style: const TextStyle(
                              fontFamily: 'Inter', fontSize: 13.5, color: AppColors.slate700)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ----- CTA BAND -----
  Widget _ctaBand() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 64, 24, 64),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            colors: [Color(0xFF0C6B46), Color(0xFF065F3C), Color(0xFF064E3B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
      ),
      child: Column(
        children: [
          const Text('Ready to transform your farming?',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontWeight: FontWeight.w900,
                  fontSize: 30,
                  height: 1.1,
                  color: Colors.white)),
          const SizedBox(height: 14),
          Text(
            'Join thousands of farmers, sellers, and agricultural professionals already growing their business with Agricore.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Inter', fontSize: 15, height: 1.6, color: Colors.white.withValues(alpha: 0.92)),
          ),
          const SizedBox(height: 26),
          PillButton(
              label: 'Get started free',
              ghost: true,
              trailingIcon: Icons.arrow_forward,
              onPressed: _go),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.verified_user_outlined, size: 15, color: Color(0xFF86EFAC)),
              const SizedBox(width: 7),
              Flexible(
                child: Text('No credit card required · Free forever for basic features',
                    style: TextStyle(
                        fontFamily: 'Inter', fontSize: 12.5, color: Colors.white.withValues(alpha: 0.82))),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ----- FOOTER -----
  Widget _footer() {
    return Container(
      width: double.infinity,
      color: AppColors.footerBg,
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 36),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.green.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF6EE7B7).withValues(alpha: 0.25)),
            ),
            child: const Icon(Icons.eco_rounded, color: Color(0xFF6EE7B7), size: 28),
          ),
          const SizedBox(height: 14),
          const Text('Agricore Solutions',
              style: TextStyle(
                  fontFamily: 'Fraunces', fontWeight: FontWeight.w700, fontSize: 22, color: Colors.white)),
          const SizedBox(height: 6),
          const Text('Smart farming for the modern world',
              style: TextStyle(fontFamily: 'Inter', fontSize: 13.5, color: Color(0xFF8FA79A))),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              _SocialDot(Icons.facebook),
              SizedBox(width: 10),
              _SocialDot(Icons.alternate_email),
              SizedBox(width: 10),
              _SocialDot(Icons.camera_alt_outlined),
              SizedBox(width: 10),
              _SocialDot(Icons.business_center_outlined),
            ],
          ),
          const SizedBox(height: 22),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.07)),
          const SizedBox(height: 16),
          const Text('© 2026 Agricore Solutions. All rights reserved.',
              style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: Color(0xFF6F877B))),
        ],
      ),
    );
  }

  Widget _sectionHead(String eyebrow, String title, String body) {
    return Column(
      children: [
        Text(eyebrow,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 1.6,
                color: AppColors.g600)),
        const SizedBox(height: 10),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontFamily: 'Fraunces',
                fontWeight: FontWeight.w900,
                fontSize: 27,
                height: 1.12,
                color: AppColors.inkWarm)),
        const SizedBox(height: 10),
        Text(body,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontFamily: 'Inter', fontSize: 14.5, height: 1.6, color: AppColors.slate600)),
      ],
    );
  }
}

class _Feat {
  final IconData icon;
  final String color;
  final String title;
  final String body;
  _Feat(this.icon, this.color, this.title, this.body);
}

class _Step {
  final String no;
  final String title;
  final String lead;
  final List<String> points;
  _Step(this.no, this.title, this.lead, this.points);
}

class _SocialDot extends StatelessWidget {
  final IconData icon;
  const _SocialDot(this.icon);
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: const Icon(Icons.circle, size: 0),
    );
  }
}
