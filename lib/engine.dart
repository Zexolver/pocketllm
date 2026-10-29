import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;

// Runs llama.cpp's llama-server (shipped as libllama_server.so) as a child process.
class Engine extends ChangeNotifier {
  Process? _proc;
  String? loadedModel;
  bool ready = false, starting = false;
  int port = 8080;
  bool lan = false;
  int ctx = 4096;
  String apiKey = '';
  final log = StringBuffer();

  bool get running => _proc != null;

  Future<String> _binary() async {
    // nativeLibraryDir isn't exposed to Dart; recover it from the mapped libflutter.so.
    final maps = await File('/proc/self/maps').readAsLines();
    final l = maps.firstWhere((l) => l.contains('libflutter.so'));
    final dir = File(l.substring(l.indexOf('/'))).parent.path;
    return '$dir/libllama_server.so';
  }

  Future<void> start(String modelPath) async {
    await stop();
    starting = true;
    log.clear();
    notifyListeners();
    try {
      await FlutterForegroundTask.startService(
        notificationTitle: 'PocketLLM',
        notificationText: 'Model server running on port $port',
      );
      final args = [
        '-m', modelPath,
        '--host', lan ? '0.0.0.0' : '127.0.0.1',
        '--port', '$port',
        '-c', '$ctx',
        '--jinja',
        if (apiKey.isNotEmpty) ...['--api-key', apiKey],
      ];
      final p = await Process.start(await _binary(), args);
      _proc = p;
      loadedModel = modelPath;
      void add(List<int> d) {
        log.write(utf8.decode(d, allowMalformed: true));
        if (log.length > 20000) {
          final s = log.toString();
          log..clear()..write(s.substring(s.length - 10000));
        }
        notifyListeners();
      }
      p.stdout.listen(add);
      p.stderr.listen(add);
      p.exitCode.then((c) {
        if (_proc == p) {
          _proc = null;
          ready = false;
          loadedModel = null;
          log.write('\n[engine exited: $c]');
          FlutterForegroundTask.stopService();
          notifyListeners();
        }
      });
      for (var i = 0; i < 300 && _proc == p; i++) {
        try {
          final r = await http.get(Uri.parse('http://127.0.0.1:$port/health'));
          if (r.statusCode == 200) {
            ready = true;
            break;
          }
        } catch (_) {}
        await Future.delayed(const Duration(seconds: 1));
      }
    } catch (e) {
      log.write('\n[start failed: $e]');
    } finally {
      starting = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    final p = _proc;
    _proc = null;
    ready = false;
    loadedModel = null;
    p?.kill();
    await FlutterForegroundTask.stopService();
    notifyListeners();
  }

  Map<String, String> get _headers =>
      {'Content-Type': 'application/json', if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey'};

  Stream<String> chat(List<Map<String, String>> messages, {double temp = 0.8}) async* {
    final client = http.Client();
    try {
      final req = http.Request('POST', Uri.parse('http://127.0.0.1:$port/v1/chat/completions'))
        ..headers.addAll(_headers)
        ..body = jsonEncode({'messages': messages, 'stream': true, 'temperature': temp});
      final res = await client.send(req);
      if (res.statusCode != 200) throw 'Server error ${res.statusCode}';
      await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!line.startsWith('data: ') || line.contains('[DONE]')) continue;
        final d = jsonDecode(line.substring(6))['choices'][0]['delta']['content'];
        if (d != null) yield d as String;
      }
    } finally {
      client.close();
    }
  }
}
