import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/screens/visceral_radio_course_widgets.dart';
import 'package:huim6_planning/screens/visceral_radio_fiche_view.dart';

void main() {
  test('Ten numbered historic points render as separate pieces', () {
    final text=List.generate(10,(i)=>(i+1).toString()+'. Point médical '+(i+1).toString()+'.').join(' ');
    final parts=VisceralCourseText.numberedParts(text);
    expect(parts.length,10);
    expect(parts.first,startsWith('Point médical 1'));
    expect(parts.last,startsWith('Point médical 10'));
  });
  test('Ordinary anatomy paragraphs remain paragraphs', () {
    expect(VisceralCourseText.numberedParts(
      'Le rectum se trouve dans le pelvis. L’IRM sert au bilan.'),isEmpty);
  });
  testWidgets('Existing fiche JSON is displayed without regeneration', (tester) async {
    const fixture=<String,dynamic>{
      'title':'Cancer du rectum',
      'summary':'Cours de chirurgie et radiologie pelvienne',
      'sections':[
        {'key':'anatomie','title':'Anatomie du rectum',
          'content':'Le rectum est situé dans le pelvis.',
          'key_points':['Rapport avec le mésorectum'],'image_requests':[]},
        {'key':'imagerie','title':'IRM rectale',
          'content':'Les séquences T2 sont importantes.',
          'key_points':[],'image_requests':[]},
      ],
      'study_core':['Stadification IRM','Technique opératoire'],
      'references':['Référence indicative de Groq'],
    };
    await tester.pumpWidget(const MaterialApp(home:Scaffold(
      body:SingleChildScrollView(child:VisceralFicheView(
        sessionId:'historical-session',fiche:fixture)))));
    await tester.pump();
    expect(find.text('Cancer du rectum'),findsOneWidget);
    expect(find.textContaining('CHAPITRE 01'),findsOneWidget);
    expect(find.text('Anatomie du rectum'),findsOneWidget);
    expect(find.text('L’ESSENTIEL EN UN COUP D’ŒIL'),findsOneWidget);
    expect(find.textContaining('Bibliographie proposée'),findsOneWidget);
  });
}
