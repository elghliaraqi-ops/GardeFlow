import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/supabase_backend_service.dart';
import 'practice_daily_visual_theme.dart';

/// Renders historic and new Groq course prose without modifying stored JSON.
class VisceralCourseText extends StatelessWidget {
  const VisceralCourseText(this.value, {super.key, this.fontSize = 14.5});
  final String value;
  final double fontSize;

  static List<String> numberedParts(String value) {
    final source = value.trim();
    final markers = RegExp(r'(?:^|\s)(\d{1,2})[.)]\s+').allMatches(source).toList();
    if (markers.length < 2 || markers.first.start != 0) return const [];
    return [
      for (var i = 0; i < markers.length; i++)
        source.substring(markers[i].start,
          i + 1 < markers.length ? markers[i+1].start : source.length)
          .trim().replaceFirst(RegExp(r'^\d{1,2}[.)]\s+'), ''),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    final points = numberedParts(value);
    if (points.isNotEmpty) {
      return Column(children: [
        for (var i = 0; i < points.length; i++)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: PracticeDailyVisualTheme.elevated.withValues(alpha: .7),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 28, height: 28, alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: PracticeDailyVisualTheme.mint.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(9)),
                child: Text((i+1).toString(),style:const TextStyle(
                  color: PracticeDailyVisualTheme.mint,fontWeight:FontWeight.w900)),
              ),
              const SizedBox(width: 11),
              Expanded(child: Text(points[i], style: TextStyle(
                color: PracticeDailyVisualTheme.text, fontSize: fontSize,
                height: 1.5))),
            ]),
          ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start,children: [
      for (final paragraph in value.trim().split(RegExp(r'\n\s*\n')))
        if (paragraph.trim().isNotEmpty)
          Padding(padding: const EdgeInsets.only(bottom: 12),child: Text(
            paragraph.trim(),style:TextStyle(
              color:PracticeDailyVisualTheme.text,fontSize:fontSize,height:1.58))),
    ]);
  }
}

/// Thumbnails and source links are resolved at display time and cached in RAM.
/// No images or image URLs are stored in Supabase database / Storage.
class VisceralMedicalGallery extends StatefulWidget {
  const VisceralMedicalGallery({super.key,required this.query,required this.caption,this.modality=''});
  final String query, caption, modality;
  @override State<VisceralMedicalGallery> createState()=>_VisceralMedicalGalleryState();
}

class _VisceralMedicalGalleryState extends State<VisceralMedicalGallery> {
  static final Map<String,Map<String,dynamic>> _cache = {};
  List<Map<String,dynamic>> images=[], sources=[];
  bool busy=false;
  String? message;
  int generation=0;
  String get cacheKey => widget.modality+'|'+widget.query;
  List<Map<String,dynamic>> rows(dynamic raw) => raw is List
    ? raw.whereType<Map>().map((v)=>Map<String,dynamic>.from(v)).toList()
    : <Map<String,dynamic>>[];
  @override void initState(){super.initState();_fetch();}
  @override void didUpdateWidget(covariant VisceralMedicalGallery old){
    super.didUpdateWidget(old);
    if(old.query!=widget.query||old.modality!=widget.modality)_fetch();
  }
  Future<void> _fetch({bool refresh=false})async{
    if(widget.query.trim().isEmpty)return;
    final n=++generation;
    final cached=refresh?null:_cache[cacheKey];
    if(cached!=null){
      setState((){
        images=rows(cached['images']);
        sources=rows(cached['medical_searches']);
        busy=false;message=null;
      });
      return;
    }
    setState((){busy=true;message=null;images=[];sources=[];});
    try {
      final response=await SupabaseBackendService.instance.client.functions.invoke(
        'generate-visceral-radio',
        body:{'action':'images','query':widget.query,'modality':widget.modality});
      final result=response.data is Map
        ? Map<String,dynamic>.from(response.data as Map)
        : <String,dynamic>{};
      if(!mounted||generation!=n)return;
      if(result['error']!=null)throw StateError('Images indisponibles');
      _cache[cacheKey]=result;
      setState((){
        images=rows(result['images']).where((v)=>
          (v['thumbnail']??'').toString().startsWith('https://') &&
          (v['source']??'').toString().startsWith('https://')).take(8).toList();
        sources=rows(result['medical_searches']);
      });
    }catch(_){
      if(mounted&&generation==n)setState(()=>message='Recherche temporairement indisponible.');
    }finally{
      if(mounted&&generation==n)setState(()=>busy=false);
    }
  }
  Future<void> _external(String value)async{
    final url=Uri.tryParse(value);
    if(url?.scheme=='https')await launchUrl(url!,mode:LaunchMode.externalApplication);
  }
  void _zoom(Map<String,dynamic> item) {
    final url=(item['full']??item['thumbnail']??'').toString();
    if(!url.startsWith('https://'))return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder:(_)=>_MedicalZoomViewer(
        url:url,source:(item['source']??'').toString(),
        title:(item['title']??widget.caption).toString(),
        credits:(item['creator']??'').toString()+' · '+(item['license']??'').toString(),
      )));
  }
  @override Widget build(BuildContext context)=>Container(
    margin:const EdgeInsets.symmetric(vertical:14),
    padding:const EdgeInsets.all(12),
    decoration:BoxDecoration(
      color:PracticeDailyVisualTheme.background.withValues(alpha:.72),
      border:Border.all(color:PracticeDailyVisualTheme.border),
      borderRadius:BorderRadius.circular(16)),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[
        const Icon(Icons.image_search_rounded,color:PracticeDailyVisualTheme.mint,size:21),
        const SizedBox(width:9),
        Expanded(child:Text(widget.caption.isEmpty?'Illustration radio-chirurgicale':widget.caption,
          style:const TextStyle(color:PracticeDailyVisualTheme.text,
            fontWeight:FontWeight.w800,fontSize:13))),
      ]),
      const SizedBox(height:5),
      const Text('Toucher pour agrandir • Pincer pour zoomer',
        style:TextStyle(color:PracticeDailyVisualTheme.muted,fontSize:11)),
      if(busy)...[
        const SizedBox(height:11),
        const LinearProgressIndicator(color:PracticeDailyVisualTheme.mint),
        const SizedBox(height:7),
        const Text('Recherche des images externes…',style:TextStyle(
          color:PracticeDailyVisualTheme.muted,fontSize:11)),
      ],
      if(images.isNotEmpty)...[
        const SizedBox(height:12),
        SizedBox(height:190,child:ListView.separated(
          scrollDirection:Axis.horizontal,itemCount:images.length,
          separatorBuilder:(_,__)=>const SizedBox(width:10),
          itemBuilder:(context,i){
            final item=images[i];
            return Semantics(button:true,label:'Agrandir l’image '+(i+1).toString(),
              child:InkWell(onTap:()=>_zoom(item),borderRadius:BorderRadius.circular(12),
                child:SizedBox(width:210,child:Column(children:[
                  Expanded(child:Stack(fit:StackFit.expand,children:[
                    ClipRRect(borderRadius:BorderRadius.circular(12),
                      child:Image.network((item['thumbnail']??'').toString(),
                        fit:BoxFit.contain,
                        errorBuilder:(_,__,___)=>Container(
                          alignment:Alignment.center,
                          color:PracticeDailyVisualTheme.elevated,
                          child:const Text('Miniature inaccessible',
                            style:TextStyle(color:PracticeDailyVisualTheme.muted,fontSize:11)))),
                    ),
                    Positioned(top:6,right:6,child:Container(
                      padding:const EdgeInsets.all(5),
                      decoration:BoxDecoration(color:Colors.black87,borderRadius:BorderRadius.circular(8)),
                      child:const Icon(Icons.zoom_in_rounded,color:Colors.white,size:20))),
                  ])),
                  const SizedBox(height:7),
                  Align(alignment:Alignment.centerLeft,child:Text(
                    (item['title']??'Image médicale').toString(),maxLines:1,
                    overflow:TextOverflow.ellipsis,
                    style:const TextStyle(color:PracticeDailyVisualTheme.text,
                      fontWeight:FontWeight.w700,fontSize:11))),
                  Align(alignment:Alignment.centerLeft,child:Text(
                    (item['provider']??'Source externe').toString()+' · '+
                      (item['license']??'').toString(),maxLines:1,
                    overflow:TextOverflow.ellipsis,style:const TextStyle(
                      color:PracticeDailyVisualTheme.muted,fontSize:10))),
                ]))),
              );
          },
        )),
      ],
      if(!busy&&images.isEmpty)...[
        const SizedBox(height:12),
        Text(message??'Aucun aperçu libre accessible pour ce sujet.',
          style:const TextStyle(color:PracticeDailyVisualTheme.muted,fontSize:12)),
        TextButton.icon(onPressed:()=>_fetch(refresh:true),
          icon:const Icon(Icons.refresh_rounded,size:17),
          label:const Text('Relancer la recherche')),
      ],
      if(sources.isNotEmpty)...[
        const SizedBox(height:7),
        const Text('Autres banques d’imagerie',style:TextStyle(
          color:PracticeDailyVisualTheme.muted,fontSize:11,fontWeight:FontWeight.w700)),
        Wrap(spacing:4,children:sources.map((s)=>TextButton.icon(
          onPressed:()=>_external((s['source']??'').toString()),
          icon:const Icon(Icons.open_in_new_rounded,size:14),
          label:Text((s['title']??'Source').toString(),
            style:const TextStyle(fontSize:11)))).toList()),
      ],
      const Text('Images représentatives externes — jamais celles du patient fictif.',
        style:TextStyle(color:PracticeDailyVisualTheme.muted,fontSize:10)),
    ]));
}

class _MedicalZoomViewer extends StatelessWidget {
  const _MedicalZoomViewer({required this.url,required this.source,
    required this.title,required this.credits});
  final String url,source,title,credits;
  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:const Color(0xFF03080F),
    appBar:AppBar(title:const Text('Visionneuse médicale'),
      backgroundColor:PracticeDailyVisualTheme.background,actions:[
      IconButton(tooltip:'Ouvrir la source originale',
        icon:const Icon(Icons.open_in_new_rounded),
        onPressed:(){
          final uri=Uri.tryParse(source);
          if(uri?.scheme=='https')launchUrl(uri!,mode:LaunchMode.externalApplication);
        }),
    ]),
    body:SafeArea(child:Column(children:[
      Expanded(child:InteractiveViewer(minScale:.5,maxScale:8,
        boundaryMargin:const EdgeInsets.all(90),
        child:Center(child:Image.network(url,fit:BoxFit.contain,
          errorBuilder:(_,__,___)=>const Text('Image non disponible',
            style:TextStyle(color:Colors.white70)))))),
      Container(width:double.infinity,color:const Color(0xFF11283A),
        padding:const EdgeInsets.all(15),child:Column(
          crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(title,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w800)),
          const SizedBox(height:4),
          Text(credits,style:const TextStyle(color:Colors.white70,fontSize:12)),
          const Text('Zoom tactile · Déplacement · Source en haut à droite',
            style:TextStyle(color:Colors.white54,fontSize:11)),
        ])),
    ])));
}
