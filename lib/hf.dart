import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

class HfModel {
  final String id;
  final int downloads, likes;
  HfModel(this.id, this.downloads, this.likes);
}

class HfFile {
  final String path;
  final int size;
  HfFile(this.path, this.size);
  String get name => path.split('/').last;
  bool get recommended => name.toUpperCase().contains('Q4_K_M');
}

class Hf {
  static Future<List<HfModel>> search(String q) async {
    final uri = Uri.https('huggingface.co', '/api/models', {
      'search': q,
      'filter': 'gguf',
      'sort': 'downloads',
      'direction': '-1',
      'limit': '40',
    });
    final r = await http.get(uri);
    if (r.statusCode != 200) throw 'Hugging Face error ${r.statusCode}';
    return (jsonDecode(r.body) as List)
        .map((m) => HfModel(m['id'], m['downloads'] ?? 0, m['likes'] ?? 0))
        .toList();
  }

  static final _split = RegExp(r'-\d{5}-of-\d{5}\.gguf$');

  static Future<List<HfFile>> files(String id) async {
    final r = await http.get(Uri.parse('https://huggingface.co/api/models/$id/tree/main?recursive=true'));
    if (r.statusCode != 200) throw 'Hugging Face error ${r.statusCode}';
    final out = <HfFile>[];
    for (final f in jsonDecode(r.body) as List) {
      final p = f['path'] as String;
      if (f['type'] != 'file' || !p.endsWith('.gguf')) continue;
      if (p.toLowerCase().contains('mmproj') || _split.hasMatch(p)) continue;
      out.add(HfFile(p, f['size'] ?? 0));
    }
    out.sort((a, b) => a.size.compareTo(b.size));
    return out;
  }

  static Future<File> download(String id, HfFile f, Directory dir, void Function(double) progress,
      {CancelToken? cancel}) async {
    final dest = File('${dir.path}/${id.replaceAll('/', '__')}__${f.name}');
    final part = '${dest.path}.part';
    await Dio().download('https://huggingface.co/$id/resolve/main/${f.path}', part,
        cancelToken: cancel,
        onReceiveProgress: (n, t) => progress(f.size > 0 ? n / f.size : (t > 0 ? n / t : 0)));
    return File(part).rename(dest.path);
  }
}

String fmtSize(int b) => b >= 1 << 30
    ? '${(b / (1 << 30)).toStringAsFixed(1)} GB'
    : '${(b / (1 << 20)).toStringAsFixed(0)} MB';
