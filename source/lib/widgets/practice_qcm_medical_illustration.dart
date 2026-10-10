import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../config/backend_config.dart';
import '../services/supabase_backend_service.dart';
import '../services/practice_google_image_cache.dart';

/// Public Practice QCM image contract: used across daily course challenges,
/// progressive fictitious cases, published cases and previewed QCM sets.
/// No image bytes or image URLs are written into the application's database.
class PracticeQcmImageMetadata {
  static const marker = '§IMAGE_SPEC§';
  static Map<String, dynamic>? fromCorrection(String correction) {
    final i = correction.indexOf(marker);
    if (i < 0) return null;
    var tail = correction.substring(i + marker.length).trim();
    for (final sep in ['§IMAGES§', '§SOURCES§']) {
      final end = tail.indexOf(sep);
      if (end >= 0) tail = tail.substring(0, end).trim();
    }
    try {
      final decoded = jsonDecode(tail);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      /* Historic corrections remain readable. */
    }
    return null;
  }

  static String visibleText(String correction) {
    var display = correction.split('§SOURCES§').first;
    display = display.split('§IMAGE_SPEC§').first;
    display = display.split('§IMAGES§').first;
    return display.trim();
  }

  static bool containsVisual(String correction) =>
      correction.contains('§IMAGE_SPEC§') || correction.contains('§IMAGES§');

  /// Retroactive enrichment: existing QCMs do not need to be regenerated.
  /// The patient/case title and question are used to formulate the request,
  /// never the obsolete URL itself. Only explicit image-oriented lessons are
  /// searched; all other old questions keep their existing text.
  static Map<String, dynamic>? legacyRequest(
    String correction,
    String question, {
    String context = '',
  }) {
    final visualMarker = containsVisual(correction);
    final cleanCorrection = visibleText(correction);
    final readable = '$question $cleanCorrection'.toLowerCase();
    final hasVisualIntent = RegExp(
      r'\b(irm|mri|tdm|scanner|ct scan|radiograph|rx|echograph|ultrasound|'
      r'diffusion|dwi|adc|t2|t1|image|imagerie|anatom|mesorect|sphincter|'
      r'séquence|sequence|échograph|radiolog)\b',
      caseSensitive: false,
    ).hasMatch(readable);
    if (!visualMarker && !hasVisualIntent) return null;
    var oldTitle = '';
    final idx = correction.indexOf('§IMAGES§');
    if (idx >= 0) {
      final line = correction
          .substring(idx + '§IMAGES§'.length)
          .trim()
          .split('\n')
          .first;
      oldTitle = line.split('|||').first.trim();
    }
    final focused = '$oldTitle $question'.toLowerCase();
    final isAnatomy =
        RegExp(r'anatom|mésorect|mesorect|sphinct|levator|rapport')
            .hasMatch(focused) &&
        !RegExp(r'\b(irm|mri|tdm|scanner|dwi|adc|t1|t2|t3|t4|diffusion)\b')
            .hasMatch(focused);
    final isScan = RegExp(
      r'\b(irm|mri|tdm|scanner|ct|radiograph|echograph|'
      r'ultrasound|t2|t1|dwi|adc|diffusion)\b',
      caseSensitive: false,
    ).hasMatch(focused);
    final contextShort = context.trim().length > 85
        ? context.trim().substring(0, 85)
        : context.trim();
    final descriptor = [
      if (contextShort.isNotEmpty) contextShort,
      if (oldTitle.isNotEmpty) oldTitle,
      if (question.trim().isNotEmpty) question.trim(),
    ].join(' — ').trim();
    if (descriptor.isEmpty) return null;
    final text = descriptor.length > 280
        ? descriptor.substring(0, 280)
        : descriptor;
    return <String, dynamic>{
      'query': text,
      'purpose': oldTitle.isNotEmpty
          ? oldTitle
          : 'Illustration médicale correspondant au QCM',
      'modality': isScan ? 'medical radiology' : 'anatomical illustration',
      'image_type': isAnatomy
          ? 'anatomical_diagram'
          : isScan
          ? 'radiology_scan'
          : 'operative_diagram',
      'anatomy': contextShort,
      'plane': 'not_applicable',
      'required_features': <String>[],
      'excluded_features': <String>[
        'book cover',
        'annual report',
        'wrong organ',
      ],
    };
  }
}

/// Image preview fetched only when a QCM explanation is visible.
/// It is deliberately separate from the case's answer/scoring logic.
class PracticeQcmMedicalIllustration extends StatefulWidget {
  const PracticeQcmMedicalIllustration({
    super.key,
    required this.correction,
    this.question = '',
    this.caseContext = '',
  });
  final String correction, question, caseContext;
  @override
  State<PracticeQcmMedicalIllustration> createState() =>
      _PracticeQcmMedicalIllustrationState();
}

class _PracticeQcmMedicalIllustrationState
    extends State<PracticeQcmMedicalIllustration> {
  List<Map<String, dynamic>> _found = [];
  List<Map<String, dynamic>> _googleImages = [];
  String _googleKey='';
  bool _googleCached=false, _googleEnabled=false, _searchingGoogle=false;
  String? _googleMessage;
  int _googleCount=0;
  List<Map<String, dynamic>> _links = [];
  List<Map<String, dynamic>> _articles = [];
  final Map<String, Uint8List> _bytes = {};
  final Set<String> _failed = {};
  bool _busy = false;
  String? _message;
  int _version = 0;

  List<Map<String, dynamic>> _records(dynamic x) => x is List
      ? x.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList()
      : <Map<String, dynamic>>[];

  Map<String, dynamic>? get _request =>
      PracticeQcmImageMetadata.fromCorrection(widget.correction) ??
      PracticeQcmImageMetadata.legacyRequest(
        widget.correction,
        widget.question,
        context: widget.caseContext,
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PracticeQcmMedicalIllustration old) {
    super.didUpdateWidget(old);
    if (old.correction != widget.correction ||
        old.question != widget.question ||
        old.caseContext != widget.caseContext) {
      _load();
    }
  }

  Map<String, String> _auth() {
    final token =
        SupabaseBackendService.instance.client.auth.currentSession?.accessToken;
    return <String, String>{
      'apikey': BackendConfig.supabasePublishableKey,
      if (token != null) 'authorization': 'Bearer ' + token,
    };
  }

  Future<void> _load() async {
    final request = _request;
    final id = ++_version;
    if (request == null ||
        request['image_type'] == 'none' ||
        (request['query'] ?? '').toString().trim().isEmpty) {
      if (mounted)
        setState(() {
          _found = [];
          _busy = false;
          _message = null;
        });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
      _found = [];
      _googleImages=[];
      _googleCached=false;
      _googleKey='';
      _googleEnabled=false;
      _googleMessage=null;
      _links = [];
      _articles = [];
      _bytes.clear();
      _failed.clear();
    });
    try {
      final response = await SupabaseBackendService.instance.client.functions
          .invoke(
            'practice-medical-images',
            body: {'action': 'images', 'image_request': request},
          );
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      if (!mounted || id != _version) return;
      if (data.containsKey('error'))
        throw StateError('image lookup unavailable');
      final images = _records(data['images']).take(4).toList();
      setState(() {
        _found = images;
        _links = _records(data['medical_searches']);
        _articles = _records(data['article_previews']);
      });
      for (final image in images) {
        if (!mounted || id != _version) break;
        final raw = (image['thumbnail'] ?? '').toString();
        await _getBytes(raw, id);
      }
      await _restoreGoogle(data,id);
      for (final article in _articles.take(2)) {
        if (!mounted || id != _version) break;
        final thumb = (article['thumbnail'] ?? '').toString();
        if (thumb.startsWith('https://') &&
            (article['figure_caption']??'').toString().isNotEmpty) await _getBytes(thumb,id);
      }
    } catch (_) {
      if (mounted && id == _version)
        setState(() {
          _message = 'Images indisponibles pour cette question.';
        });
    } finally {
      if (mounted && id == _version) setState(() => _busy = false);
    }
  }

  String get _userId =>
      SupabaseBackendService.instance.client.auth.currentUser?.id??'';
  Future<void> _restoreGoogle(Map<String,dynamic> result,int requestVersion)async{
    final key=(result['google_cache_key']??'').toString();
    final enabled=result['google_images_available']==true;
    final user=_userId;
    List<Map<String,dynamic>>? fromCache;
    int count=0;
    try{
      if(key.isNotEmpty&&user.isNotEmpty){
        fromCache=await PracticeGoogleImageCache.read(userId:user,googleKey:key);
        count=await PracticeGoogleImageCache.localCount(user);
      }
    }catch(_){/* Preserve free image gallery. */}
    if(!mounted||requestVersion!=_version)return;
    setState((){
      _googleKey=key;
      _googleEnabled=enabled;
      _googleCached=fromCache!=null;
      _googleImages=fromCache??[];
      _googleCount=count;
      _googleMessage=fromCache!=null&&fromCache.isEmpty
        ?'Aucun résultat Google en cache (recherche conservée 3 jours).':null;
    });
    for(final image in _googleImages){
      if(!mounted||requestVersion!=_version)break;
      await _getBytes((image['thumbnail']??'').toString(),requestVersion);
    }
  }
  Future<void> _searchGoogle()async{
    if(_searchingGoogle||_googleCached||!_googleEnabled||_googleKey.isEmpty)return;
    final user=_userId;
    final request=_request;
    if(user.isEmpty||request==null)return;
    final reqVersion=_version;
    setState(()=>_searchingGoogle=true);
    try{
      final count=await PracticeGoogleImageCache.localCount(user);
      if(count>=PracticeGoogleImageCache.maxPerDeviceMonth){
        if(mounted)setState(()=>_googleMessage='Limite de prudence locale atteinte (240 ce mois-ci).');
        return;
      }
      await PracticeGoogleImageCache.countAttempt(user);
      final response=await SupabaseBackendService.instance.client.functions.invoke(
        'practice-medical-images',
        body:{'action':'google_images','image_request':request},
      );
      final data=response.data is Map
        ?Map<String,dynamic>.from(response.data as Map):<String,dynamic>{};
      if(data['error']!=null||data['google_enabled']!=true||data['search_executed']!=true)
        throw StateError('SerpApi unavailable');
      final results=_records(data['images']).take(8).toList();
      await PracticeGoogleImageCache.write(userId:user,
        googleKey:_googleKey,images:results);
      if(!mounted||reqVersion!=_version)return;
      setState((){
        _googleImages=results;
        _googleCached=true;
        _googleCount=count+1;
        _googleMessage=results.isEmpty
          ?'Recherche Google sans résultat médical : conservée 3 jours.'
          :'Résultats Google réutilisables 30 jours sans nouvelle requête.';
      });
      for(final image in results){
        if(!mounted||reqVersion!=_version)break;
        await _getBytes((image['thumbnail']??'').toString(),reqVersion);
      }
    }catch(_){
      if(mounted&&reqVersion==_version)setState(()=>
        _googleMessage='Recherche Google indisponible. Aucun nouvel appel automatique.');
    }finally{
      if(mounted)setState(()=>_searchingGoogle=false);
    }
  }

  Future<void> _getBytes(String raw, int requestVersion) async {
    if (raw.isEmpty || _bytes.containsKey(raw) || _failed.contains(raw)) return;
    final url = Uri.parse(
      BackendConfig.supabaseUrl +
          '/functions/v1/practice-medical-images'
              '?asset=' +
          Uri.encodeComponent(raw),
    );
    try {
      final result = await http
          .get(url, headers: _auth())
          .timeout(const Duration(seconds: 18));
      if (!mounted || requestVersion != _version) return;
      final type = (result.headers['content-type'] ?? '').toLowerCase();
      if (result.statusCode == 200 &&
          type.startsWith('image/') &&
          result.bodyBytes.isNotEmpty &&
          result.bodyBytes.lengthInBytes <= 12 * 1024 * 1024) {
        setState(() => _bytes[raw] = result.bodyBytes);
      } else {
        setState(() => _failed.add(raw));
      }
    } catch (_) {
      if (mounted && requestVersion == _version)
        setState(() => _failed.add(raw));
    }
  }

  Future<void> _open(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri?.scheme == 'https')
      await launchUrl(uri!, mode: LaunchMode.externalApplication);
  }

  Future<void> _zoom(Map<String, dynamic> image, Uint8List initial) async {
    final full = (image['full'] ?? '').toString();
    Uint8List data = initial;
    if (full.startsWith('https://') && full != (image['thumbnail'] ?? '')) {
      final request = ++_version;
      await _getBytes(full, request);
      data = _bytes[full] ?? initial;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _QcmImageViewer(
          bytes: data,
          title: (image['title'] ?? 'Image médicale').toString(),
          credits: '${image['creator'] ?? ''} · ${image['license'] ?? ''}',
          source: (image['source'] ?? '').toString(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_request == null) return const SizedBox.shrink();
    final live = [..._found,..._googleImages]
        .where((x) => _bytes.containsKey((x['thumbnail'] ?? '').toString()))
        .toList();
    return Container(
      margin: const EdgeInsets.only(top: 14, bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0C2035),
        border: Border.all(color: const Color(0xFF285574)),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(
                Icons.image_search_rounded,
                size: 19,
                color: Color(0xFF4FDBA8),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'IMAGERIE PÉDAGOGIQUE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Aperçus externes · toucher pour zoomer',
            style: TextStyle(color: Color(0xFFB6CDDD), fontSize: 11),
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(color: Color(0xFF4FDBA8)),
          ],
          if (live.isNotEmpty) ...[
            const SizedBox(height: 11),
            SizedBox(
              height: 170,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: live.length,
                separatorBuilder: (_, __) => const SizedBox(width: 9),
                itemBuilder: (context, i) {
                  final item = live[i];
                  final data = _bytes[(item['thumbnail'] ?? '').toString()]!;
                  return InkWell(
                    key: ValueKey('qcm-image-' + i.toString()),
                    onTap: () => _zoom(item, data),
                    child: SizedBox(
                      width: 185,
                      child: Column(
                        children: [
                          Expanded(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.memory(
                                    data,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                                const Positioned(
                                  top: 6,
                                  right: 6,
                                  child: Icon(
                                    Icons.zoom_in_rounded,
                                    color: Colors.white,
                                    size: 23,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            (item['title'] ?? 'Imagerie externe').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          if(_googleKey.isNotEmpty)...[
            const SizedBox(height:11),
            if(_googleImages.isNotEmpty)
              const Text('Google Images — résultats mémorisés sur cet appareil',
                style:TextStyle(color:Color(0xFF4FDBA8),fontSize:11,
                  fontWeight:FontWeight.w700)),
            if(!_googleCached&&_googleEnabled)
              OutlinedButton.icon(
                onPressed:_searchingGoogle?null:_searchGoogle,
                icon:_searchingGoogle
                  ?const SizedBox(width:15,height:15,
                      child:CircularProgressIndicator(strokeWidth:2))
                  :const Icon(Icons.search,size:16),
                label:Text(_searchingGoogle
                  ?'Recherche Google en cours…'
                  :'Rechercher avec Google (1 crédit SerpApi maximum)'),
              ),
            if(_googleCached&&_googleImages.isNotEmpty)
              const Text('Cache disponible : aucun appel SerpApi supplémentaire.',
                style:TextStyle(color:Color(0xFFB6CDDD),fontSize:11)),
            if(_googleMessage!=null)
              Text(_googleMessage!,style:const TextStyle(
                color:Color(0xFFB6CDDD),fontSize:11)),
            Text('Quota prudent local : $_googleCount/240 recherches déclenchées ce mois-ci (cet appareil).',
              style:const TextStyle(color:Color(0xFF90ADBC),fontSize:10)),
          ],
          if(_articles.isNotEmpty)...[
            const SizedBox(height:12),
            const Text('Articles sources — figures à consulter',
              style:TextStyle(color:Color(0xFF4FDBA8),fontWeight:FontWeight.w800,fontSize:12)),
            const SizedBox(height:8),
            for(final article in _articles.take(3))
              Container(
                margin:const EdgeInsets.only(bottom:8),
                decoration:BoxDecoration(
                  color:const Color(0xFF173049),
                  borderRadius:BorderRadius.circular(12)),
                child:InkWell(
                  key:ValueKey('qcm-article-'+(article['source']??'').toString()),
                  borderRadius:BorderRadius.circular(12),
                  onTap:()=>_open((article['figure_page']??article['source']??'').toString()),
                  child:Padding(
                    padding:const EdgeInsets.all(11),
                    child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
                      if((article['figure_caption']??'').toString().isNotEmpty &&
                        _bytes.containsKey((article['thumbnail']??'').toString()))
                        ClipRRect(borderRadius:BorderRadius.circular(8),
                          child:Image.memory(_bytes[(article['thumbnail']??'').toString()]!,
                            width:60,height:65,fit:BoxFit.contain)),
                      if((article['figure_caption']??'').toString().isEmpty ||
                        !_bytes.containsKey((article['thumbnail']??'').toString()))
                        const Icon(Icons.article_outlined,color:Color(0xFF4FDBA8)),
                      const SizedBox(width:9),
                      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                        Text((article['title']??'Article médical').toString(),
                          maxLines:3,overflow:TextOverflow.ellipsis,
                          style:const TextStyle(color:Colors.white,fontSize:12,fontWeight:FontWeight.w700)),
                        const SizedBox(height:5),
                        Text((article['summary']??'Figures sur le site source').toString(),
                          maxLines:2,style:const TextStyle(
                            color:Color(0xFFB6CDDD),fontSize:11)),
                        const SizedBox(height:4),
                        const Text('Ouvrir l’article source et les figures ↗',style:TextStyle(
                          color:Color(0xFF4FDBA8),fontSize:11)),
                      ])),
                    ]),
                  ),
                ),
              ),
          ],
          if (!_busy && live.isEmpty && _articles.isEmpty) ...[
            const SizedBox(height: 11),
            Text(
              _message ?? 'Aucun aperçu médical correspondant et accessible.',
              style: const TextStyle(color: Color(0xFFB6CDDD), fontSize: 11),
            ),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Réessayer'),
            ),
          ],
          if (_links.isNotEmpty)
            Wrap(
              spacing: 4,
              children: [
                for (final link in _links)
                  TextButton.icon(
                    onPressed: () => _open((link['source'] ?? '').toString()),
                    icon: const Icon(Icons.open_in_new, size: 13),
                    label: Text(
                      (link['title'] ?? 'Source').toString(),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
              ],
            ),
          const Text(
            'Images représentatives, jamais celles d’un patient fictif.',
            style: TextStyle(color: Color(0xFF90ADBC), fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _QcmImageViewer extends StatefulWidget {
  const _QcmImageViewer({
    required this.bytes,
    required this.title,
    required this.credits,
    required this.source,
  });
  final Uint8List bytes;
  final String title, credits, source;
  @override
  State<_QcmImageViewer> createState() => _QcmImageViewerState();
}

class _QcmImageViewerState extends State<_QcmImageViewer> {
  final TransformationController _matrix = TransformationController();
  @override
  void dispose() {
    _matrix.dispose();
    super.dispose();
  }

  void _scale(double ratio) {
    final level = (_matrix.value.getMaxScaleOnAxis() * ratio).clamp(.7, 8.0);
    setState(() => _matrix.value = Matrix4.identity()..scale(level));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF020A12),
    appBar: AppBar(
      title: const Text('Visionneuse QCM'),
      backgroundColor: const Color(0xFF0E2030),
      actions: [
        IconButton(
          tooltip: 'Source originale',
          onPressed: () {
            final url = Uri.tryParse(widget.source);
            if (url?.scheme == 'https')
              launchUrl(url!, mode: LaunchMode.externalApplication);
          },
          icon: const Icon(Icons.open_in_new),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              transformationController: _matrix,
              minScale: .7,
              maxScale: 8,
              boundaryMargin: const EdgeInsets.all(90),
              child: Center(
                child: Image.memory(widget.bytes, fit: BoxFit.contain),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => _scale(.7),
                tooltip: 'Zoom arrière',
                icon: const Icon(
                  Icons.remove_circle_outline,
                  color: Colors.white,
                ),
              ),
              IconButton(
                onPressed: () =>
                    setState(() => _matrix.value = Matrix4.identity()),
                tooltip: 'Réinitialiser',
                icon: const Icon(
                  Icons.center_focus_strong,
                  color: Colors.white,
                ),
              ),
              IconButton(
                onPressed: () => _scale(1.4),
                tooltip: 'Zoom avant',
                icon: const Icon(Icons.add_circle_outline, color: Colors.white),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  widget.credits,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
