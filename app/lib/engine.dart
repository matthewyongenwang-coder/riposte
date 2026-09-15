import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'models.dart';

class EngineException implements Exception {
  EngineException(this.message);
  final String message;
  @override
  String toString() => message;
}

class EngineLaunch {
  const EngineLaunch({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.kind,
  });

  final String executable;
  final List<String> arguments;
  final String workingDirectory;

  /// "bundled" inside the .app, or "development" from the repo's venv.
  final String kind;
}

/// Talks to engine.py over its stdin and stdout.
///
/// The engine is a separate process on purpose. The tracker is Python and
/// OpenCV, and this app never decodes video or runs tracking itself. If it
/// did, the app and the terminal could disagree about what happened in a
/// bout, which is how the browser version went wrong.
class Engine {
  Engine._(this._process, this.launch) {
    _process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(_onLine, onDone: _onExit);
    _process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((l) => debugPrint(l));
    _process.exitCode.then((code) {
      exitCode = code;
      _onExit();
    });
  }

  final Process _process;
  final EngineLaunch launch;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  int _nextId = 0;
  bool _closed = false;
  bool _disposing = false;
  int? exitCode;
  Map<String, dynamic> hello = const {};

  Stream<Map<String, dynamic>> get events => _events.stream;

  /// Where the engine lives. Inside the packaged app first, then the repo.
  static EngineLaunch locate() {
    final exe = File(Platform.resolvedExecutable);
    // Riposte.app/Contents/MacOS/Riposte -> Riposte.app/Contents/Resources
    final resources = '${exe.parent.parent.path}/Resources';
    final bundled = File('$resources/engine/riposte-engine');
    if (bundled.existsSync()) {
      return EngineLaunch(
        executable: bundled.path,
        arguments: const [],
        workingDirectory: bundled.parent.path,
        kind: 'bundled',
      );
    }
    final home = Platform.environment['HOME'] ?? '';
    final repo = Platform.environment['RIPOSTE_REPO'] ?? '$home/fencing-tracker';
    final python = '$repo/venv/bin/python';
    final script = '$repo/engine.py';
    if (File(python).existsSync() && File(script).existsSync()) {
      return EngineLaunch(executable: python, arguments: [script], workingDirectory: repo, kind: 'development');
    }
    throw EngineException(
      'Could not find the tracking engine. There is no engine inside the app, '
      'and nothing at $script.',
    );
  }

  static Future<Engine> start() async {
    final launch = locate();
    final process = await Process.start(
      launch.executable,
      launch.arguments,
      workingDirectory: launch.workingDirectory,
      environment: const {'PYTHONUNBUFFERED': '1'},
    );
    final engine = Engine._(process, launch);
    try {
      engine.hello = await engine.request('hello').timeout(const Duration(seconds: 60));
    } on TimeoutException {
      engine.dispose();
      throw EngineException('The tracking engine started but never answered.');
    }
    return engine;
  }

  Future<Map<String, dynamic>> request(String cmd, [Map<String, dynamic> args = const {}]) {
    if (_closed) {
      return Future.error(EngineException('The tracking engine has stopped.'));
    }
    final id = ++_nextId;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _process.stdin.writeln(jsonEncode({'id': id, 'cmd': cmd, ...args}));
    return completer.future;
  }

  void _onLine(String line) {
    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      debugPrint('engine wrote a line that is not JSON: $line');
      return;
    }
    final id = msg['id'];
    if (id is int && _pending.containsKey(id)) {
      final completer = _pending.remove(id)!;
      if (msg['ok'] == true) {
        completer.complete(msg);
      } else {
        completer.completeError(EngineException(msg['error'] as String? ?? 'The engine could not do that.'));
      }
      return;
    }
    if (msg.containsKey('event')) {
      _events.add(msg);
    }
  }

  void _onExit() {
    if (_closed) return;
    _closed = true;
    for (final c in _pending.values) {
      c.completeError(EngineException('The tracking engine stopped unexpectedly.'));
    }
    _pending.clear();
    if (!_disposing) {
      _events.add({'event': 'engine_exit', 'code': exitCode});
    }
  }

  // --- typed commands --------------------------------------------------

  Future<ClipInfo> probe(String path) async => ClipInfo.fromJson(await request('probe', {'path': path}));

  Future<({int frames, double fps})> measure(String path) async {
    final r = await request('measure', {'path': path});
    return (frames: (r['frames'] as num).toInt(), fps: (r['fps'] as num).toDouble());
  }

  Future<FrameImage> frame(String path, int index) async =>
      FrameImage.fromJson(await request('frame', {'path': path, 'index': index}));

  Future<String> run({
    required String path,
    required Box boxA,
    required Box boxB,
    required int start,
    required int frames,
    required bool detect,
    required bool pose,
    required TrackerKind tracker,
  }) async {
    final r = await request('run', {
      'path': path,
      'box_a': boxA.toJson(),
      'box_b': boxB.toJson(),
      'start': start,
      'frames': frames,
      'detect': detect,
      'pose': pose,
      'tracker': tracker.name,
    });
    return r['run'] as String;
  }

  Future<void> cancel(String runId) => request('cancel', {'run': runId});

  /// Closing stdin is how the engine knows the app has gone. It stops any
  /// running tracker and exits. Killed outright only if it ignores that.
  void dispose() {
    if (_disposing) return;
    _disposing = true;
    try {
      _process.stdin.close();
    } catch (_) {}
    Future.delayed(const Duration(seconds: 3), () {
      if (!_closed) _process.kill();
    });
  }
}
