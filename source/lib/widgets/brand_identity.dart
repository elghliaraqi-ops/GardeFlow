import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/widgets.dart';

Color get _brandGreen => AppColors.brand;
const _brandRed = AppColors.cyan;

class GardeFlowBrandBlock extends StatelessWidget {
  final bool compact;
  final bool light;
  final Color? subtitleColor;

  const GardeFlowBrandBlock({
    super.key,
    this.compact = false,
    this.light = false,
    this.subtitleColor,
  });

  @override
  Widget build(BuildContext context) {
    final titleSize = compact ? 34.0 : 46.0;
    final iconSize = compact ? 78.0 : 104.0;
    final secondary = light ? Colors.white.withOpacity(0.88) : AppColors.inkSoft;
    final resolvedSubtitleColor = subtitleColor ?? secondary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.all(compact ? 7 : 9),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(light ? 0.90 : 0.97),
            borderRadius: BorderRadius.circular(compact ? 24 : 30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.09),
                blurRadius: compact ? 18 : 28,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: GardeFlowLogo(size: iconSize),
        ),
        SizedBox(height: compact ? 12 : 18),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                fontFamily: 'SpaceGrotesk',
                fontSize: titleSize,
                height: 1,
                fontWeight: FontWeight.w600,
                letterSpacing: -1.5,
              ),
              children: [
                TextSpan(text: 'Garde', style: TextStyle(color: _brandGreen)),
                TextSpan(text: 'Flow', style: TextStyle(color: _brandRed)),
              ],
            ),
          ),
        ),
        SizedBox(height: compact ? 3 : 5),
        Text(
          'Planning médical intelligent',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: compact ? 14 : 16,
            letterSpacing: compact ? 2.1 : 2.8,
            fontWeight: FontWeight.w500,
            color: resolvedSubtitleColor,
          ),
        ),
        SizedBox(height: compact ? 9 : 12),
        SizedBox(
          width: compact ? 150 : 190,
          child: Row(
            children: [
              Expanded(child: Divider(color: _brandGreen.withOpacity(0.28))),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 7),
                child: Icon(Icons.monitor_heart_outlined, size: compact ? 20 : 23, color: _brandGreen.withOpacity(0.42)),
              ),
              Expanded(child: Divider(color: _brandGreen.withOpacity(0.28))),
            ],
          ),
        ),
        Text(
          'LE PLANNING DE GARDE POUR GARDER LE FLOW',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: compact ? 8.8 : 10.2,
            letterSpacing: compact ? 2.0 : 2.8,
            fontWeight: FontWeight.w600,
            color: secondary.withOpacity(light ? 0.88 : 0.78),
          ),
        ),
      ],
    );
  }
}

class InstitutionalLogosPanel extends StatelessWidget {
  final bool compact;
  final bool showBouskouraOnOwnRow;

  const InstitutionalLogosPanel({
    super.key,
    this.compact = false,
    this.showBouskouraOnOwnRow = false,
  });

  static const _rabat = 'assets/branding/partners/hui_rabat.png';
  static const _cheikh = 'assets/branding/partners/hui_cheikh_khalifa.png';
  static const _bouskoura = 'assets/branding/partners/hui_bouskoura.png';
  static const _amium6 = 'assets/branding/partners/amium6.png';

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.88),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.82)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.055), blurRadius: 18, offset: Offset(0, 8)),
          ],
        ),
        child: Row(
          children: [
            for (final asset in [_rabat, _cheikh, _bouskoura, _amium6]) ...[
              Expanded(child: _LogoAsset(asset: asset, height: 46)),
              if (asset != _amium6)
                Container(width: 1, height: 40, margin: EdgeInsets.symmetric(horizontal: 6), color: AppColors.line.withOpacity(0.75)),
            ],
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.93),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.92)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: const [
              Expanded(child: _LogoAsset(asset: _rabat, height: 76)),
              SizedBox(width: 10),
              SizedBox(height: 68, child: VerticalDivider(width: 1)),
              SizedBox(width: 10),
              Expanded(child: _LogoAsset(asset: _cheikh, height: 76)),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(),
          const SizedBox(height: 8),
          if (showBouskouraOnOwnRow)
            const _LogoAsset(asset: _bouskoura, height: 74)
          else
            Row(
              children: const [
                Expanded(child: _LogoAsset(asset: _bouskoura, height: 70)),
                SizedBox(width: 16),
                Expanded(child: _LogoAsset(asset: _amium6, height: 62)),
              ],
            ),
          if (showBouskouraOnOwnRow) ...[
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
            const _LogoAsset(asset: _amium6, height: 64),
          ],
        ],
      ),
    );
  }
}

class _LogoAsset extends StatelessWidget {
  final String asset;
  final double height;

  const _LogoAsset({required this.asset, required this.height});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}
