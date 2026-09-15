import 'dart:async';

import 'package:flutter/material.dart';

import 'engine.dart';
import 'theme.dart';
import 'workspace.dart';

void main() => runApp(const RiposteApp());

class RiposteApp extends StatelessWidget {
  const RiposteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Riposte',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const EngineHost(),
    );
  }
}

/// Starts the tracking engine, keeps it alive, and says plainly what went
/// wrong if it cannot start, rather than showing a window that does nothing.
class EngineHost extends StatefulWidget {
  const EngineHost({super.key});

  @override
  State<EngineHost> createState() => _EngineHostState();
}

class _EngineHostState extends State<EngineHost> {
  Engine? _engine;
  Object? _error;
  bool _starting = true;
  StreamSubscription<Map<String, dynamic>>? _exitWatch;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final engine = await Engine.start();
      if (!mounted) {
        engine.dispose();
        return;
      }
      _exitWatch?.cancel();
      _exitWatch = engine.events.where((m) => m['event'] == 'engine_exit').listen((_) {
        if (!mounted) return;
        setState(() {
          _engine = null;
          _error = EngineException('The tracking engine stopped. Restart it to carry on.');
        });
      });
      setState(() {
        _engine = engine;
        _starting = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _starting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _exitWatch?.cancel();
    _engine?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
    if (engine != null) return Workspace(engine: engine);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: _starting
                ? const Column(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)),
                    SizedBox(height: 18),
                    Text('Starting the tracker', style: TextStyle(color: Brand.muted)),
                  ])
                : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('The tracker could not start',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    SelectableText('$_error', style: const TextStyle(color: Brand.muted, height: 1.5)),
                    const SizedBox(height: 22),
                    FilledButton(onPressed: _start, child: const Text('Try again')),
                  ]),
          ),
        ),
      ),
    );
  }
}
