import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:huim6_planning/services/practice_google_image_cache.dart';

void main(){
  setUp(()=>SharedPreferences.setMockInitialValues({}));
  test('same search is reused without another SerpApi request',()async{
    const user='owner-1';
    const key='radiology_scan|rectal cancer t2 mri';
    expect(await PracticeGoogleImageCache.read(userId:user,googleKey:key),isNull);
    await PracticeGoogleImageCache.write(
      userId:user,googleKey:key,
      images:[{'title':'Rectal MRI','thumbnail':'https://cdn.example.org/mri.png'}],
    );
    final cached=await PracticeGoogleImageCache.read(userId:user,googleKey:key);
    expect(cached?.length,1);
    expect(cached?.first['title'],'Rectal MRI');
    expect(await PracticeGoogleImageCache.read(userId:'another-owner',googleKey:key),isNull);
  });
  test('negative results are remembered to avoid repeated paid searches',()async{
    await PracticeGoogleImageCache.write(userId:'owner',googleKey:'a',images:[]);
    final negative=await PracticeGoogleImageCache.read(userId:'owner',googleKey:'a');
    expect(negative,isNotNull);
    expect(negative,isEmpty);
  });
  test('thirty-day positive and three-day negative expiry',(){
    final now=DateTime(2026,10,10);
    final monthAgo=now.subtract(const Duration(days:31));
    expect(PracticeGoogleImageCache.fresh(now,monthAgo.millisecondsSinceEpoch,true),isFalse);
    expect(PracticeGoogleImageCache.fresh(now,now.subtract(const Duration(days:29)).millisecondsSinceEpoch,true),isTrue);
    expect(PracticeGoogleImageCache.fresh(now,now.subtract(const Duration(days:4)).millisecondsSinceEpoch,false),isFalse);
    expect(PracticeGoogleImageCache.fresh(now,now.subtract(const Duration(days:2)).millisecondsSinceEpoch,false),isTrue);
  });
  test('monthly local counter rolls over and stops before 250',()async{
    const user='owner';
    expect(await PracticeGoogleImageCache.localCount(user),0);
    await PracticeGoogleImageCache.countAttempt(user);
    expect(await PracticeGoogleImageCache.localCount(user),1);
    expect(PracticeGoogleImageCache.maxPerDeviceMonth,240);
    final october=PracticeGoogleImageCache.counterKey(user,DateTime(2026,10,10));
    final november=PracticeGoogleImageCache.counterKey(user,DateTime(2026,11,10));
    expect(october,isNot(november));
  });
}
