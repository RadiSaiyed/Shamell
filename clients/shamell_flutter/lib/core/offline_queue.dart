import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';

class OfflineTask {
  final String id;
  final String method;
  final String url;
  final Map<String, String> headers;
  final String body;
  final String tag;
  final int createdAt;
  int retries;
  int nextAt = 0;
  OfflineTask({
    required this.id,
    required this.method,
    required this.url,
    required this.headers,
    required this.body,
    required this.tag,
    required this.createdAt,
    this.retries = 0,
    int? nextAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'method': method,
    'url': url,
    'headers': headers,
    'body': body,
    'tag': tag,
    'createdAt': createdAt,
    'retries': retries,
    'nextAt': nextAt,
  };
  static OfflineTask fromJson(Map<String, dynamic> j) => OfflineTask(
    id: j['id'],
    method: j['method'],
    url: j['url'],
    headers: (j['headers'] as Map).map((k,v)=> MapEntry(k.toString(), v.toString())),
    body: j['body'],
    tag: j['tag'] ?? 'misc',
    createdAt: j['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
    retries: j['retries'] ?? 0,
    nextAt: j['nextAt'] ?? 0,
  );
}

class OfflineQueue {
  static final _key = 'offline_queue_v1';
  static List<OfflineTask> _items = [];
  static bool _flushing = false;

  static Future<void> init() async {
    try{
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getStringList(_key) ?? [];
      _items = raw.map((s)=> OfflineTask.fromJson(jsonDecode(s))).toList(growable: true);
    }catch(_){ _items = []; }
  }

  static List<OfflineTask> pending({String? tag}){
    return List.unmodifiable(tag==null? _items : _items.where((t)=> t.tag==tag));
  }

  static Future<void> _persist() async {
    try{
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(_key, _items.map((t)=> jsonEncode(t.toJson())).toList());
    }catch(_){ }
  }

  static Future<void> enqueue(OfflineTask t) async {
    // initialize nextAt to now for first attempt
    t.nextAt = DateTime.now().millisecondsSinceEpoch;
    _items.add(t);
    await _persist();
  }

  static Future<int> flush() async {
    if(_flushing || _items.isEmpty) return 0;
    _flushing = true;
    int delivered = 0;
    try{
      // Simple sequential flush
      for(int i=0;i<_items.length;){
        final t = _items[i];
        final now = DateTime.now().millisecondsSinceEpoch;
        if(t.nextAt > now){ i += 1; continue; }
        try{
          http.Response r;
          if(t.method.toUpperCase()=='POST'){
            r = await http.post(Uri.parse(t.url), headers: t.headers, body: t.body).timeout(const Duration(seconds: 10));
          } else if(t.method.toUpperCase()=='PUT'){
            r = await http.put(Uri.parse(t.url), headers: t.headers, body: t.body).timeout(const Duration(seconds: 10));
          } else {
            r = await http.post(Uri.parse(t.url), headers: t.headers, body: t.body).timeout(const Duration(seconds: 10));
          }
          if(r.statusCode>=200 && r.statusCode<300){
            _items.removeAt(i); delivered++; await _persist(); continue;
          }
        }catch(_){ }
        // failed
        t.retries += 1;
        if(t.retries>10){ _items.removeAt(i); await _persist(); continue; }
        // exponential backoff with jitter (base 5s, cap 60s)
        final base = 5000 * (1 << (t.retries-1));
        final cap = 60000;
        final jitter = math.Random().nextInt(3000);
        final delay = math.min(base, cap) + jitter;
        t.nextAt = now + delay;
        await _persist();
        i += 1;
      }
    } finally {
      _flushing = false;
    }
    return delivered;
  }
  static Future<int> flushTag(String tag) async {
    final matches = _items.where((t)=> t.tag==tag).map((t)=> t.id).toList();
    int ok=0; for(final id in matches){ final r= await flushOne(id); if(r) ok++; }
    return ok;
  }
  static Future<int> removeTag(String tag) async {
    final before = _items.length; _items.removeWhere((t)=> t.tag==tag); await _persist(); return before - _items.length;
  }

  static Future<bool> flushOne(String id) async {
    final idx = _items.indexWhere((t)=> t.id == id);
    if(idx<0) return false;
    final t = _items[idx];
    try{
      http.Response r;
      if(t.method.toUpperCase()=='POST'){
        r = await http.post(Uri.parse(t.url), headers: t.headers, body: t.body).timeout(const Duration(seconds: 10));
      } else if(t.method.toUpperCase()=='PUT'){
        r = await http.put(Uri.parse(t.url), headers: t.headers, body: t.body).timeout(const Duration(seconds: 10));
      } else {
        r = await http.post(Uri.parse(t.url), headers: t.headers, body: t.body).timeout(const Duration(seconds: 10));
      }
      if(r.statusCode>=200 && r.statusCode<300){ _items.removeAt(idx); await _persist(); return true; }
    }catch(_){ }
    // schedule retry soon
    final now = DateTime.now().millisecondsSinceEpoch;
    t.retries += 1; t.nextAt = now + 5000; await _persist();
    return false;
  }

  static Future<bool> remove(String id) async {
    final idx = _items.indexWhere((t)=> t.id == id);
    if(idx<0) return false;
    _items.removeAt(idx); await _persist(); return true;
  }
}
