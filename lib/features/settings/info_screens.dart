import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/responsive/responsive.dart';
import '../../widgets/app_toast.dart';

const _supportEmail = 'support@agricore.app';

/// Shared scaffold + section helpers for the simple info screens below so they
/// match the Settings visual language (cream bg, Fraunces title, white cards).
PreferredSizeWidget _infoAppBar(String title) => AppBar(
      backgroundColor: AppColors.cream,
      foregroundColor: AppColors.inkWarm,
      elevation: 0,
      title: Text(title,
          style: const TextStyle(
              fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 22)),
    );

Widget _card({required Widget child}) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.line)),
      child: child,
    );

Widget _heading(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(t,
          style: const TextStyle(
              fontFamily: 'Fraunces',
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: AppColors.inkWarm)),
    );

Widget _para(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(t,
          style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 13.5,
              height: 1.5,
              color: AppColors.slate700)),
    );

Future<void> _launchUri(BuildContext context, Uri uri) async {
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    showToast(context, 'Could not open ${uri.scheme} link.');
  }
}

/// ---- Privacy ----
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mailto = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: {'subject': 'Delete my AgriCore account'},
    );
    return Scaffold(
      backgroundColor: context.palette.surface,
      appBar: _infoAppBar('Privacy'),
      body: MaxWidthBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _heading('Data we collect'),
                  _para(
                      'AgriCore collects the information you provide when you create an account '
                      '(name, email and phone number), and the records you add such as farms, '
                      'crops, livestock, store listings, orders and payout details.'),
                  _para(
                      'We also process transaction and escrow data needed to complete trades, '
                      'and basic device/usage diagnostics to keep the app stable and secure.'),
                  _heading('How we use it'),
                  _para(
                      'Your data is used to run your account, match buyers and sellers, settle '
                      'payments and payouts, send the notifications you enable, and improve the '
                      'service. We do not sell your personal information.'),
                  _para(
                      'You can request a copy of your data or ask us to delete your account at '
                      'any time using the option below.'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: () => _launchUri(context, mailto),
              borderRadius: BorderRadius.circular(20),
              child: _card(
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                          color: const Color(0xFFFDE7E7),
                          borderRadius: BorderRadius.circular(11)),
                      child: const Icon(Icons.delete_outline_rounded,
                          color: Color(0xFFC0392B), size: 19),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Contact us to delete your account',
                              style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14.5,
                                  color: context.palette.ink)),
                          Text(_supportEmail,
                              style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 12,
                                  color: context.palette.muted)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: context.palette.muted),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---- Help center ----
class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  static const _faqs = <(String, String)>[
    (
      'How do I add a farm or store?',
      'Open the Farms or Stores tab and tap the add button. Fill in the details '
          'and save — your records sync to your account automatically.'
    ),
    (
      'How does escrow work?',
      'When a buyer pays, funds are held in escrow. They are released to the '
          'seller once the order is confirmed as delivered, protecting both sides.'
    ),
    (
      'When do I receive payouts?',
      'Payouts are sent to the bank or mobile-money account set in Payout details '
          'once an order is completed and the escrow is released.'
    ),
    (
      'How do I change my language or currency?',
      'Go to Settings → Preferences and pick your language or currency. The change '
          'applies across the whole app immediately.'
    ),
    (
      'I forgot my password.',
      'Use the change-password option in Settings → Account & security, or contact '
          'support if you cannot sign in.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final mailto = Uri(scheme: 'mailto', path: _supportEmail);
    return Scaffold(
      backgroundColor: context.palette.surface,
      appBar: _infoAppBar('Help center'),
      body: MaxWidthBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _heading('Frequently asked'),
                  for (final f in _faqs)
                    Theme(
                      data: Theme.of(context)
                          .copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(bottom: 12),
                        title: Text(f.$1,
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: context.palette.ink)),
                        children: [_para(f.$2)],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: () => _launchUri(context, mailto),
              borderRadius: BorderRadius.circular(20),
              child: _card(
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                          color: const Color(0xFFE4EEF6),
                          borderRadius: BorderRadius.circular(11)),
                      child: const Icon(Icons.mail_outline_rounded,
                          color: Color(0xFF2F6F9E), size: 19),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Still need help? Email support',
                              style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14.5,
                                  color: context.palette.ink)),
                          Text(_supportEmail,
                              style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 12,
                                  color: context.palette.muted)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: context.palette.muted),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---- Terms & policies ----
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.surface,
      appBar: _infoAppBar('Terms & policies'),
      body: MaxWidthBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _heading('Terms of Service'),
                  _para(
                      'By using AgriCore you agree to use the platform lawfully and to provide '
                      'accurate information about yourself and the goods you list or buy.'),
                  _para(
                      'AgriCore facilitates trade between farmers, buyers and transporters and '
                      'provides escrow to help secure payments. You are responsible for the '
                      'quality of goods you sell and for fulfilling orders you accept.'),
                  _heading('Payments & escrow'),
                  _para(
                      'Funds held in escrow are released according to the order lifecycle. Fees '
                      'and payout timelines are shown at the point of transaction.'),
                  _heading('Privacy Policy'),
                  _para(
                      'We process your data to operate the service as described in the Privacy '
                      'section of Settings. We apply reasonable safeguards to protect it and do '
                      'not sell your personal information.'),
                  _heading('Changes'),
                  _para(
                      'These terms may be updated from time to time. Continued use of AgriCore '
                      'after an update means you accept the revised terms.'),
                  const SizedBox(height: 4),
                  Text('Last updated: June 2026',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: context.palette.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
