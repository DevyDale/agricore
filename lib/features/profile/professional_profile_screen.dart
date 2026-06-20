import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/dio_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/fresh_kit.dart';
import '../../widgets/state_views.dart';
import '../../core/i18n/locale_provider.dart';

const _profilePath = '/professional-profiles/me/';
const _updatePath = '/professional-profiles/update_me/';

/// Editor for the user's published workforce profile — the "My professional
/// profile" they expose so farms and employers can hire them. Loads the
/// current profile (or starts blank if none exists yet) and saves the editable
/// text / number / list / choice fields back via `update_me`.
///
/// Backend field names mirror [ProfessionalProfileCreateUpdateSerializer]:
///   bio, phone, location, specialty, years_experience, hourly_rate,
///   availability, education, work_experience, skills, certifications,
///   languages, notable_projects, linkedin_url, portfolio_url, response_time.
/// File fields (profile_image, resume) are intentionally skipped here.
class ProfessionalProfileScreen extends StatefulWidget {
  const ProfessionalProfileScreen({super.key});

  @override
  State<ProfessionalProfileScreen> createState() =>
      _ProfessionalProfileScreenState();
}

class _ProfessionalProfileScreenState extends State<ProfessionalProfileScreen> {
  // Model SPECIALTY_CHOICES (value, label).
  static const _specialties = <(String, String)>[
    ('agronomist', 'Agronomist'),
    ('veterinarian', 'Veterinarian'),
    ('mechanic', 'Mechanic'),
    ('chemist', 'Chemist'),
    ('farm_manager', 'Farm Manager'),
    ('agricultural_engineer', 'Agricultural Engineer'),
    ('soil_scientist', 'Soil Scientist'),
    ('crop_consultant', 'Crop Consultant'),
    ('pest_control', 'Pest Control Specialist'),
    ('livestock_handler', 'Livestock Handler'),
    ('irrigation_specialist', 'Irrigation Specialist'),
    ('agricultural_economist', 'Agricultural Economist'),
    ('horticulturist', 'Horticulturist'),
    ('agricultural_technician', 'Agricultural Technician'),
    ('food_safety', 'Food Safety Specialist'),
    ('data_analyst', 'Agricultural Data Analyst'),
    ('farm_laborer', 'Farm Laborer'),
    ('equipment_operator', 'Equipment Operator'),
    ('harvester', 'Harvester'),
    ('planting_specialist', 'Planting Specialist'),
  ];

  // Model AVAILABILITY_CHOICES (value, label).
  static const _availabilities = <(String, String)>[
    ('full_time', 'Full-Time'),
    ('part_time', 'Part-Time'),
    ('contract', 'Contract'),
    ('seasonal', 'Seasonal'),
    ('available', 'Available Now'),
    ('not_available', 'Not Available'),
  ];

  bool _loading = true;
  bool _saving = false;
  String? _error;

  // Text / number controllers.
  final _bio = TextEditingController();
  final _phone = TextEditingController();
  final _location = TextEditingController();
  final _yearsExperience = TextEditingController();
  final _hourlyRate = TextEditingController();
  final _education = TextEditingController();
  final _workExperience = TextEditingController();
  final _skills = TextEditingController();
  final _certifications = TextEditingController();
  final _languages = TextEditingController();
  final _notableProjects = TextEditingController();
  final _linkedinUrl = TextEditingController();
  final _portfolioUrl = TextEditingController();
  final _responseTime = TextEditingController();

  // Single-select choice fields.
  String? _specialty;
  String _availability = 'available';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _bio.dispose();
    _phone.dispose();
    _location.dispose();
    _yearsExperience.dispose();
    _hourlyRate.dispose();
    _education.dispose();
    _workExperience.dispose();
    _skills.dispose();
    _certifications.dispose();
    _languages.dispose();
    _notableProjects.dispose();
    _linkedinUrl.dispose();
    _portfolioUrl.dispose();
    _responseTime.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = context.read<DioClient>().dio;
      final res = await dio.get(_profilePath);
      if (!mounted) return;
      final data = res.data;
      if (data is Map) _prefill(data.cast<String, dynamic>());
      setState(() => _loading = false);
    } on DioException catch (e) {
      if (!mounted) return;
      // No profile yet → start with a blank form, not an error.
      if (e.response?.statusCode == 404) {
        setState(() => _loading = false);
        return;
      }
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  void _prefill(Map<String, dynamic> j) {
    _bio.text = pickString(j, ['bio']) ?? '';
    _phone.text = pickString(j, ['phone']) ?? '';
    _location.text = pickString(j, ['location']) ?? '';
    final yrs = pickNum(j, ['years_experience']);
    _yearsExperience.text = yrs == null ? '' : yrs.toInt().toString();
    final rate = pickNum(j, ['hourly_rate']);
    _hourlyRate.text = rate == null ? '' : money(rate, decimals: 2);
    _education.text = pickString(j, ['education']) ?? '';
    _workExperience.text = pickString(j, ['work_experience']) ?? '';
    _skills.text = _joinList(j['skills']);
    _certifications.text = _joinList(j['certifications']);
    _languages.text = _joinList(j['languages']);
    _notableProjects.text = pickString(j, ['notable_projects']) ?? '';
    _linkedinUrl.text = pickString(j, ['linkedin_url']) ?? '';
    _portfolioUrl.text = pickString(j, ['portfolio_url']) ?? '';
    _responseTime.text = pickString(j, ['response_time']) ?? '';
    _specialty = pickString(j, ['specialty']);
    _availability = pickString(j, ['availability']) ?? 'available';
  }

  String _joinList(dynamic v) {
    if (v is List) {
      return v.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).join(', ');
    }
    return v is String ? v : '';
  }

  List<String> _splitList(String s) => s
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  Future<void> _save() async {
    if (_saving) return;

    // Required (non-blank) model fields.
    if (_location.text.trim().isEmpty) {
      showToast(context, 'Add your location.', success: false);
      return;
    }
    if (_specialty == null || _specialty!.isEmpty) {
      showToast(context, 'Pick your specialty.', success: false);
      return;
    }
    final years = int.tryParse(_yearsExperience.text.trim());
    if (years == null || years < 0) {
      showToast(context, 'Enter your years of experience.', success: false);
      return;
    }
    final rate = num.tryParse(_hourlyRate.text.trim().replaceAll(',', ''));
    if (rate == null || rate < 0) {
      showToast(context, 'Enter a valid hourly rate.', success: false);
      return;
    }

    final body = <String, dynamic>{
      'bio': _bio.text.trim(),
      'phone': _phone.text.trim(),
      'location': _location.text.trim(),
      'specialty': _specialty,
      'years_experience': years,
      'hourly_rate': rate,
      'availability': _availability,
      'education': _education.text.trim(),
      'work_experience': _workExperience.text.trim(),
      'skills': _splitList(_skills.text),
      'certifications': _splitList(_certifications.text),
      'languages': _splitList(_languages.text),
      'notable_projects': _notableProjects.text.trim(),
      'linkedin_url': _linkedinUrl.text.trim(),
      'portfolio_url': _portfolioUrl.text.trim(),
      'response_time': _responseTime.text.trim(),
    };

    setState(() => _saving = true);
    try {
      final dio = context.read<DioClient>().dio;
      await dio.post(_updatePath, data: body);
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, 'Profile saved', success: true);
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, friendlyError(e), success: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Column(
        children: [
          GradientHero(
            title: context.tr('My professional profile'),
            subtitle: context.tr('Get hired on AgriCore'),
            icon: Icons.badge_rounded,
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
          children: [
            FreshSectionHeader(title: context.tr('About you')),
            const SizedBox(height: 12),
            FreshField(
              controller: _bio,
              label: context.tr('Bio'),
              hint: context.tr('A short summary of what you do'),
              lines: 4,
            ),
            const SizedBox(height: 12),
            FreshField(
              controller: _location,
              label: context.tr('Location'),
              hint: context.tr('e.g. Kampala, Uganda'),
            ),
            const SizedBox(height: 12),
            FreshField(
              controller: _phone,
              label: context.tr('Phone'),
              hint: context.tr('e.g. +256772123456'),
            ),
            const SizedBox(height: 22),

            FreshSectionHeader(title: context.tr('Specialty')),
            const SizedBox(height: 12),
            _ChipWrap(
              options: _specialties,
              isSelected: (value) => _specialty == value,
              onTap: (value) => setState(
                  () => _specialty = _specialty == value ? null : value),
            ),
            const SizedBox(height: 22),

            FreshSectionHeader(title: context.tr('Rate & experience')),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: FreshField(
                    controller: _yearsExperience,
                    label: context.tr('Years of experience'),
                    hint: context.tr('e.g. 5'),
                    number: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FreshField(
                    controller: _hourlyRate,
                    label: context.tr('Hourly rate'),
                    hint: context.tr('e.g. 25'),
                    number: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FreshField(
              controller: _responseTime,
              label: context.tr('Typical response time'),
              hint: context.tr('e.g. Within 24 hours'),
            ),
            const SizedBox(height: 22),

            FreshSectionHeader(title: context.tr('Availability')),
            const SizedBox(height: 12),
            _ChipWrap(
              options: _availabilities,
              isSelected: (value) => _availability == value,
              onTap: (value) => setState(() => _availability = value),
            ),
            const SizedBox(height: 22),

            FreshSectionHeader(title: context.tr('Skills & credentials')),
            const SizedBox(height: 12),
            FreshField(
              controller: _skills,
              label: context.tr('Skills (comma separated)'),
              hint: context.tr('e.g. Soil testing, Irrigation, Pest control'),
              lines: 2,
            ),
            const SizedBox(height: 12),
            FreshField(
              controller: _certifications,
              label: context.tr('Certifications (comma separated)'),
              hint: context.tr('e.g. Certified Agronomist, FAO Cert'),
              lines: 2,
            ),
            const SizedBox(height: 12),
            FreshField(
              controller: _languages,
              label: context.tr('Languages (comma separated)'),
              hint: context.tr('e.g. English, Swahili, Luganda'),
              lines: 2,
            ),
            const SizedBox(height: 22),

            FreshSectionHeader(title: context.tr('Background')),
            const SizedBox(height: 12),
            FreshField(
              controller: _education,
              label: context.tr('Education'),
              hint: context.tr('Your educational background'),
              lines: 3,
            ),
            const SizedBox(height: 12),
            FreshField(
              controller: _workExperience,
              label: context.tr('Work experience'),
              hint: context.tr('Detailed work experience'),
              lines: 3,
            ),
            const SizedBox(height: 12),
            FreshField(
              controller: _notableProjects,
              label: context.tr('Notable projects'),
              hint: context.tr('Projects you are proud of'),
              lines: 3,
            ),
            const SizedBox(height: 22),

            FreshSectionHeader(title: context.tr('Links')),
            const SizedBox(height: 12),
            FreshField(
              controller: _linkedinUrl,
              label: context.tr('LinkedIn URL'),
              hint: context.tr('https://linkedin.com/in/you'),
            ),
            const SizedBox(height: 12),
            FreshField(
              controller: _portfolioUrl,
              label: context.tr('Portfolio URL'),
              hint: context.tr('https://your-portfolio.com'),
            ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _SaveBar(saving: _saving, onTap: _save),
        ),
      ],
    );
  }
}

/// Wrap of single-select choice chips that mirror the wallet/fresh_kit pattern:
/// selected = emerald fill with white text, unselected = white with a line border.
class _ChipWrap extends StatelessWidget {
  final List<(String, String)> options;
  final bool Function(String value) isSelected;
  final ValueChanged<String> onTap;
  const _ChipWrap({
    required this.options,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (value, label) in options)
          GestureDetector(
            onTap: () => onTap(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: isSelected(value) ? AppColors.g600 : Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isSelected(value) ? AppColors.g600 : AppColors.line,
                ),
              ),
              child: Text(
                context.tr(label),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: isSelected(value) ? Colors.white : AppColors.slate700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Sticky bottom gradient "Save profile" button.
class _SaveBar extends StatelessWidget {
  final bool saving;
  final VoidCallback onTap;
  const _SaveBar({required this.saving, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
      decoration: const BoxDecoration(
        color: AppColors.cream,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: GestureDetector(
        onTap: saving ? null : onTap,
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: AppColors.emeraldGrad,
            borderRadius: BorderRadius.circular(13),
          ),
          child: saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: Colors.white),
                )
              : Text(
                  context.tr('Save profile'),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontSize: 15,
                  ),
                ),
        ),
      ),
    );
  }
}
