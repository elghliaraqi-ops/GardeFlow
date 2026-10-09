import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/models/practice_daily_models.dart';

void main() {
  Map<String,dynamic> question(int i) => <String,dynamic>{
    'question':'Question $i','options':<String>['A','B','C','D'],'topic':'diagnostic',
  };
  test('a pending daily challenge has 10 QCM and hides corrections', () {
    final state=PracticeDailySession.fromMap(<String,dynamic>{
      'ready':true,'completed':false,'day':'2026-10-09','mode':'cours',
      'questions':List<Map<String,dynamic>>.generate(10,question),
    });
    expect(state.questions,hasLength(10));
    expect(state.questions.every((q)=>q.correctIndex==null&&q.correction.isEmpty),isTrue);
    expect(state.score,isNull);
  });
  test('a completed challenge retains score and selected responses', () {
    final state=PracticeDailySession.fromMap(<String,dynamic>{
      'ready':true,'completed':true,'day':'2026-10-09','mode':'cas_clinique',
      'score':8,'case_title':'Simulation IA','case_stem':'Cas fictif',
      'questions':List<Map<String,dynamic>>.generate(10,(i)=>{
        ...question(i),'selected_index':i%4,'correct_index':i%4,'correction':'Correction IA'
      }),
    });
    expect(state.completed,isTrue);
    expect(state.score,8);
    expect(state.questions.first.selectedIndex,0);
    expect(state.questions.first.correction,'Correction IA');
  });
  test('refuses incomplete challenge or premature answer keys', () {
    expect(()=>PracticeDailySession.fromMap(<String,dynamic>{
      'ready':true,'completed':false,'day':'2026-10-09','mode':'cours',
      'questions':List<Map<String,dynamic>>.generate(9,question),
    }),throwsStateError);
    expect(()=>PracticeDailySession.fromMap(<String,dynamic>{
      'ready':true,'completed':false,'day':'2026-10-09','mode':'cours',
      'questions':List<Map<String,dynamic>>.generate(10,(i)=>{...question(i),'correct_index':2}),
    }),throwsStateError);
  });
  test('parses monthly score without marking other days complete', () {
    final item=PracticeDailyCalendarEntry.fromMap(<String,dynamic>{
      'challenge_date':'2026-10-09','mode':'cours','score':7
    });
    expect(item.day.day,9);
    expect(item.score,7);
  });
}
