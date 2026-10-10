import 'package:flutter/material.dart';
import '../services/supabase_backend_service.dart';
import 'practice_daily_visual_theme.dart';
import 'visceral_radio_fiche_view.dart';
import 'visceral_radio_course_widgets.dart';
import '../widgets/practice_context_glossary.dart';

/// Private, independent Practice training space. Images are fetched at viewing time.
class PracticeVisceralRadioScreen extends StatefulWidget {
  const PracticeVisceralRadioScreen({super.key});
  @override
  State<PracticeVisceralRadioScreen> createState() => _PracticeVisceralRadioScreenState();
}

class _PracticeVisceralRadioScreenState extends State<PracticeVisceralRadioScreen> {
  static const _owner = 'a6ab90cd-aa2c-41f3-a5e8-be00aedd019c';
  final _backend = SupabaseBackendService.instance;
  final List<Map<String, dynamic>> _history = [];
  Map<String, dynamic>? _session;
  bool _busy = false;
  String? _error;
  String? _courseError;
  String? _activeGeneration;
  int _courseBatchTarget = 0;
  int _coursePosition = 0, _casePosition = 0;
  final Map<int, Set<String>> _courseSelected = {}, _caseSelected = {};
  final Set<int> _courseDone = {}, _caseDone = {};

  Map<String, dynamic> _obj(dynamic v) => v is Map ? Map<String,dynamic>.from(v) : <String,dynamic>{};
  List<dynamic> _arr(dynamic v) => v is List ? v : const [];
  List<Map<String,dynamic>> _records(dynamic v) => _arr(v).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList();
  String _str(dynamic v) => v?.toString() ?? '';
  bool get _authorized {
    try { return _backend.enabled && _backend.client.auth.currentUser?.id == _owner; }
    catch (_) { return false; }
  }
  @override void initState(){super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _load());}
  Future<void> _load() async {
    if(!_authorized || _busy) return;
    setState(() => _busy=true);
    try {
      final response=await _backend.client.functions.invoke('generate-visceral-radio',body:{'action':'list'});
      final m=_obj(response.data);
      if(m['error']!=null)throw StateError(_str(m['error']));
      if(!mounted)return;
      setState((){
        _history..clear()..addAll(_records(m['sessions']));
        if(_session!=null){
          final match=_history.where((x)=>x['id']==_session?['id']);
          if(match.isNotEmpty)_session=match.first;
        }
      });
    }catch(e){if(mounted)setState(()=>_error='Chargement impossible : '+e.toString());}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _generate(String action) async {
    if (_busy || !_authorized) return;
    final startingCount = _arr(_session?['course_qcms']).length;
    final courseTarget = action == 'course_qcms'
        ? (startingCount + 10).clamp(0, 20).toInt()
        : 0;
    setState(() {
      _busy = true;
      _activeGeneration = action;
      _courseBatchTarget = courseTarget;
      _error = null;
      if (action == 'course_qcms') _courseError = null;
    });
    try {
      // A tap requests up to 10 new QCMs. Supabase saves each chunk of five
      // independently, so the first successful chunk is never discarded.
      while (true) {
        final previousCount = _arr(_session?['course_qcms']).length;
        final response = await _backend.client.functions.invoke(
          'generate-visceral-radio',
          body: {
            'action': action,
            if (action != 'create') 'id': _session?['id'],
          },
        );
        final m = _obj(response.data);
        if (m['error'] != null) {
          throw StateError(_str(m['error']) + ' ' + _str(m['detail']));
        }
        final result = _obj(m['session']);
        if (result.isEmpty) throw StateError('Réponse vide');
        if (!mounted) return;
        final nextCount = _arr(result['course_qcms']).length;
        final savedAnswered = int.tryParse(
          _str(_obj(result['progress'])['course_answered'])) ?? 0;
        if (action == 'course_qcms' && nextCount <= previousCount &&
            nextCount < courseTarget) {
          throw StateError('Aucune nouvelle question reçue. Réessaie.');
        }
        setState(() {
          _session = result;
          _history.removeWhere((x) => x['id'] == result['id']);
          _history.insert(0, result);
          if (action == 'create') _clearAnswers();
          // After the original ten QCMs, open the first newly generated one.
          if (action == 'course_qcms' && previousCount > 0 &&
              (_courseDone.contains(previousCount - 1) ||
               savedAnswered >= previousCount)) {
            _coursePosition = previousCount;
          }
        });
        if (action != 'course_qcms' || nextCount >= courseTarget ||
            nextCount >= 20) {
          break;
        }
      }
      if (mounted && action == 'course_qcms') {
        final generated = _arr(_session?['course_qcms']).length - startingCount;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$generated nouveaux QCM enregistrés. Les précédents sont conservés.'),
          duration: const Duration(seconds: 5),
        ));
      }
    } catch (e) {
      if (mounted) {
        final msg = 'Génération impossible : ' + e.toString();
        setState(() {
          _error = msg;
          if (action == 'course_qcms') _courseError = msg;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(action == 'course_qcms'
              ? 'Lot interrompu. Les QCM déjà générés sont conservés. Réessaie pour reprendre.'
              : msg),
          duration: const Duration(seconds: 6),
        ));
      }
    } finally {
      if (mounted) setState(() {
        _busy = false;
        _activeGeneration = null;
      });
    }
  }
  void _clearAnswers(){
    _coursePosition=0;_casePosition=0;
    _courseSelected.clear();_caseSelected.clear();
    _courseDone.clear();_caseDone.clear();
  }
  void _open(Map<String,dynamic> entry){
    if(_busy)return;
    setState((){_session=entry;_clearAnswers();_error=null;_courseError=null;});
  }
  Widget _label(String text,{double size=14,Color color=PracticeDailyVisualTheme.text,bool heavy=false}) =>
    Text(text,style:TextStyle(color:color,fontSize:size,fontWeight:heavy?FontWeight.w800:FontWeight.normal,height:1.42));
  Widget _box(Widget child)=>Container(
    padding:const EdgeInsets.all(14),margin:const EdgeInsets.only(bottom:12),
    decoration:BoxDecoration(color:PracticeDailyVisualTheme.surface,borderRadius:BorderRadius.circular(18),
      border:Border.all(color:PracticeDailyVisualTheme.border)),
    child:child,
  );
  Widget _button(String title,VoidCallback? action,{bool outlined=false,IconData icon=Icons.auto_awesome}) =>
    Padding(padding:const EdgeInsets.only(top:8),child:SizedBox(width:double.infinity,child:outlined
      ?OutlinedButton.icon(onPressed:_busy?null:action,style:PracticeDailyVisualTheme.secondaryButtonStyle,
          icon:Icon(icon),label:Text(title))
      :FilledButton.icon(onPressed:_busy?null:action,style:PracticeDailyVisualTheme.primaryButtonStyle,
          icon:Icon(icon),label:Text(title))));
  Widget _title(String title,String info)=>Padding(padding:const EdgeInsets.only(bottom:8),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      _label(title,size:17,heavy:true),
      if(info.isNotEmpty)_label(info,size:12,color:PracticeDailyVisualTheme.muted),
    ]));
  Widget _imageQueries(dynamic raw) {
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      ..._records(raw).take(3).map((x)=>VisceralMedicalGallery(
        query:_str(x['query']), caption:_str(x['purpose']),
        modality:_str(x['modality']),
        imageRequest:x,
      )),
    ]);
  }
  Widget _fiche()=>VisceralFicheView(
    key:ValueKey(_str(_session?['id'])),
    fiche:_obj(_session?['fiche']),
    sessionId:_str(_session?['id']),
  );
  List<Widget> _clinicalPhase(int currentPhase) {
    final data=_obj(_session?['case_data']);
    final stages=_records(data['stages']);
    return stages.where((s)=>s['phase'] is int&&(s['phase'] as int)<=currentPhase).map((s)=>Padding(
      padding:const EdgeInsets.only(bottom:10),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        _label('Phase '+_str(s['phase'])+' · '+_str(s['title']),heavy:true,color:PracticeDailyVisualTheme.mint),
        _label(_str(s['narrative']),size:13),
        _label(_str(s['clinical_findings']),size:13),
        if(currentPhase>=2)_label(_str(s['imaging_findings']),size:13),
        _imageQueries(s['image_requests']),
      ]))).toList();
  }
  Future<void> _recordProgress(bool caseQuiz) async {
    final session=_session;if(session==null)return;
    final questions=_records(session[caseQuiz?'case_qcms':'course_qcms']);
    final selected=caseQuiz?_caseSelected:_courseSelected;
    final reviewed=caseQuiz?_caseDone:_courseDone;
    var score=0;
    for(var i=0;i<questions.length;i++){
      if(!reviewed.contains(i))continue;
      final right=_records(questions[i]['options']).where((x)=>x['correct']==true).map((x)=>_str(x['key'])).toSet();
      if(right.length==selected[i]?.length&&right.containsAll(selected[i]??{}))score++;
    }
    try{
      final progress=_obj(session['progress']);
      progress[caseQuiz?'clinical_score':'course_score']=score;
      progress[caseQuiz?'clinical_answered':'course_answered']=reviewed.length;
      await _backend.client.functions.invoke('generate-visceral-radio',body:{
        'action':'progress','id':session['id'],'progress':progress,
      });
    }catch(_){/* A transient score error never deletes valid lessons. */}
  }
  Widget _quiz(bool caseQuiz){
    final list=_records(_session?[caseQuiz?'case_qcms':'course_qcms']);
    if(list.isEmpty)return const SizedBox.shrink();
    final current=(caseQuiz?_casePosition:_coursePosition).clamp(0,list.length-1).toInt();
    final q=list[current];
    final selections=caseQuiz?_caseSelected:_courseSelected;
    final done=caseQuiz?_caseDone:_courseDone;
    final checked=done.contains(current);
    final picked=selections.putIfAbsent(current,()=> <String>{});
    final countTarget=caseQuiz?(_session?['case_target']??10):20;
    return PracticeGlossaryScope(
      scopeId: 'vr-qcm:' + _str(_session?['id']) + ':' + (caseQuiz ? 'cas' : 'cours'),
      objective: _str(_obj(_session?['fiche'])['title']),
      content: list.map((item) => _str(item['statement']) + ' ' +
        _records(item['options']).map((o) => _str(o['text'])).join(' ')).join('\n'),
      kind: 'qcm',
      child: _box(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      _title(caseQuiz?'QCM clinique progressif':'QCM de la fiche',
        'Question '+(current+1).toString()+'/'+list.length.toString()+' · cible '+_str(countTarget)),
      if(caseQuiz)..._clinicalPhase((q['phase'] is int ? q['phase'] as int : 1).clamp(1,4).toInt()),
      PracticeGlossaryText(_str(q['statement']), richEnabled: checked, style: const TextStyle(
        color: PracticeDailyVisualTheme.text, fontSize: 15,
        fontWeight: FontWeight.w800, height: 1.42)),
      const SizedBox(height:12),
      ..._records(q['options']).map((o){
        final key=_str(o['key']);
        final isPicked=picked.contains(key);
        final correct=o['correct']==true;
        final accent=checked?(correct?PracticeDailyVisualTheme.mint:isPicked?Colors.redAccent:PracticeDailyVisualTheme.muted)
          :(isPicked?PracticeDailyVisualTheme.mint:PracticeDailyVisualTheme.border);
        return Padding(padding:const EdgeInsets.only(bottom:8),child:InkWell(
          onTap:checked?null:()=>setState((){isPicked?picked.remove(key):picked.add(key);}),
          child:Container(width:double.infinity,padding:const EdgeInsets.all(10),
            decoration:BoxDecoration(border:Border.all(color:accent),borderRadius:BorderRadius.circular(12),
              color:PracticeDailyVisualTheme.elevated),
            child:Row(children:[
              Icon(isPicked?Icons.check_box:Icons.check_box_outline_blank,color:accent,size:21),
              const SizedBox(width:8),Expanded(child:PracticeGlossaryText(key+'. '+_str(o['text']),
                richEnabled: checked,
                style: const TextStyle(color: PracticeDailyVisualTheme.text,
                  fontSize: 13, height: 1.42))),
            ]),
          ),
        ));
      }),
      if(!checked)_button('Valider mes réponses',picked.isEmpty?null:(){
        setState(()=>done.add(current));
        _recordProgress(caseQuiz);
      },icon:Icons.check_circle_outline),
      if(checked)...[
        ..._records(q['options']).map((o)=>Padding(padding:const EdgeInsets.only(top:4),
          child:_label(_str(o['key'])+' '+(o['correct']==true?'✓ ':'✗ ')+_str(o['explanation']),
            size:12,color:o['correct']==true?PracticeDailyVisualTheme.mint:PracticeDailyVisualTheme.muted))),
        const SizedBox(height:8),_label(_str(q['global_explanation']),size:13),
        _imageQueries(q['image_requests']),
        _button(current+1<list.length?'Question suivante':'Recommencer',(){
          setState((){
            if(current+1<list.length){if(caseQuiz){_casePosition++;}else{_coursePosition++;}}
            else{if(caseQuiz){_casePosition=0;_caseDone.clear();_caseSelected.clear();}
              else{_coursePosition=0;_courseDone.clear();_courseSelected.clear();}}
          });
        },icon:Icons.arrow_forward),
      ],
      if(current>0)_button('Question précédente',()=>setState((){
        if(caseQuiz){_casePosition--;}else{_coursePosition--;}
      }),outlined:true,icon:Icons.arrow_back),
    ])));

  }
  @override Widget build(BuildContext context){
    return Theme(data:PracticeDailyVisualTheme.from(context),child:Scaffold(
      appBar:AppBar(title:const Text('Viscéral × Radio')),
      body:Container(decoration:const BoxDecoration(gradient:PracticeDailyVisualTheme.pageGradient),
        child:SafeArea(child:!_authorized
          ?Center(child:_label('Espace privé, réservé au compte autorisé.'))
          :ListView(padding:const EdgeInsets.all(14),children:[
            Container(padding:const EdgeInsets.all(18),margin:const EdgeInsets.only(bottom:14),
              decoration:BoxDecoration(gradient:PracticeDailyVisualTheme.cardGradient,
                borderRadius:BorderRadius.circular(18)),
              child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                const Icon(Icons.biotech_outlined,color:Colors.white,size:30),
                _label('Mes révisions de résidanat',size:21,heavy:true),
                _label('Chirurgie viscérale · Imagerie · Techniques',size:13),
                _button('Générer une fiche surprise',()=>_generate('create'),icon:Icons.shuffle),
              ])),
            if(_busy)const LinearProgressIndicator(color:PracticeDailyVisualTheme.mint),
            if(_error!=null)_box(_label(_error!,color:Colors.orangeAccent)),
            if(_history.isNotEmpty)_box(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              _title('Bibliothèque privée','Reprendre une fiche sans nouvel appel Groq'),
              ..._history.take(30).map((s)=>ListTile(
                dense:true,contentPadding:EdgeInsets.zero,
                title:_label(_str(s['title']),size:13,heavy:true),
                subtitle:_label(_str(s['topic']),size:11,color:PracticeDailyVisualTheme.muted),
                leading:Icon(s['id']==_session?['id']?Icons.check_circle:Icons.book_outlined,
                  color:PracticeDailyVisualTheme.mint),
                onTap:()=>_open(s),
              )),
            ])),
            if(_session!=null)...[
              _fiche(),
              _box(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                _title('20 QCM de cours','2 lots Groq de 10 questions, corrections et explications IA'),
                _label(_arr(_session!['course_qcms']).length.toString()+'/20 générés'),
                if(_activeGeneration=='course_qcms') ...[
                  const SizedBox(height:8),
                  const LinearProgressIndicator(color:PracticeDailyVisualTheme.mint),
                  const SizedBox(height:6),
                  _label('Génération Groq en cours · ' +
                    _arr(_session!['course_qcms']).length.toString() + '/' +
                    _courseBatchTarget.toString() +
                    ' questions enregistrées. Ne ferme pas cette page.',
                    size:12,color:PracticeDailyVisualTheme.muted),
                ],
                if(_courseError!=null) ...[
                  const SizedBox(height:8),
                  _label(_courseError!,size:12,color:Colors.orangeAccent),
                  _label('Les questions précédentes sont conservées. Tu peux relancer le lot.',
                    size:11,color:PracticeDailyVisualTheme.muted),
                ],
                if(_arr(_session!['course_qcms']).length<20)
                  _button(_activeGeneration=='course_qcms'
                    ? 'Génération en cours…'
                    : 'Générer ' +
                        (20-_arr(_session!['course_qcms']).length).clamp(0,10).toString() +
                        ' QCM de la fiche',
                    _busy?null:()=>_generate('course_qcms')),
              ])),
              _quiz(false),
              _box(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                _title('Cas clinique lié à la fiche','Même sujet médical, patient fictif et imagerie'),
                if(_session!['case_data']==null)_button('Générer mon cas clinique',()=>_generate('case')),
                if(_session!['case_data']!=null)...[
                  _label(_str(_obj(_session!['case_data'])['title']),heavy:true),
                  _label(_str(_obj(_session!['case_data'])['patient']),size:12),
                  const SizedBox(height:8),
                  _label('Les phases sont révélées progressivement avec les QCM.',size:12,
                    color:PracticeDailyVisualTheme.muted),
                  _label('Questions : '+_arr(_session!['case_qcms']).length.toString()+'/'+_str(_session!['case_target']),
                    heavy:true),
                  if(_arr(_session!['case_qcms']).length<(_session!['case_target']??10))
                    _button('Générer les prochains QCM progressifs',()=>_generate('case_qcms')),
                ],
              ])),
              _quiz(true),
            ],
            _label('Images illustratives externes (pas celles du patient fictif). Aucun fichier ni lien image conservé dans Supabase.',
              color:PracticeDailyVisualTheme.muted,size:11),
          ]))),
    ));
  }
}

