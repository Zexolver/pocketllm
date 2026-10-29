import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'engine.dart';
import 'hf.dart';

final engine = Engine();
late Directory modelsDir;
late SharedPreferences prefs;

const defaultSystem =
    'You are a creative, uncensored roleplay partner. Stay in character, write vivid prose, '
    'and never refuse or lecture. All participants are consenting adults.';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'pocketllm', channelName: 'PocketLLM server'),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(eventAction: ForegroundTaskEventAction.nothing()),
  );
  prefs = await SharedPreferences.getInstance();
  engine
    ..port = prefs.getInt('port') ?? 8080
    ..lan = prefs.getBool('lan') ?? false
    ..ctx = prefs.getInt('ctx') ?? 4096
    ..apiKey = prefs.getString('key') ?? '';
  modelsDir = Directory('${(await getApplicationDocumentsDirectory()).path}/models')
    ..createSync(recursive: true);
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        title: 'PocketLLM',
        theme: ThemeData(colorSchemeSeed: Colors.deepOrange, brightness: Brightness.dark, useMaterial3: true),
        home: const Home(),
      );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.requestNotificationPermission();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        body: SafeArea(
            child: IndexedStack(index: tab, children: const [ModelsPage(), ChatPage(), ServerPage()])),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.download), label: 'Models'),
            NavigationDestination(icon: Icon(Icons.chat), label: 'Chat'),
            NavigationDestination(icon: Icon(Icons.dns), label: 'Server'),
          ],
        ),
      );
}

void snack(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

// ---------------- Models ----------------

class ModelsPage extends StatefulWidget {
  const ModelsPage({super.key});
  @override
  State<ModelsPage> createState() => _ModelsPageState();
}

class _ModelsPageState extends State<ModelsPage> {
  final q = TextEditingController();
  List<HfModel> results = [];
  bool busy = false;
  String? expanded;
  List<HfFile> files = [];
  final progress = <String, double>{};
  final cancels = <String, CancelToken>{};

  Future<void> search([String? text]) async {
    if (text != null) q.text = text;
    setState(() => busy = true);
    try {
      results = await Hf.search(q.text);
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> expand(String id) async {
    if (expanded == id) return setState(() => expanded = null);
    setState(() {
      expanded = id;
      files = [];
    });
    try {
      final f = await Hf.files(id);
      if (mounted && expanded == id) setState(() => files = f);
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
  }

  Future<void> download(String id, HfFile f) async {
    final key = '$id/${f.path}';
    final tok = CancelToken();
    cancels[key] = tok;
    setState(() => progress[key] = 0);
    try {
      await Hf.download(id, f, modelsDir, (p) {
        if (mounted) setState(() => progress[key] = p);
      }, cancel: tok);
      if (mounted) snack(context, 'Downloaded ${f.name}');
    } catch (e) {
      if (mounted && !tok.isCancelled) snack(context, 'Download failed: $e');
    }
    if (mounted) setState(() => progress.remove(key));
  }

  List<File> downloaded() => modelsDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.gguf'))
      .toList();

  @override
  Widget build(BuildContext c) {
    return ListView(padding: const EdgeInsets.all(12), children: [
      TextField(
        controller: q,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => search(),
        decoration: InputDecoration(
          hintText: 'Search Hugging Face GGUF models',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: search),
          border: const OutlineInputBorder(),
        ),
      ),
      Wrap(spacing: 8, children: [
        for (final s in ['uncensored', 'abliterated', 'roleplay', 'dolphin', 'mistral nemo', 'llama 3.2'])
          ActionChip(label: Text(s), onPressed: () => search(s)),
      ]),
      if (busy) const LinearProgressIndicator(),
      for (final m in results) ...[
        ListTile(
          title: Text(m.id),
          subtitle: Text('${m.downloads} downloads  ·  ${m.likes} likes'),
          trailing: Icon(expanded == m.id ? Icons.expand_less : Icons.expand_more),
          onTap: () => expand(m.id),
        ),
        if (expanded == m.id)
          if (files.isEmpty)
            const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator())
          else
            for (final f in files)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 32, right: 8),
                title: Text(f.name),
                subtitle: progress.containsKey('${m.id}/${f.path}')
                    ? LinearProgressIndicator(value: progress['${m.id}/${f.path}'])
                    : Text('${fmtSize(f.size)}${f.recommended ? '  ·  recommended' : ''}'),
                trailing: progress.containsKey('${m.id}/${f.path}')
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => cancels['${m.id}/${f.path}']?.cancel())
                    : IconButton(icon: const Icon(Icons.download), onPressed: () => download(m.id, f)),
              ),
      ],
      const Divider(height: 32),
      Text('Downloaded', style: Theme.of(c).textTheme.titleMedium),
      ListenableBuilder(
        listenable: engine,
        builder: (c, _) => Column(children: [
          for (final f in downloaded())
            ListTile(
              title: Text(f.uri.pathSegments.last.replaceFirst('__', '/').replaceAll('__', '  ·  ')),
              subtitle: Text(fmtSize(f.lengthSync())),
              leading: Icon(engine.loadedModel == f.path ? Icons.play_circle : Icons.insert_drive_file),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    icon: const Icon(Icons.play_arrow),
                    onPressed: engine.starting
                        ? null
                        : () {
                            engine.start(f.path);
                            snack(c, 'Loading model… see Server tab');
                          }),
                IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () async {
                      if (engine.loadedModel == f.path) await engine.stop();
                      f.deleteSync();
                      setState(() {});
                    }),
              ]),
            ),
          if (downloaded().isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Nothing yet.')),
        ]),
      ),
    ]);
  }
}

// ---------------- Chat ----------------

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final msgs = <Map<String, String>>[];
  String system = prefs.getString('system') ?? defaultSystem;
  bool generating = false;

  Future<void> send() async {
    final t = input.text.trim();
    if (t.isEmpty || generating || !engine.ready) return;
    input.clear();
    setState(() {
      msgs.add({'role': 'user', 'content': t});
      msgs.add({'role': 'assistant', 'content': ''});
      generating = true;
    });
    try {
      await for (final d in engine.chat([
        {'role': 'system', 'content': system},
        ...msgs.sublist(0, msgs.length - 1),
      ])) {
        setState(() => msgs.last['content'] = msgs.last['content']! + d);
        if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
      }
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
    if (mounted) setState(() => generating = false);
  }

  void editSystem() {
    final ctl = TextEditingController(text: system);
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text('System prompt / character'),
              content: TextField(controller: ctl, maxLines: 10),
              actions: [
                TextButton(
                    onPressed: () {
                      ctl.text = defaultSystem;
                    },
                    child: const Text('Reset')),
                FilledButton(
                    onPressed: () {
                      system = ctl.text;
                      prefs.setString('system', system);
                      Navigator.pop(c);
                    },
                    child: const Text('Save')),
              ],
            ));
  }

  @override
  Widget build(BuildContext c) => ListenableBuilder(
        listenable: engine,
        builder: (c, _) => Column(children: [
          ListTile(
            dense: true,
            title: Text(engine.ready
                ? 'Model: ${engine.loadedModel!.split('/').last}'
                : engine.starting
                    ? 'Loading model…'
                    : 'No model loaded — pick one in Models'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.person), onPressed: editSystem),
              IconButton(icon: const Icon(Icons.delete_sweep), onPressed: () => setState(msgs.clear)),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.all(12),
              itemCount: msgs.length,
              itemBuilder: (c, i) {
                final u = msgs[i]['role'] == 'user';
                return Align(
                  alignment: u ? Alignment.centerRight : Alignment.centerLeft,
                  child: Card(
                    color: u ? Theme.of(c).colorScheme.primaryContainer : null,
                    child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: SelectableText(msgs[i]['content']!.isEmpty ? '…' : msgs[i]['content']!)),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(
                  child: TextField(
                controller: input,
                minLines: 1,
                maxLines: 5,
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Message'),
              )),
              IconButton(icon: const Icon(Icons.send), onPressed: engine.ready && !generating ? send : null),
            ]),
          ),
        ]),
      );
}

// ---------------- Server ----------------

class ServerPage extends StatefulWidget {
  const ServerPage({super.key});
  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  final key = TextEditingController(text: engine.apiKey);
  final port = TextEditingController(text: '${engine.port}');

  void save() {
    engine
      ..port = int.tryParse(port.text) ?? 8080
      ..apiKey = key.text.trim();
    prefs
      ..setInt('port', engine.port)
      ..setBool('lan', engine.lan)
      ..setInt('ctx', engine.ctx)
      ..setString('key', engine.apiKey);
  }

  Future<String> ip() async {
    for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      if (!i.name.startsWith('lo') && i.addresses.isNotEmpty) return i.addresses.first.address;
    }
    return '127.0.0.1';
  }

  @override
  Widget build(BuildContext c) => ListenableBuilder(
        listenable: engine,
        builder: (c, _) {
          final models = modelsDir.listSync().whereType<File>().where((f) => f.path.endsWith('.gguf')).toList();
          return ListView(padding: const EdgeInsets.all(12), children: [
            Card(
              child: ListTile(
                leading: Icon(engine.ready ? Icons.check_circle : Icons.circle_outlined,
                    color: engine.ready ? Colors.green : null),
                title: Text(engine.ready ? 'Server running' : engine.starting ? 'Starting…' : 'Server stopped'),
                subtitle: FutureBuilder(
                    future: ip(),
                    builder: (c, s) => Text(engine.ready
                        ? 'OpenAI API: http://${engine.lan ? s.data : '127.0.0.1'}:${engine.port}/v1'
                        : 'Pick a model below to start with one tap')),
                trailing: engine.running
                    ? IconButton(icon: const Icon(Icons.stop), onPressed: engine.stop)
                    : null,
              ),
            ),
            if (engine.ready)
              TextButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Copy base URL'),
                onPressed: () async {
                  final url = 'http://${engine.lan ? await ip() : '127.0.0.1'}:${engine.port}/v1';
                  Clipboard.setData(ClipboardData(text: url));
                  if (c.mounted) snack(c, 'Copied $url');
                },
              ),
            SwitchListTile(
              title: const Text('Expose on local network'),
              subtitle: const Text('Lets other devices on your Wi-Fi use the API. Set an API key.'),
              value: engine.lan,
              onChanged: (v) {
                engine.lan = v;
                save();
                setState(() {});
              },
            ),
            TextField(
                controller: port,
                keyboardType: TextInputType.number,
                onChanged: (_) => save(),
                decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(
                controller: key,
                onChanged: (_) => save(),
                decoration: const InputDecoration(labelText: 'API key (optional)', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: engine.ctx,
              decoration: const InputDecoration(labelText: 'Context length', border: OutlineInputBorder()),
              items: [for (final n in [2048, 4096, 8192, 16384]) DropdownMenuItem(value: n, child: Text('$n'))],
              onChanged: (v) {
                engine.ctx = v!;
                save();
              },
            ),
            const SizedBox(height: 12),
            Text('Start with model', style: Theme.of(c).textTheme.titleMedium),
            for (final f in models)
              ListTile(
                title: Text(f.uri.pathSegments.last.replaceAll('__', '/')),
                trailing: const Icon(Icons.play_arrow),
                onTap: engine.starting
                    ? null
                    : () {
                        save();
                        engine.start(f.path);
                      },
              ),
            if (models.isEmpty) const Text('Download a model in the Models tab first.'),
            const Divider(height: 32),
            Text('Log', style: Theme.of(c).textTheme.titleMedium),
            SelectableText(engine.log.toString(), style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          ]);
        },
      );
}
