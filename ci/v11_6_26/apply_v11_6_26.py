from pathlib import Path

EXPECTED = "version: 11.6.25+185"
TARGET = "version: 11.6.26+186"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.26: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

brand = Path("lib/widgets/brand_identity.dart")
b = brand.read_text()

b = b.replace(
"""class GardeFlowBrandBlock extends StatelessWidget {
  final bool compact;
  final bool light;

  const GardeFlowBrandBlock({
    super.key,
    this.compact = false,
    this.light = false,
  });""",
"""class GardeFlowBrandBlock extends StatelessWidget {
  final bool compact;
  final bool light;
  final Color? subtitleColor;

  const GardeFlowBrandBlock({
    super.key,
    this.compact = false,
    this.light = false,
    this.subtitleColor,
  });""",
1,
)

b = b.replace(
"""    final secondary = light ? Colors.white.withOpacity(0.88) : AppColors.inkSoft;""",
"""    final secondary = light ? Colors.white.withOpacity(0.88) : AppColors.inkSoft;
    final resolvedSubtitleColor = subtitleColor ?? secondary;""",
1,
)

old_subtitle = """            color: secondary,
          ),
        ),
        SizedBox(height: compact ? 9 : 12),"""
new_subtitle = """            color: resolvedSubtitleColor,
          ),
        ),
        SizedBox(height: compact ? 9 : 12),"""
if old_subtitle not in b:
    raise SystemExit("V11.6.26: brand subtitle color anchor missing")
b = b.replace(old_subtitle, new_subtitle, 1)
brand.write_text(b)

auth = Path("lib/screens/auth_screen.dart")
a = auth.read_text()

def replace_method(source: str, signature: str, replacement: str) -> str:
    start = source.find(signature)
    if start < 0:
        raise SystemExit(f"V11.6.26: method not found: {signature}")
    brace = source.find("{", start)
    if brace < 0:
        raise SystemExit(f"V11.6.26: opening brace missing: {signature}")
    depth = 0
    end = None
    for i in range(brace, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                end = i + 1
                break
    if end is None:
        raise SystemExit(f"V11.6.26: closing brace missing: {signature}")
    return source[:start] + replacement.rstrip() + source[end:]

build_method = r"""  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/branding/login_urgences.jpg',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.high,
          ),
          AnimatedBuilder(
            animation: _entranceController,
            builder: (context, child) {
              final t =
                  Curves.easeInOutCubic.transform(_entranceController.value);
              final sigma = 8.5 * t;
              return BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                child: Container(
                  color: Colors.white.withOpacity(0.05 + (0.10 * t)),
                ),
              );
            },
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withOpacity(0.68),
                  Colors.white.withOpacity(0.34),
                  Colors.white.withOpacity(0.54),
                  const Color(0xFFEAF7EF).withOpacity(0.78),
                ],
                stops: const [0, 0.28, 0.70, 1],
              ),
            ),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: _contentOpacity,
              child: SlideTransition(
                position: _contentSlide,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (_showRegister) {
                      return Center(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding:
                              const EdgeInsets.fromLTRB(18, 16, 18, 20),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 460),
                            child: _buildAuthContent(
                              register: true,
                              compactLogin: false,
                            ),
                          ),
                        ),
                      );
                    }

                    final availableWidth = constraints.maxWidth - 28;
                    final contentWidth =
                        availableWidth > 440 ? 440.0 : availableWidth;

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: contentWidth,
                            child: _buildAuthContent(
                              register: false,
                              compactLogin: true,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthContent({
    required bool register,
    required bool compactLogin,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GardeFlowBrandBlock(
          compact: true,
          subtitleColor: _loginGreen,
        ),
        SizedBox(height: compactLogin ? 10 : 18),
        if (_info != null) ...[
          _Banner(
            text: _info!,
            background: const Color(0xFFE7F6ED),
            foreground: _loginGreenDark,
            icon: Icons.check_circle_rounded,
          ),
          const SizedBox(height: 7),
        ],
        if (_error != null) ...[
          _Banner(
            text: _error!,
            background: const Color(0xFFFFE7E3),
            foreground: AppColors.danger,
            icon: Icons.error_rounded,
          ),
          const SizedBox(height: 7),
        ],
        _GlassCard(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: register ? _buildRegisterForm() : _buildLoginForm(),
          ),
        ),
        SizedBox(height: compactLogin ? 10 : 18),
        const InstitutionalLogosPanel(compact: true),
        SizedBox(height: compactLogin ? 8 : 12),
        RichText(
          textAlign: TextAlign.center,
          text: const TextSpan(
            style: TextStyle(
              fontFamily: 'SpaceGrotesk',
              fontSize: 11.5,
              height: 1.2,
              fontWeight: FontWeight.w800,
            ),
            children: [
              TextSpan(
                text: 'Le planning de garde pour garder le ',
                style: TextStyle(color: _loginGreenDark),
              ),
              TextSpan(
                text: 'flow',
                style: TextStyle(color: AppColors.danger),
              ),
            ],
          ),
        ),
        SizedBox(height: compactLogin ? 7 : 12),
        const Text(
          'AU SERVICE DES SOIGNANTS\nAU SERVICE DES PATIENTS',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 9,
            height: 1.35,
            letterSpacing: 2.2,
            color: _loginGreenDark,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Container(
          width: 42,
          height: 2,
          decoration: BoxDecoration(
            color: _loginGreen,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ],
    );
  }
"""

a = replace_method(a, "  @override\n  Widget build(BuildContext context)", build_method)

# Compact the login-only form slightly so it fits on one page without scrolling.
a = a.replace(
"""            fontSize: 29,""",
"""            fontSize: 27,""",
1,
)
a = a.replace(
"""        const SizedBox(height: 22),
        TextField(
          controller: _loginPhoneCtrl,""",
"""        const SizedBox(height: 15),
        TextField(
          controller: _loginPhoneCtrl,""",
1,
)
a = a.replace(
"""        const SizedBox(height: 18),
        const _OrDivider(),
        const SizedBox(height: 16),""",
"""        const SizedBox(height: 12),
        const _OrDivider(),
        const SizedBox(height: 11),""",
1,
)
a = a.replace(
"""          height: 52,
          child: OutlinedButton(""",
"""          height: 48,
          child: OutlinedButton(""",
1,
)

auth.write_text(a)

print("GardeFlow V11.6.26: login sans défilement + slogan vert + tagline flow")
