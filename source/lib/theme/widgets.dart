import 'package:flutter/material.dart';
import 'app_theme.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final List<BoxShadow>? shadow;
  final Border? border;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.radius = AppRadius.lg,
    this.color,
    this.shadow,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.card,
        borderRadius: BorderRadius.circular(radius),
        border: border ?? Border.all(color: AppColors.line),
        boxShadow: shadow ?? AppShadow.low,
      ),
      child: child,
    );
  }
}

class SoftIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? background;
  final Color? foreground;
  final String? tooltip;

  const SoftIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 42,
    this.background,
    this.foreground,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background ?? AppColors.brandSoft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Color(0xFFD7E7F8)),
          ),
          child: Icon(icon, size: size * 0.48, color: foreground ?? AppColors.brand),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class Pill extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? background;
  final Color? foreground;
  final double fontSize;

  const Pill({
    super.key,
    required this.text,
    this.icon,
    this.background,
    this.foreground,
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background ?? AppColors.brandSoft,
        borderRadius: AppRadius.pillR,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 3, color: foreground),
            SizedBox(width: 5),
          ],
          Text(text, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, color: foreground)),
        ],
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Row(
        children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

PreferredSizeWidget appBarOf(BuildContext context, String title, {List<Widget>? actions}) {
  return AppBar(
    title: Text(title),
    actions: actions,
    bottom: PreferredSize(
      preferredSize: Size.fromHeight(1),
      child: Divider(height: 1, color: AppColors.line),
    ),
  );
}

class GardeFlowTitle extends StatelessWidget {
  final String section;
  const GardeFlowTitle(this.section, {super.key});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GardeFlowLogo(size: 34),
          SizedBox(width: 10),
          Flexible(
            child: Text(
              section,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
            ),
          ),
        ],
      );
}

class GardeFlowLogo extends StatelessWidget {
  final double size;
  const GardeFlowLogo({super.key, this.size = 44});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.24),
        child: Image.asset(
          'assets/branding/gardeflow_logo.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
          semanticLabel: 'Logo GardeFlow',
        ),
      );
}

class BlueHero extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const BlueHero({super.key, required this.child, this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D74E6), AppColors.brandDark],
          ),
          borderRadius: AppRadius.xlR,
          boxShadow: AppShadow.mid,
        ),
        child: child,
      );
}
