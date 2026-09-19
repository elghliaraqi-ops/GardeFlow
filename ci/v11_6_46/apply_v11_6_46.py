from pathlib import Path

EXPECTED = "version: 11.6.45+205"
TARGET = "version: 11.6.46+206"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.46: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

news = Path("lib/screens/daily_news_section.dart")
s = news.read_text()

# Horizontal feed: larger card + much larger square media preview.
old = """              SizedBox(
                height: 256,
                child: ListView.separated("""
new = """              SizedBox(
                height: 430,
                child: ListView.separated("""
if old not in s:
    raise SystemExit("V11.6.46: horizontal news list height anchor missing")
s = s.replace(old, new, 1)

old = """    return SizedBox(
      width: 238,"""
new = """    return SizedBox(
      width: 286,"""
if old not in s:
    raise SystemExit("V11.6.46: horizontal news card width anchor missing")
s = s.replace(old, new, 1)

old = """                  SizedBox(
                    height: 126,
                    width: double.infinity,
                    child: imageUrl == null || imageUrl.isEmpty"""
new = """                  SizedBox(
                    height: 286,
                    width: double.infinity,
                    child: imageUrl == null || imageUrl.isEmpty"""
if old not in s:
    raise SystemExit("V11.6.46: horizontal media size anchor missing")
s = s.replace(old, new, 1)

# Show the full media instead of cropping it.
old = """                        : Image.network(
                            imageUrl,
                            fit: BoxFit.cover,"""
new = """                        : Container(
                            color: AppColors.paperAlt,
                            alignment: Alignment.center,
                            child: Image.network(
                              imageUrl,
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.contain,"""
if old not in s:
    raise SystemExit("V11.6.46: horizontal Image.network anchor missing")
s = s.replace(old, new, 1)

old = """                            errorBuilder: (_, __, ___) => Container(
                              color: AppColors.brandSoft,
                              child: const Icon(
                                Icons.image_not_supported_outlined,
                                color: AppColors.brand,
                              ),
                            ),
                          ),"""
new = """                              errorBuilder: (_, __, ___) => Container(
                                color: AppColors.brandSoft,
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.image_not_supported_outlined,
                                  color: AppColors.brand,
                                ),
                              ),
                            ),
                          ),"""
if old not in s:
    raise SystemExit("V11.6.46: horizontal Image.network closing anchor missing")
s = s.replace(old, new, 1)

# Vertical article cards: full-width square preview, no crop.
old = """                if (imageUrl != null && imageUrl.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    height: 190,
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,"""
new = """                if (imageUrl != null && imageUrl.isNotEmpty)
                  AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      color: AppColors.paperAlt,
                      alignment: Alignment.center,
                      child: Image.network(
                        imageUrl,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.contain,"""
if old not in s:
    raise SystemExit("V11.6.46: vertical media anchor missing")
s = s.replace(old, new, 1)

old = """                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.brandSoft,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.image_not_supported_outlined,
                          color: AppColors.brand,
                        ),
                      ),
                    ),
                  ),"""
new = """                        errorBuilder: (_, __, ___) => Container(
                          color: AppColors.brandSoft,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.image_not_supported_outlined,
                            color: AppColors.brand,
                          ),
                        ),
                      ),
                    ),
                  ),"""
if old not in s:
    raise SystemExit("V11.6.46: vertical Image.network closing anchor missing")
s = s.replace(old, new, 1)

news.write_text(s)

print("GardeFlow V11.6.46: enlarged horizontal/vertical news media and preserved full image/video previews")
