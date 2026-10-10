import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/backend_config.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/supabase_backend_service.dart';
import '../services/practice_google_image_cache.dart';
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

/// The authenticated image proxy solves Flutter Web CanvasKit image CORS and
/// keeps medical images outside the application database and storage.
String visceralImageProxyUrl(String external) =>
    '${BackendConfig.supabaseUrl}/functions/v1/generate-visceral-radio?asset=${Uri.encodeComponent(external)}';
Map<String,String> visceralImageHeaders() {
  final token=SupabaseBackendService.instance.client.auth.currentSession?.accessToken;
  return {
    'apikey': BackendConfig.supabasePublishableKey,
    if(token!=null) 'Authorization':'Bearer '+token,
  };
}

/// Thumbnails and source links are resolved at display time and cached in RAM.
/// No images or image URLs are stored in Supabase database / Storage.
class VisceralMedicalGallery extends StatefulWidget {
  const VisceralMedicalGallery({super.key,required this.query,required this.caption,this.modality='',this.imageRequest=const {}});
  final String query, caption, modality;
  final Map<String,dynamic> imageRequest;
  @override State<VisceralMedicalGallery> createState()=>_VisceralMedicalGalleryState();
}

class _VisceralMedicalGalleryState extends State<VisceralMedicalGallery> {
  static final Map<String,Map<String,dynamic>> _cache = {};
  // Image bytes stay only in this widget's RAM. Flutter Web's Image.network
  // cannot reliably send Authorization to the private Supabase GET endpoint.
  final Map<String,Future<Uint8List?>> _imageFutures={};
  List<Map<String,dynamic>> images=[], sources=[], articles=[], googleImages=[];
  String googleKey='';
  bool googleCached=false,googleEnabled=false,searchingGoogle=false;
  String? googleMessage;
  int localGoogleCount=0;
  List<Map<String,dynamic>> get visibleImages {
    // A figure resolved from a peer-reviewed article belongs in the zoomable
    // gallery as well as in its article card. Preserve the source article link.
    final articleFigures=articles.where((a)=>
      (a['figure_caption']??'').toString().isNotEmpty &&
      (a['thumbnail']??'').toString().startsWith('https://'))
      .map((a)=><String,dynamic>{
        'thumbnail':a['thumbnail'], 'full':a['thumbnail'],
        'source':a['figure_page']??a['source'],
        'title':a['figure_caption'], 'creator':a['summary']??'',
        'license':a['license']??'Voir la licence de l’article',
        'provider':a['provider']??'PubMed Central',
      });
    final known=<String>{};
    return [...images,...articleFigures,...googleImages].where((x){
      final url=(x['full']??x['thumbnail']??'').toString();
      return url.startsWith('https://')&&known.add(url);
    }).take(12).toList();
  }
  bool busy=false;
  String? message;
  int generation=0;
  String get cacheKey => jsonEncode(widget.imageRequest.isEmpty?{'query':widget.query,'modality':widget.modality}:widget.imageRequest);
  List<Map<String,dynamic>> rows(dynamic raw) => raw is List
    ? raw.whereType<Map>().map((v)=>Map<String,dynamic>.from(v)).toList()
    : <Map<String,dynamic>>[];
  @override void initState(){super.initState();_fetch();}
  @override void didUpdateWidget(covariant VisceralMedicalGallery old){
    super.didUpdateWidget(old);
    if(old.query!=widget.query||old.modality!=widget.modality||jsonEncode(old.imageRequest)!=jsonEncode(widget.imageRequest))_fetch();
  }
  Future<void> _fetch({bool refresh=false})async{
    if(widget.query.trim().isEmpty)return;
    final n=++generation;
    if(refresh)_imageFutures.clear();
    final cached=refresh?null:_cache[cacheKey];
    if(cached!=null){
      setState((){
        images=rows(cached['images']);
        sources=rows(cached['medical_searches']);
        articles=rows(cached['article_previews']);
        busy=false;message=null;
      });
      await _restoreGoogle(cached,n);
      return;
    }
    setState((){busy=true;message=null;images=[];sources=[];articles=[];
      googleImages=[];googleCached=false;googleKey='';googleEnabled=false;googleMessage=null;});
    try {
      final response=await SupabaseBackendService.instance.client.functions.invoke(
        'generate-visceral-radio',
        body:{'action':'images','image_request':widget.imageRequest.isNotEmpty?widget.imageRequest:{'query':widget.query,'modality':widget.modality,'purpose':widget.caption}});
      final result=response.data is Map
        ? Map<String,dynamic>.from(response.data as Map)
        : <String,dynamic>{};
      if(!mounted||generation!=n)return;
      if(result['error']!=null)throw StateError('Images indisponibles');
      // An article-only response is NOT a successful image search. Do not
      // memoize it: new open-access figure sources must remain discoverable
      // when a historic fiche is reopened.
      if(rows(result['images']).isNotEmpty ||
         rows(result['article_previews']).any((a)=>
           (a['figure_caption']??'').toString().isNotEmpty &&
           (a['thumbnail']??'').toString().startsWith('https://'))){
        _cache[cacheKey]=result;
      }else{
        _cache.remove(cacheKey);
      }
      setState((){
        images=rows(result['images']).where((v)=>
          (v['thumbnail']??'').toString().startsWith('https://') &&
          (v['source']??'').toString().startsWith('https://')).take(8).toList();
        sources=rows(result['medical_searches']);
        articles=rows(result['article_previews']);
      });
      await _restoreGoogle(result,n);
    }catch(_){
      if(mounted&&generation==n)setState(()=>message='Recherche temporairement indisponible.');
    }finally{
      if(mounted&&generation==n)setState(()=>busy=false);
    }
  }
  String get _userId => SupabaseBackendService.instance.client.auth.currentUser?.id??'';
  Future<void> _restoreGoogle(Map<String,dynamic> result,int requestNumber)async {
    final key=(result['google_cache_key']??'').toString();
    final enabled=result['google_images_available']==true;
    final user=_userId;
    List<Map<String,dynamic>>? existing;
    var count=0;
    try{
      if(user.isNotEmpty&&key.isNotEmpty){
        existing=await PracticeGoogleImageCache.read(userId:user,googleKey:key);
        count=await PracticeGoogleImageCache.localCount(user);
      }
    }catch(_){/* Cache unavailable => explicit button still possible with warning. */}
    if(!mounted||generation!=requestNumber)return;
    setState((){
      googleKey=key;googleEnabled=enabled;
      localGoogleCount=count;
      googleCached=existing!=null;
      googleImages=existing??[];
      googleMessage=existing!=null&&existing.isEmpty
        ?'Aucune image Google trouvée. Nouvel essai possible après 2 heures.'
        :null;
    });
  }
  Future<void> _searchGoogle()async{
    if(searchingGoogle||googleCached||!googleEnabled||googleKey.isEmpty)return;
    final user=_userId;
    if(user.isEmpty)return;
    setState((){searchingGoogle=true;googleMessage=null;});
    try{
      final count=await PracticeGoogleImageCache.localCount(user);
      if(count>=PracticeGoogleImageCache.maxPerDeviceMonth){
        if(mounted)setState(()=>googleMessage='Limite de prudence atteinte (240 recherches déclenchées sur cet appareil ce mois-ci).');
        return;
      }
      // Count BEFORE making the network request to conservatively protect quota.
      await PracticeGoogleImageCache.countAttempt(user);
      final response=await SupabaseBackendService.instance.client.functions.invoke(
        'generate-visceral-radio',
        body:{'action':'google_images','image_request':widget.imageRequest.isNotEmpty
          ?widget.imageRequest:{'query':widget.query,'modality':widget.modality,'purpose':widget.caption}},
      );
      final result=response.data is Map
        ?Map<String,dynamic>.from(response.data as Map):<String,dynamic>{};
      if(result['error']!=null||result['google_enabled']!=true||result['search_executed']!=true){
        throw StateError('Recherche Google indisponible');
      }
      final list=rows(result['images']).where((x)=>
        (x['thumbnail']??'').toString().startsWith('https://')).take(8).toList();
      await PracticeGoogleImageCache.write(
        userId:user,googleKey:googleKey,images:list);
      if(!mounted)return;
      setState((){
        googleImages=list;googleCached=true;
        localGoogleCount=count+1;
        googleMessage=list.isEmpty
          ?'Aucune image Google adaptée trouvée ; nouvel essai possible après 2 heures.'
          :'Résultats Google récupérés et mémorisés 30 jours sur cet appareil.';
      });
    }catch(_){
      if(mounted)setState(()=>googleMessage='Recherche Google indisponible ; vérifiez votre connexion. Aucun nouvel essai automatique.');
    }finally{
      if(mounted)setState(()=>searchingGoogle=false);
    }
  }
  Future<Uint8List?> _fetchImageBytes(String external)async{
    if(!external.startsWith('https://'))return null;
    try{
      final response=await http.get(
        Uri.parse(visceralImageProxyUrl(external)),
        headers:visceralImageHeaders(),
      ).timeout(const Duration(seconds:20));
      final mime=(response.headers['content-type']??'').toLowerCase();
      if(response.statusCode!=200||!mime.startsWith('image/')||
         response.bodyBytes.isEmpty||response.bodyBytes.lengthInBytes>12*1024*1024)
        return null;
      return response.bodyBytes;
    }catch(_){return null;}
  }
  Future<Uint8List?> _imageBytes(String external)=>
    _imageFutures.putIfAbsent(external,()=>_fetchImageBytes(external));
  Widget _imagePreview(String external,{double? width,double? height,bool compact=false}){
    return FutureBuilder<Uint8List?>(
      future:_imageBytes(external),
      builder:(context,snapshot){
        if(snapshot.connectionState!=ConnectionState.done){
          return const Center(child:SizedBox(width:21,height:21,
            child:CircularProgressIndicator(strokeWidth:2,
              color:PracticeDailyVisualTheme.mint)));
        }
        final bytes=snapshot.data;
        if(bytes!=null)return Image.memory(bytes,width:width,height:height,fit:BoxFit.contain,
          errorBuilder:(_,__,___)=>const Icon(Icons.broken_image_outlined,
            color:PracticeDailyVisualTheme.muted));
        if(compact)return const Icon(Icons.article_outlined,
          color:PracticeDailyVisualTheme.mint,size:22);
        return Container(
          alignment:Alignment.center,
          color:PracticeDailyVisualTheme.elevated,
          child:const Column(mainAxisAlignment:MainAxisAlignment.center,children:[
            Icon(Icons.image_not_supported_outlined,color:PracticeDailyVisualTheme.muted),
            SizedBox(height:7),
            Text('Aperçu inaccessible',style:TextStyle(
              color:PracticeDailyVisualTheme.muted,fontSize:11))]));
      },
    );
  }
  Future<void> _external(String value)async{
    final url=Uri.tryParse(value);
    if(url?.scheme=='https')await launchUrl(url!,mode:LaunchMode.externalApplication);
  }
  Future<void> _zoom(Map<String,dynamic> item)async{
    final url=(item['full']??item['thumbnail']??'').toString();
    if(!url.startsWith('https://'))return;
    final bytes=await _imageBytes(url) ??
      await _imageBytes((item['thumbnail']??'').toString());
    if(!mounted)return;
    if(bytes==null){
      await _external((item['source']??'').toString());
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder:(_)=>_MedicalZoomViewer(
        bytes:bytes,source:(item['source']??'').toString(),
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
      if(visibleImages.isNotEmpty)...[
        const SizedBox(height:12),
        SizedBox(height:190,child:ListView.separated(
          scrollDirection:Axis.horizontal,itemCount:visibleImages.length,
          separatorBuilder:(_,__)=>const SizedBox(width:10),
          itemBuilder:(context,i){
            final item=visibleImages[i];
            return Semantics(button:true,label:'Agrandir l’image '+(i+1).toString(),
              child:InkWell(onTap:()=>_zoom(item),borderRadius:BorderRadius.circular(12),
                child:SizedBox(width:210,child:Column(children:[
                  Expanded(child:Stack(fit:StackFit.expand,children:[
                    ClipRRect(borderRadius:BorderRadius.circular(12),
                      child:_imagePreview((item['thumbnail']??'').toString())),
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
      if(googleKey.isNotEmpty)...[
        const SizedBox(height:10),
        if(googleImages.isNotEmpty)
          const Text('Google Images — résultats en cache local',
            style:TextStyle(color:PracticeDailyVisualTheme.mint,fontSize:11,
              fontWeight:FontWeight.w700)),
        if(!googleCached&&googleEnabled)
          OutlinedButton.icon(
            onPressed:searchingGoogle?null:_searchGoogle,
            icon:searchingGoogle
              ?const SizedBox(width:15,height:15,child:CircularProgressIndicator(strokeWidth:2))
              :const Icon(Icons.search_rounded,size:17),
            label:Text(searchingGoogle
              ?'Recherche Google en cours…'
              :'Rechercher avec Google (1 crédit SerpApi maximum)')),
        if(googleCached&&googleImages.isNotEmpty)
          const Text('Recherche déjà effectuée : aucune nouvelle requête SerpApi.',
            style:TextStyle(color:PracticeDailyVisualTheme.muted,fontSize:11)),
        if(googleMessage!=null)
          Text(googleMessage!,style:const TextStyle(
            color:PracticeDailyVisualTheme.muted,fontSize:11)),
        Text('Quota prudent local : $localGoogleCount/240 recherches déclenchées ce mois-ci (cet appareil uniquement).',
          style:const TextStyle(color:PracticeDailyVisualTheme.muted,fontSize:10)),
      ],
      if(articles.isNotEmpty)...[
        const SizedBox(height:12),
        const Text('Articles sources (liens vers les figures)',
          style:TextStyle(color:PracticeDailyVisualTheme.mint,fontSize:12,fontWeight:FontWeight.w800)),
        const SizedBox(height:7),
        ...articles.take(4).map((a)=>Container(
          margin:const EdgeInsets.only(bottom:8),
          decoration:BoxDecoration(color:PracticeDailyVisualTheme.elevated.withValues(alpha:.65),
            borderRadius:BorderRadius.circular(11)),
          child:InkWell(
            onTap:()=>_external((a['figure_page']??a['source']??'').toString()),
            borderRadius:BorderRadius.circular(11),
            child:Padding(padding:const EdgeInsets.all(11),
              child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
                if((a['figure_caption']??'').toString().isNotEmpty &&
                  (a['thumbnail']??'').toString().startsWith('https://'))
                  Padding(padding:const EdgeInsets.only(right:9),
                    child:ClipRRect(borderRadius:BorderRadius.circular(8),
                      child:SizedBox(width:65,height:65,
                        child:_imagePreview((a['thumbnail']??'').toString(),
                          width:65,height:65,compact:true)))),
                if((a['figure_caption']??'').toString().isEmpty ||
                  !(a['thumbnail']??'').toString().startsWith('https://'))
                  const Icon(Icons.article_outlined,color:PracticeDailyVisualTheme.mint,size:20),
                const SizedBox(width:10),
                Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text((a['title']??'Article médical').toString(),maxLines:3,
                    overflow:TextOverflow.ellipsis,style:const TextStyle(
                      color:PracticeDailyVisualTheme.text,fontSize:12.5,fontWeight:FontWeight.w700)),
                  const SizedBox(height:4),
                  Text((a['summary']??'Consulter les figures et les légendes').toString(),
                    maxLines:2,style:const TextStyle(
                      color:PracticeDailyVisualTheme.muted,fontSize:11)),
                  const SizedBox(height:4),
                  const Text('Consulter l’article source et ses figures ↗',style:TextStyle(
                    color:PracticeDailyVisualTheme.mint,fontSize:11)),
                ])),
              ])),
          ),
        )),
      ],
      if(!busy&&visibleImages.isEmpty)...[
        const SizedBox(height:12),
        Text(message??'Aucun aperçu médical direct pour ce sujet. Les articles et banques d’imagerie restent accessibles ci-dessous.',
          style:const TextStyle(color:PracticeDailyVisualTheme.muted,fontSize:12)),
        TextButton.icon(onPressed:()=>_fetch(refresh:true),
          icon:const Icon(Icons.refresh_rounded,size:17),
          label:const Text('Relancer la recherche gratuite d’images')),
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

class _MedicalZoomViewer extends StatefulWidget {
  const _MedicalZoomViewer({required this.bytes,required this.source,
    required this.title,required this.credits});
  final Uint8List bytes;
  final String source,title,credits;
  @override State<_MedicalZoomViewer> createState()=>_MedicalZoomViewerState();
}
class _MedicalZoomViewerState extends State<_MedicalZoomViewer> {
  final TransformationController controller=TransformationController();
  @override void dispose(){controller.dispose();super.dispose();}
  void zoom(double factor){
    final value=(controller.value.getMaxScaleOnAxis()*factor).clamp(.7,8.0);
    setState(()=>controller.value=Matrix4.identity()..scale(value));
  }
  void reset()=>setState(()=>controller.value=Matrix4.identity());
  void openSource(){
    final uri=Uri.tryParse(widget.source);
    if(uri?.scheme=='https')launchUrl(uri!,mode:LaunchMode.externalApplication);
  }
  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:const Color(0xFF03080F),
    appBar:AppBar(
      title:const Text('Visionneuse médicale'),
      backgroundColor:PracticeDailyVisualTheme.background,
      actions:[IconButton(tooltip:'Voir le document source',
        onPressed:openSource,icon:const Icon(Icons.open_in_new_rounded))],
    ),
    body:SafeArea(child:Column(children:[
      Expanded(child:InteractiveViewer(
        transformationController:controller,
        minScale:.7,maxScale:8,
        boundaryMargin:const EdgeInsets.all(120),
        panEnabled:true,scaleEnabled:true,
        child:Center(child:Image.memory(widget.bytes,
          fit:BoxFit.contain,
          errorBuilder:(_,__,___)=>Column(
            mainAxisAlignment:MainAxisAlignment.center,
            children:[
              const Icon(Icons.broken_image_outlined,
                color:Colors.white70,size:36),
              const SizedBox(height:8),
              const Text('Image externe indisponible',
                style:TextStyle(color:Colors.white70)),
              TextButton(onPressed:openSource,
                child:const Text('Ouvrir le site source')),
            ]),
        )),
      )),
      Row(mainAxisAlignment:MainAxisAlignment.center,children:[
        IconButton(tooltip:'Zoom arrière',onPressed:()=>zoom(.72),
          icon:const Icon(Icons.remove_circle_outline,color:Colors.white)),
        IconButton(tooltip:'Réinitialiser le zoom',onPressed:reset,
          icon:const Icon(Icons.center_focus_strong,color:Colors.white)),
        IconButton(tooltip:'Zoom avant',onPressed:()=>zoom(1.45),
          icon:const Icon(Icons.add_circle_outline,color:Colors.white)),
      ]),
      Container(
        width:double.infinity,color:const Color(0xFF11283A),
        padding:const EdgeInsets.all(15),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(widget.title,style:const TextStyle(
            color:Colors.white,fontWeight:FontWeight.w800)),
          const SizedBox(height:4),
          Text(widget.credits,style:const TextStyle(
            color:Colors.white70,fontSize:12)),
          const Text('Pincer pour zoomer · Glisser · Commandes + / −',
            style:TextStyle(color:Colors.white54,fontSize:11)),
        ]),
      ),
    ])),
  );
}
