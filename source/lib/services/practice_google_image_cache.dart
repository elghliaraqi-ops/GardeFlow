import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-device persistent cache of Google/SerpApi search METADATA only.
/// No image bytes or URLs are stored in Supabase DB or Storage.
/// Survives web refresh/restarts and revisits of previously generated cases.
class PracticeGoogleImageCache {
  static const int maxPerDeviceMonth = 240;
  static const Duration positiveTtl = Duration(days: 30);
  static const Duration negativeTtl = Duration(days: 3);

  static String scope(String userId, String key) =>
      sha256.convert(utf8.encode(userId+'|'+key)).toString();
  static String cacheKey(String userId, String googleKey) =>
      'practice_google_cache_v1_'+scope(userId,googleKey);
  static String counterKey(String userId, DateTime now) =>
      'practice_google_count_v1_'+scope(userId,now.year.toString()+'-'+now.month.toString());

  static bool fresh(DateTime now, int savedAtMs, bool hasResults) {
    if (savedAtMs <= 0) return false;
    final diff=now.difference(DateTime.fromMillisecondsSinceEpoch(savedAtMs));
    return !diff.isNegative && diff < (hasResults?positiveTtl:negativeTtl);
  }

  static Future<List<Map<String,dynamic>>?> read({
    required String userId, required String googleKey,
  }) async {
    if (userId.isEmpty || googleKey.isEmpty) return null;
    final prefs=await SharedPreferences.getInstance();
    final raw=prefs.getString(cacheKey(userId,googleKey));
    if (raw==null) return null;
    try {
      final decoded=jsonDecode(raw);
      if(decoded is! Map) return null;
      final data=decoded['images'];
      if(data is! List) return null;
      final results=data.whereType<Map>()
        .map((v)=>Map<String,dynamic>.from(v)).take(8).toList();
      if(!fresh(DateTime.now(),(decoded['saved_at'] as num?)?.toInt()??0,
          results.isNotEmpty))return null;
      return results;
    }catch(_){return null;}
  }

  static Future<void> write({
    required String userId,required String googleKey,
    required List<Map<String,dynamic>> images,
  }) async {
    if(userId.isEmpty||googleKey.isEmpty)return;
    final prefs=await SharedPreferences.getInstance();
    // Only remote URL metadata on the DEVICE; never downloaded image bytes.
    final value=jsonEncode({
      'saved_at':DateTime.now().millisecondsSinceEpoch,
      'images':images.take(8).toList(),
    });
    if(!await prefs.setString(cacheKey(userId,googleKey),value)){
      throw StateError('Cannot save persistent Google cache');
    }
  }

  static Future<int> localCount(String userId)async {
    if(userId.isEmpty)return 0;
    final prefs=await SharedPreferences.getInstance();
    return prefs.getInt(counterKey(userId,DateTime.now()))??0;
  }

  static Future<void> countAttempt(String userId)async{
    final prefs=await SharedPreferences.getInstance();
    final key=counterKey(userId,DateTime.now());
    final value=(prefs.getInt(key)??0)+1;
    if(!await prefs.setInt(key,value)){
      throw StateError('Cannot update local Google search counter');
    }
  }
}
