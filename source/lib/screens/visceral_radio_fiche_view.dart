import 'package:flutter/material.dart';
import 'practice_daily_visual_theme.dart';
import 'visceral_radio_course_widgets.dart';

/// Read-only universal renderer for historic and future Viscéral × Radio fiches.
/// Does not migrate, regenerate or overwrite any content in Supabase.
class VisceralFicheView extends StatelessWidget {
  const VisceralFicheView({super.key,required this.fiche,required this.sessionId});
  final Map<String,dynamic> fiche;
  final String sessionId;
  static String text(dynamic v)=>v?.toString()??'';
  static List<dynamic> items(dynamic raw)=>raw is List?raw:const [];
  static List<Map<String,dynamic>> records(dynamic raw)=>items(raw).whereType<Map>()
      .map((v)=>Map<String,dynamic>.from(v)).toList();
  static const ink=PracticeDailyVisualTheme.text;
  static const mint=PracticeDailyVisualTheme.mint;
  static const muted=PracticeDailyVisualTheme.muted;

  Widget galleries(dynamic raw){
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      ...records(raw).take(3).map((x)=>VisceralMedicalGallery(
        key:ValueKey(text(x['query'])+'|'+text(x['modality'])),
        query:text(x['query']),caption:text(x['purpose']),modality:text(x['modality']),
      )),
    ]);
  }

  Widget section(Map<String,dynamic> part,int i){
    final title=text(part['title']),lower=title.toLowerCase();
    final icon=lower.contains('radio')||lower.contains('imagerie')||lower.contains('irm')
      ?Icons.document_scanner_rounded
      :lower.contains('opérat')||lower.contains('chirurg')?Icons.medical_services_rounded
      :lower.contains('anatom')?Icons.account_tree_rounded
      :lower.contains('complication')?Icons.monitor_heart_rounded
      :lower.contains('point')||lower.contains('retenir')?Icons.stars_rounded
      :Icons.menu_book_rounded;
    final keyPoints=items(part['key_points']);
    return Container(
      margin:const EdgeInsets.only(bottom:13),
      decoration:BoxDecoration(color:PracticeDailyVisualTheme.surface,
        borderRadius:BorderRadius.circular(19),
        border:Border.all(color:PracticeDailyVisualTheme.border)),
      clipBehavior:Clip.antiAlias,
      child:Theme(data:ThemeData.dark().copyWith(dividerColor:Colors.transparent),
        child:ExpansionTile(
          key:PageStorageKey('vr-'+sessionId+'-'+i.toString()),
          initiallyExpanded:i<=1,
          maintainState:false,
          iconColor:mint,collapsedIconColor:muted,
          tilePadding:const EdgeInsets.fromLTRB(15,13,13,13),
          childrenPadding:const EdgeInsets.fromLTRB(16,0,16,17),
          title:Row(children:[
            Container(width:37,height:37,
              decoration:BoxDecoration(color:mint.withValues(alpha:.14),
                borderRadius:BorderRadius.circular(12)),
              child:Icon(icon,size:19,color:mint)),
            const SizedBox(width:11),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('CHAPITRE '+(i+1).toString().padLeft(2,'0'),
                style:const TextStyle(color:mint,fontWeight:FontWeight.w900,
                  fontSize:10,letterSpacing:.8)),
              const SizedBox(height:4),
              Text(title,style:const TextStyle(color:ink,fontWeight:FontWeight.w800,
                fontSize:15.5,height:1.24)),
            ])),
          ]),
          children:[
            Align(alignment:Alignment.centerLeft,child:Column(
              crossAxisAlignment:CrossAxisAlignment.stretch,children:[
                VisceralCourseText(text(part['content']),
                  fontSize:lower.contains('point')?13.5:14.5),
                if(keyPoints.isNotEmpty)Container(
                  margin:const EdgeInsets.only(top:4,bottom:8),
                  padding:const EdgeInsets.all(12),
                  decoration:BoxDecoration(
                    color:PracticeDailyVisualTheme.elevated.withValues(alpha:.64),
                    borderRadius:BorderRadius.circular(13)),
                  child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                    const Row(children:[
                      Icon(Icons.push_pin_outlined,color:mint,size:17),
                      SizedBox(width:8),
                      Text('À RETENIR',style:TextStyle(color:mint,
                        fontSize:11,fontWeight:FontWeight.w900,letterSpacing:.7)),
                    ]),
                    const SizedBox(height:8),
                    ...keyPoints.map((point)=>Padding(
                      padding:const EdgeInsets.only(bottom:8),
                      child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
                        const Padding(padding:EdgeInsets.only(top:6),
                          child:Icon(Icons.circle,color:mint,size:6)),
                        const SizedBox(width:9),
                        Expanded(child:Text(text(point),style:const TextStyle(
                          color:ink,fontSize:12.5,height:1.45))),
                      ]))),
                  ]),
                ),
                galleries(part['image_requests']),
              ])),
          ],
        ),
      ),
    );
  }
  @override Widget build(BuildContext context){
    final chapters=records(fiche['sections']);
    final refs=items(fiche['references']);
    final highlights=items(fiche['study_core']);
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Container(
        margin:const EdgeInsets.only(bottom:13),
        padding:const EdgeInsets.all(18),
        decoration:BoxDecoration(
          gradient:const LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,
            colors:[Color(0xFF183F5C),Color(0xFF192F53),Color(0xFF104D42)]),
          border:Border.all(color:PracticeDailyVisualTheme.border),
          borderRadius:BorderRadius.circular(21)),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Row(children:[
            Icon(Icons.import_contacts_rounded,color:mint,size:21),
            SizedBox(width:8),
            Expanded(child:Text('FICHE DE RÉVISION · VISCÉRAL × RADIO',
              style:TextStyle(color:mint,fontSize:10.5,
                fontWeight:FontWeight.w900,letterSpacing:.8))),
          ]),
          const SizedBox(height:13),
          Text(text(fiche['title']),style:const TextStyle(color:ink,
            fontSize:23,fontWeight:FontWeight.w900,height:1.22)),
          const SizedBox(height:12),
          Text(text(fiche['summary']),style:const TextStyle(
            color:Color(0xFFE2EEF8),fontSize:14,height:1.54)),
          const SizedBox(height:12),
          Text(chapters.length.toString()+' chapitres · Anatomie · Imagerie · Chirurgie',
            style:const TextStyle(color:Color(0xFFBEF0E2),fontSize:11)),
        ]),
      ),
      if(highlights.isNotEmpty)Container(
        margin:const EdgeInsets.only(bottom:14),padding:const EdgeInsets.all(14),
        decoration:BoxDecoration(color:PracticeDailyVisualTheme.surface,
          borderRadius:BorderRadius.circular(17),
          border:Border.all(color:PracticeDailyVisualTheme.border)),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Row(children:[
            Icon(Icons.bolt_rounded,color:PracticeDailyVisualTheme.gold,size:20),
            SizedBox(width:8),
            Text('L’ESSENTIEL EN UN COUP D’ŒIL',
              style:TextStyle(color:ink,fontSize:12,fontWeight:FontWeight.w900)),
          ]),
          const SizedBox(height:11),
          ...highlights.take(5).map((v)=>Padding(
            padding:const EdgeInsets.only(bottom:9),
            child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
              const Icon(Icons.check_circle_outline,color:mint,size:17),
              const SizedBox(width:10),
              Expanded(child:Text(text(v),style:const TextStyle(
                color:ink,fontSize:13,height:1.45))),
            ]),
          )),
        ]),
      ),
      Padding(padding:const EdgeInsets.only(bottom:11),
        child:Row(children:[
          const Icon(Icons.layers_rounded,color:mint,size:20),
          const SizedBox(width:9),
          Expanded(child:Text('Le cours · '+chapters.length.toString()+' chapitres',
            style:const TextStyle(color:ink,fontSize:17,fontWeight:FontWeight.w900))),
        ])),
      ...chapters.asMap().entries.map((e)=>section(e.value,e.key)),
      if(refs.isNotEmpty)Container(
        margin:const EdgeInsets.only(bottom:14),
        decoration:BoxDecoration(color:PracticeDailyVisualTheme.surface,
          border:Border.all(color:PracticeDailyVisualTheme.border),
          borderRadius:BorderRadius.circular(16)),
        child:Theme(data:ThemeData.dark().copyWith(dividerColor:Colors.transparent),
          child:ExpansionTile(
            title:const Text('Bibliographie proposée par Groq',
              style:TextStyle(color:ink,fontSize:14,fontWeight:FontWeight.w800)),
            subtitle:const Text('Références indicatives, non vérifiées automatiquement',
              style:TextStyle(color:muted,fontSize:11)),
            iconColor:mint,collapsedIconColor:muted,
            childrenPadding:const EdgeInsets.fromLTRB(15,0,15,15),
            children:refs.map((x)=>Padding(
              padding:const EdgeInsets.only(bottom:9),
              child:Text('• '+text(x),style:const TextStyle(
                color:muted,fontSize:12,height:1.45)))).toList(),
          ),
        ),
      ),
    ]);
  }
}
