class PracticeDailyQuestion {
 final String question,topic,correction;
 final List<String> options;
 final int? selectedIndex,correctIndex;
 const PracticeDailyQuestion({required this.question,required this.options,required this.topic,this.correction='',this.selectedIndex,this.correctIndex});
 factory PracticeDailyQuestion.fromMap(Map<String,dynamic> m) {
   final o=m['options'];
   return PracticeDailyQuestion(question:'${m['question'] ?? ''}',
     options:o is List?o.map((x)=>'$x').toList(growable:false):const [],
     topic:'${m['topic'] ?? ''}',correction:'${m['correction'] ?? ''}',
     selectedIndex:int.tryParse('${m['selected_index'] ?? ''}'),
     correctIndex:int.tryParse('${m['correct_index'] ?? ''}'));
 }
}
class PracticeDailySession {
 final bool ready,completed;
 final DateTime day;
 final String mode,caseTitle,caseStem;
 final List<PracticeDailyQuestion> questions;
 final int? score;
 const PracticeDailySession({required this.ready,required this.completed,required this.day,required this.mode,
 required this.caseTitle,required this.caseStem,required this.questions,required this.score});
 factory PracticeDailySession.fromMap(Map<String,dynamic> m) {
  final source=m['questions'];
  final q=source is List?source.whereType<Map>().map((x)=>PracticeDailyQuestion.fromMap(Map<String,dynamic>.from(x))).toList(growable:false):<PracticeDailyQuestion>[];
  final ready=m['ready']==true, completed=m['completed']==true;
  if(ready&&(q.length!=10||q.any((x)=>x.options.length!=4)))throw StateError('Le défi doit comporter exactement 10 QCM.');
  if(!completed&&q.any((x)=>x.correctIndex!=null||x.correction.isNotEmpty))throw StateError('Corrigé dévoilé avant la fin.');
  final day=DateTime.tryParse('${m['day'] ?? ''}');
  if(day==null)throw StateError('Date du défi invalide.');
  return PracticeDailySession(ready:ready,completed:completed,day:day,mode:'${m['mode'] ?? 'cours'}',
   caseTitle:'${m['case_title'] ?? ''}',caseStem:'${m['case_stem'] ?? ''}',questions:q,
   score:int.tryParse('${m['score'] ?? ''}'));
 }
}
class PracticeDailyCalendarEntry {
 final DateTime day;final int score;final String mode;
 const PracticeDailyCalendarEntry({required this.day,required this.score,required this.mode});
 factory PracticeDailyCalendarEntry.fromMap(Map<String,dynamic> m){
  final day=DateTime.tryParse('${m['challenge_date'] ?? ''}');
  if(day==null)throw StateError('Jour invalide.');
  return PracticeDailyCalendarEntry(day:day,score:int.tryParse('${m['score'] ?? 0}')??0,mode:'${m['mode'] ?? ''}');
 }
}
