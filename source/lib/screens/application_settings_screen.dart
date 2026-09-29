import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../services/doctor_visual_preference.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import '../theme/doctor_visuals.dart';

class ApplicationSettingsScreen extends StatelessWidget {
  const ApplicationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    Widget choice({
      required String label,
      required String subtitle,
      required String value,
      required Color swatch,
    }) {
      return _AppearanceChoice(
        label: label,
        subtitle: subtitle,
        value: value,
        swatch: swatch,
        selected: appState.appearanceTheme == value,
        onTap: () => appState.setAppearanceTheme(value),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: GardeFlowTitle('Réglages de l’application')),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, 34),
        children: [
          SectionLabel('Thème de l’application'),
          AppCard(
            padding: EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.brandSoft,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.palette_rounded,
                        color: AppColors.brand,
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Choisissez l’apparence générale de GardeFlow. Le vert reste le thème par défaut.',
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: AppColors.inkSoft, height: 1.4),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: AppSpace.lg),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final itemWidth = (constraints.maxWidth - 10) / 2;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: itemWidth,
                          child: choice(
                            label: 'Vert',
                            subtitle: 'Par défaut',
                            value: 'green',
                            swatch: const Color(0xFF138A55),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: choice(
                            label: 'Rouge',
                            subtitle: 'Rouge profond',
                            value: 'red',
                            swatch: const Color(0xFFD94A43),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: choice(
                            label: 'Blanc',
                            subtitle: 'Ancien mode clair',
                            value: 'white',
                            swatch: Colors.white,
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: choice(
                            label: 'Noir',
                            subtitle: 'Mode sombre',
                            value: 'black',
                            swatch: const Color(0xFF101311),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SectionLabel('Médecin affiché'),
          AppCard(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.brandSoft,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.person_rounded,
                        color: AppColors.brandBright,
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Choisissez le médecin illustré qui vous représentera dans l’application.',
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: AppColors.inkSoft, height: 1.4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FutureBuilder<void>(
                  future: DoctorVisualPreference.ensureLoaded(),
                  builder: (context, _) => ValueListenableBuilder<String>(
                    valueListenable: DoctorVisualPreference.gender,
                    builder: (context, selectedGender, __) {
                      return Row(
                        children: [
                          Expanded(
                            child: _DoctorVisualChoice(
                              label: 'Femme',
                              gender: 'female',
                              selected: selectedGender == 'female',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _DoctorVisualChoice(
                              label: 'Homme',
                              gender: 'male',
                              selected: selectedGender == 'male',
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 34),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 280,
                  height: 126,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Image.asset(
                    'assets/branding/elghali_signature.webp',
                    width: 260,
                    height: 112,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Elghali Production © 2026',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.inkSoft,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.25,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'Version 12.0.0',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.inkFaint,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
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

class _DoctorVisualChoice extends StatelessWidget {
  final String label;
  final String gender;
  final bool selected;

  const _DoctorVisualChoice({
    required this.label,
    required this.gender,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.brand.withOpacity(0.13) : AppColors.paperAlt,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => DoctorVisualPreference.setGender(gender),
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppColors.brandBright : AppColors.line,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              DoctorAvatar(gender: gender, size: 72),
              const SizedBox(height: 9),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected
                        ? AppColors.brandBright
                        : AppColors.inkFaint,
                    size: 21,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppearanceChoice extends StatelessWidget {
  final String label;
  final String subtitle;
  final String value;
  final Color swatch;
  final bool selected;
  final VoidCallback? onTap;

  const _AppearanceChoice({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.swatch,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selectedBorder = value == 'white' ? AppColors.inkSoft : swatch;

    return Material(
      color: selected ? swatch.withOpacity(0.16) : AppColors.paperAlt,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? selectedBorder : AppColors.line,
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: swatch,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: value == 'white' ? const Color(0xFFCBD6D0) : swatch,
                    width: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  size: 19,
                  color: AppColors.brand,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
