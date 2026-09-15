import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine.dart';
import 'frame_view.dart';
import 'models.dart';
import 'results.dart';
import 'theme.dart';

enum Stage { empty, setup, running, results }

class Workspace extends StatefulWidget {
  const Workspace({super.key, required this.engine});
  final Engine engine;

  @override
  State<Workspace> createState() => WorkspaceState();
}

class WorkspaceState extends State<Workspace> {
  final _focus = FocusNode(debugLabel: 'workspace');
  StreamSubscription<Map<String, dynamic>>? _events;

  Stage _stage = Stage.empty;
  ClipInfo? _clip;
  String? _notice;
  bool _dropHover = false;

  int _index = 0;
  FrameImage? _frame;
  bool _frameLoading = false;
  Timer? _debounce;
  int _frameSeq = 0;

  Box? _boxA;
  Box? _boxB;
  // The frame the boxes were drawn on. The tracker starts from exactly this
  // frame, because a box only means something on the frame it was drawn on.
  int? _boxFrame;
  Fencer _active = Fencer.a;
  Offset? _dragStart;
  Offset? _dragNow;

  int _framesToProcess = 150;
  bool _detect = true;
  bool _pose = true;
  TrackerKind _tracker = TrackerKind.vit;

  String? _runId;
  int _runStart = 0;
  int _done = 0;
  int _total = 0;
  final List<String> _runLog = [];
  String? _runError;
  RunResult? _result;

  @override
  void initState() {
    super.initState();
    _events = widget.engine.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _events?.cancel();
    _debounce?.cancel();
    final id = _runId;
    if (id != null) widget.engine.cancel(id).catchError((_) {});
    _focus.dispose();
    super.dispose();
  }

  /// Opens a clip by path. Used by the integration test, which cannot click
  /// through the macOS open panel.
  @visibleForTesting
  Future<void> openClip(String path) => _openClip(path);

  @visibleForTesting
  set framesToProcess(int value) => setState(() => _framesToProcess = value);

  // --- clips and frames ------------------------------------------------

  Future<void> _chooseClip() async {
    if (_stage == Stage.running) return;
    const group = XTypeGroup(
      label: 'Video',
      extensions: ['mov', 'mp4', 'm4v', 'avi', 'mkv'],
      uniformTypeIdentifiers: ['public.movie'],
    );
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file != null) await _openClip(file.path);
  }

  Future<void> _openClip(String path) async {
    setState(() => _notice = null);
    final ClipInfo clip;
    try {
      clip = await widget.engine.probe(path);
    } on EngineException catch (e) {
      if (mounted) setState(() => _notice = e.message);
      return;
    }
    if (!mounted) return;
    setState(() {
      _clip = clip;
      _stage = Stage.setup;
      _index = 0;
      _frame = null;
      _boxA = null;
      _boxB = null;
      _boxFrame = null;
      _active = Fencer.a;
      _result = null;
      _runError = null;
      _framesToProcess = math.min(150, clip.frames);
    });
    _loadFrame(0);
    _focus.requestFocus();

    // The header frame count can be wrong, so get the real one in the
    // background rather than making you wait to open the clip.
    widget.engine.measure(path).then((m) {
      if (!mounted || _clip?.path != path) return;
      final measured = _clip!.withMeasured(frames: m.frames, fps: m.fps);
      final clamped = math.min(_index, measured.frames - 1);
      setState(() {
        _clip = measured;
        _framesToProcess = math.min(_framesToProcess, math.max(1, measured.frames - (_boxFrame ?? clamped)));
      });
      if (clamped != _index) _goTo(clamped);
    }).catchError((Object _) {});
  }

  void _goTo(int index) {
    final clip = _clip;
    if (clip == null || _stage == Stage.running) return;
    final target = index.clamp(0, clip.frames - 1);
    setState(() => _index = target);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 70), () => _loadFrame(target));
  }

  Future<void> _loadFrame(int index) async {
    final clip = _clip;
    if (clip == null) return;
    final seq = ++_frameSeq;
    setState(() => _frameLoading = true);
    try {
      final f = await widget.engine.frame(clip.path, index);
      if (!mounted || seq != _frameSeq) return;
      await precacheImage(FileImage(File(f.image)), context);
      if (!mounted || seq != _frameSeq) return;
      setState(() {
        _frame = f;
        _frameLoading = false;
      });
    } on EngineException catch (e) {
      if (mounted && seq == _frameSeq) {
        setState(() {
          _frameLoading = false;
          _notice = e.message;
        });
      }
    }
  }

  // --- boxes -----------------------------------------------------------

  void _dragStarted(Offset p) {
    setState(() {
      // Boxes from a different frame do not belong on this one.
      if (_boxFrame != null && _boxFrame != _index) {
        _boxA = null;
        _boxB = null;
        _boxFrame = null;
        _active = Fencer.a;
      }
      _dragStart = p;
      _dragNow = p;
    });
  }

  void _dragUpdated(Offset p) => setState(() => _dragNow = p);

  void _dragEnded() {
    final start = _dragStart;
    final now = _dragNow;
    setState(() {
      _dragStart = null;
      _dragNow = null;
      if (start == null || now == null) return;
      final box = Box.fromCorners(start, now);
      if (!box.isUsable) return;
      if (_active == Fencer.a) {
        _boxA = box;
      } else {
        _boxB = box;
      }
      _boxFrame = _index;
      final other = _active.other;
      if ((other == Fencer.a ? _boxA : _boxB) == null) _active = other;
    });
  }

  void _clearBox(Fencer f) => setState(() {
        if (f == Fencer.a) {
          _boxA = null;
        } else {
          _boxB = null;
        }
        if (_boxA == null && _boxB == null) _boxFrame = null;
        _active = f;
      });

  Box? get _draft => (_dragStart != null && _dragNow != null) ? Box.fromCorners(_dragStart!, _dragNow!) : null;

  bool get _ready => _clip != null && _boxA != null && _boxB != null && _boxFrame != null;

  // --- running ---------------------------------------------------------

  Future<void> _run() async {
    if (!_ready || _stage == Stage.running) return;
    final clip = _clip!;
    final start = _boxFrame!;
    final frames = math.min(_framesToProcess, math.max(1, clip.frames - start));
    setState(() {
      _stage = Stage.running;
      _runStart = start;
      _runId = null;
      _done = 0;
      _total = frames;
      _runLog.clear();
      _runError = null;
      _result = null;
      _notice = null;
    });
    try {
      final id = await widget.engine.run(
        path: clip.path,
        boxA: _boxA!,
        boxB: _boxB!,
        start: start,
        frames: frames,
        detect: _detect,
        pose: _pose,
        tracker: _tracker,
      );
      if (mounted && _stage == Stage.running) setState(() => _runId ??= id);
    } on EngineException catch (e) {
      if (mounted) {
        setState(() {
          _stage = Stage.setup;
          _runError = e.message;
        });
      }
    }
  }

  void _cancel() {
    final id = _runId;
    if (id != null) widget.engine.cancel(id).catchError((_) {});
  }

  void _onEvent(Map<String, dynamic> msg) {
    if (!mounted || _stage != Stage.running) return;
    final run = msg['run'] as String?;
    _runId ??= run;
    if (run != _runId) return;
    switch (msg['event']) {
      case 'progress':
        setState(() {
          _done = (msg['done'] as num).toInt();
          _total = math.max(_total, (msg['total'] as num).toInt());
        });
      case 'log':
        setState(() {
          _runLog.add(msg['line'] as String);
          if (_runLog.length > 40) _runLog.removeAt(0);
        });
      case 'done':
        setState(() {
          _result = RunResult.fromEvent(msg, startFrame: _runStart);
          _stage = Stage.results;
          _runId = null;
        });
      case 'error':
        setState(() {
          _runError = msg['error'] as String? ?? 'The run failed.';
          _stage = Stage.setup;
          _runId = null;
        });
      case 'cancelled':
        setState(() {
          _notice = 'Stopped.';
          _stage = Stage.setup;
          _runId = null;
        });
    }
  }

  // --- keys ------------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final key = event.logicalKey;
    if (keys.isMetaPressed && key == LogicalKeyboardKey.keyO) {
      _chooseClip();
      return KeyEventResult.handled;
    }
    if (_stage != Stage.setup) return KeyEventResult.ignored;
    final step = keys.isShiftPressed ? 10 : 1;
    if (key == LogicalKeyboardKey.arrowRight) {
      _goTo(_index + step);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _goTo(_index - step);
    } else if (key == LogicalKeyboardKey.keyA) {
      setState(() => _active = Fencer.a);
    } else if (key == LogicalKeyboardKey.keyB) {
      setState(() => _active = Fencer.b);
    } else if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      _clearBox(_active);
    } else if (key == LogicalKeyboardKey.enter && keys.isMetaPressed) {
      _run();
    } else if (key == LogicalKeyboardKey.escape) {
      setState(() {
        _dragStart = null;
        _dragNow = null;
      });
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // --- layout ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final Widget body = switch (_stage) {
      Stage.empty => _emptyState(),
      Stage.results => ResultsView(
          key: ValueKey(_result!.folder),
          result: _result!,
          clip: _clip!,
          onTrackAgain: () => setState(() {
            _stage = Stage.setup;
            _focus.requestFocus();
          }),
          onOpenClip: _chooseClip,
        ),
      _ => _setup(),
    };

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: DropTarget(
        onDragEntered: (_) => setState(() => _dropHover = true),
        onDragExited: (_) => setState(() => _dropHover = false),
        onDragDone: (details) {
          setState(() => _dropHover = false);
          if (details.files.isNotEmpty && _stage != Stage.running) {
            _openClip(details.files.first.path);
          }
        },
        child: Scaffold(
          body: Stack(children: [
            Column(children: [
              _topBar(),
              if (_notice != null) _noticeBar(),
              Expanded(child: body),
            ]),
            if (_dropHover && _stage != Stage.running)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Brand.bg.withValues(alpha: 0.82),
                    alignment: Alignment.center,
                    child: const Text('Drop the clip to open it',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Brand.accent)),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _topBar() {
    final clip = _clip;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: Brand.surface,
        border: Border(bottom: BorderSide(color: Brand.line)),
      ),
      child: Row(children: [
        const Text.rich(TextSpan(children: [
          TextSpan(text: 'Riposte', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: -0.4)),
          TextSpan(text: '.', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Brand.accent)),
        ])),
        if (clip != null) ...[
          const SizedBox(width: 18),
          Container(width: 1, height: 18, color: Brand.line),
          const SizedBox(width: 18),
          Flexible(
            child: Text(clip.name,
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          Text(
            '${clip.width}x${clip.height}  ${clip.frames}${clip.measured ? '' : '~'} frames  '
            '${clip.fps.toStringAsFixed(2)} fps  ${(clip.sizeBytes / 1e6).toStringAsFixed(0)} MB',
            style: mono(size: 11.5, color: Brand.faint),
          ),
        ],
        const Spacer(),
        if (widget.engine.launch.kind == 'development')
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Tooltip(
              message: 'Running the engine from ${widget.engine.launch.workingDirectory}',
              child: Text('dev engine', style: mono(size: 11, color: Brand.faint)),
            ),
          ),
        OutlinedButton.icon(
          onPressed: _stage == Stage.running ? null : _chooseClip,
          icon: const Icon(Icons.video_file_outlined, size: 17),
          label: const Text('Open clip'),
        ),
      ]),
    );
  }

  Widget _noticeBar() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        color: Brand.raised,
        child: Row(children: [
          Expanded(child: Text(_notice!, style: const TextStyle(color: Brand.ink))),
          IconButton(
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _notice = null),
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ]),
      );

  Widget _emptyState() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Open a bout',
                style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1)),
            const SizedBox(height: 12),
            const Text(
              'Choose a competition clip or drop it anywhere on this window. Nothing is copied or uploaded. '
              'The clip stays where it is and everything runs on this Mac.',
              style: TextStyle(color: Brand.muted, fontSize: 15, height: 1.55),
            ),
            const SizedBox(height: 26),
            Row(children: [
              FilledButton.icon(
                onPressed: _chooseClip,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16)),
                icon: const Icon(Icons.video_file_outlined),
                label: const Text('Choose a clip'),
              ),
              const SizedBox(width: 14),
              Text('or press Cmd O', style: mono(size: 12, color: Brand.faint)),
            ]),
            const SizedBox(height: 36),
            const Divider(),
            const SizedBox(height: 18),
            _tip('Film from a tripod, or at least keep still.',
                'The only benchmark clip that tracked both fencers cleanly was filmed with almost no pan and no zoom.'),
            _tip('Box the mask and torso, not the whole fencer.',
                'On a real clip a full body box slid onto the referee after 49 frames. A torso box followed the fencer correctly.'),
            _tip('Check the losses.',
                'When it cannot find a fencer it says so and leaves those frames blank, instead of guessing.'),
          ]),
        ),
      ),
    );
  }

  Widget _tip(String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(body, style: const TextStyle(color: Brand.muted, height: 1.45)),
        ]),
      );

  Widget _setup() {
    final clip = _clip!;
    final running = _stage == Stage.running;
    final onBoxFrame = _boxFrame == null || _boxFrame == _index;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: Column(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: FrameView(
                frame: _frame,
                videoSize: clip.size,
                boxA: _boxA,
                boxB: _boxB,
                showBoxes: onBoxFrame,
                draft: _draft,
                active: _active,
                loading: _frameLoading,
                enabled: !running,
                onDragStart: _dragStarted,
                onDragUpdate: _dragUpdated,
                onDragEnd: _dragEnded,
              ),
            ),
          ),
          _scrubber(clip, running),
        ]),
      ),
      Container(
        width: 340,
        decoration: const BoxDecoration(
          color: Brand.surface,
          border: Border(left: BorderSide(color: Brand.line)),
        ),
        child: running ? _runningPanel() : _setupPanel(clip),
      ),
    ]);
  }

  Widget _scrubber(ClipInfo clip, bool running) {
    Widget step(String label, int delta) => TextButton(
          onPressed: running ? null : () => _goTo(_index + delta),
          style: TextButton.styleFrom(
            minimumSize: const Size(40, 34),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            foregroundColor: Brand.muted,
          ),
          child: Text(label, style: mono(size: 12, color: running ? Brand.faint : Brand.muted)),
        );
    final maxIndex = math.max(clip.frames - 1, 1).toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 20, 14),
      child: Row(children: [
        step('-30', -30),
        step('-5', -5),
        step('-1', -1),
        Expanded(
          child: Slider(
            value: _index.toDouble().clamp(0, maxIndex),
            max: maxIndex,
            onChanged: running ? null : (v) => _goTo(v.round()),
          ),
        ),
        step('+1', 1),
        step('+5', 5),
        step('+30', 30),
        const SizedBox(width: 12),
        SizedBox(
          width: 150,
          child: Text(
            'frame $_index  ${(_index / clip.fps).toStringAsFixed(2)} s',
            textAlign: TextAlign.right,
            style: mono(size: 12, color: Brand.ink),
          ),
        ),
      ]),
    );
  }

  Widget _section(String number, String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(number, style: mono(size: 12, color: Brand.accent, weight: FontWeight.w600)),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          ...children,
        ]),
      );

  Widget _setupPanel(ClipInfo clip) {
    final start = _boxFrame ?? _index;
    final remaining = math.max(1, clip.frames - start);
    final frames = math.min(_framesToProcess, remaining);
    final fullBody = [
      if (_boxA?.looksFullBody ?? false) Fencer.a,
      if (_boxB?.looksFullBody ?? false) Fencer.b,
    ];

    return ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 24), children: [
      _section('01', 'Find the phrase', [
        const Text(
          'Scrub to just before the action. Tracking starts from the frame you draw the boxes on. '
          'Arrow keys step one frame, Shift steps ten.',
          style: TextStyle(color: Brand.muted, height: 1.45, fontSize: 13.5),
        ),
        if (_boxFrame != null && _boxFrame != _index) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Brand.bg, borderRadius: BorderRadius.circular(6), border: Border.all(color: Brand.line)),
            child: Row(children: [
              Expanded(
                child: Text('Your boxes are on frame $_boxFrame. Drawing here starts again.',
                    style: const TextStyle(fontSize: 12.5, color: Brand.muted, height: 1.4)),
              ),
              TextButton(onPressed: () => _goTo(_boxFrame!), child: const Text('Go back')),
            ]),
          ),
        ],
      ]),
      _section('02', 'Box each fencer', [
        _fencerRow(Fencer.a, _boxA),
        const SizedBox(height: 8),
        _fencerRow(Fencer.b, _boxB),
        const SizedBox(height: 10),
        const Text(
          'Drag around the mask and torso only, not the legs. Press A or B to choose which box you are drawing.',
          style: TextStyle(color: Brand.muted, height: 1.45, fontSize: 13.5),
        ),
        for (final f in fullBody) ...[
          const SizedBox(height: 10),
          Text(
            '${f.label}\'s box is tall and narrow, which looks like a full body. On a real clip a full body box slid '
            'onto the referee after 49 frames. Box the mask and torso instead.',
            style: const TextStyle(color: Brand.warn, height: 1.45, fontSize: 13),
          ),
        ],
      ]),
      _section('03', 'Track it', [
        Row(children: [
          const Expanded(child: Text('Frames to process', style: TextStyle(fontSize: 13.5))),
          Text('$frames  ${(frames / clip.fps).toStringAsFixed(1)} s', style: mono(size: 12, color: Brand.ink)),
        ]),
        if (remaining > 1)
          Slider(
            value: frames.toDouble().clamp(1, remaining.toDouble()),
            min: 1,
            max: remaining.toDouble(),
            onChanged: (v) => setState(() => _framesToProcess = v.round()),
          ),
        _switchRow('Person detection', 'Recommended. Keeps each box on a real person.', _detect,
            (v) => setState(() => _detect = v)),
        _switchRow('Body landmarks', 'Feet, hips, sword hand. Roughly halves the speed.', _pose,
            (v) => setState(() => _pose = v)),
        const SizedBox(height: 10),
        const Text('Tracker', style: TextStyle(fontSize: 13.5)),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<TrackerKind>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: TrackerKind.vit, label: Text('ViT')),
              ButtonSegment(value: TrackerKind.csrt, label: Text('CSRT')),
            ],
            selected: {_tracker},
            onSelectionChanged: (s) => setState(() => _tracker = s.first),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _tracker == TrackerKind.vit
              ? 'Gives up sooner instead of holding on to the wrong thing. Loses fencers more often through a fleche.'
              : 'Holds on through a fleche better, but when it goes wrong it goes wrong silently.',
          style: const TextStyle(color: Brand.faint, fontSize: 12.5, height: 1.45),
        ),
      ]),
      if (_runError != null) ...[
        Text(_runError!, style: const TextStyle(color: Brand.lost, height: 1.45)),
        const SizedBox(height: 14),
      ],
      FilledButton(
        onPressed: _ready ? _run : null,
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
        child: Text(_ready ? 'Track this phrase' : 'Box both fencers first'),
      ),
      const SizedBox(height: 8),
      if (_ready) Center(child: Text('or Cmd Enter', style: mono(size: 11, color: Brand.faint))),
    ]);
  }

  Widget _fencerRow(Fencer f, Box? box) {
    final selected = _active == f;
    return Material(
      color: selected ? Brand.raised : Brand.bg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _active = f),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? Brand.box(f) : Brand.line, width: selected ? 1.5 : 1),
          ),
          child: Row(children: [
            Container(width: 12, height: 12, color: Brand.box(f)),
            const SizedBox(width: 10),
            Text(f.label, style: TextStyle(fontWeight: FontWeight.w700, color: Brand.text(f))),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                box == null ? (selected ? 'drag on the frame' : 'not drawn') : '${box.w.round()} x ${box.h.round()} px',
                style: mono(size: 11.5, color: box == null ? Brand.faint : Brand.muted),
              ),
            ),
            if (box != null)
              IconButton(
                tooltip: 'Clear ${f.label}',
                visualDensity: VisualDensity.compact,
                onPressed: () => _clearBox(f),
                icon: const Icon(Icons.close_rounded, size: 16),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _switchRow(String title, String help, bool value, ValueChanged<bool> onChanged) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 13.5)),
              const SizedBox(height: 2),
              Text(help, style: const TextStyle(color: Brand.faint, fontSize: 12, height: 1.35)),
            ]),
          ),
          const SizedBox(width: 10),
          Switch(value: value, onChanged: onChanged),
        ]),
      );

  Widget _runningPanel() {
    final pct = _total > 0 ? (_done / _total).clamp(0.0, 1.0) : null;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 24), children: [
      const Text('Tracking', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text(
        _done == 0
            ? 'Loading the models. The first frames take a few seconds.'
            : 'Frame $_done of $_total, from frame $_runStart.',
        style: const TextStyle(color: Brand.muted),
      ),
      const SizedBox(height: 16),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: _done == 0 ? null : pct, minHeight: 6),
      ),
      const SizedBox(height: 22),
      const Text('As it happens', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      if (_runLog.isEmpty)
        const Text('Nothing lost so far.', style: TextStyle(color: Brand.faint))
      else
        for (final line in _runLog.reversed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              line,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: line.contains('LOST') ? Brand.lost : Brand.muted,
              ),
            ),
          ),
      const SizedBox(height: 20),
      OutlinedButton(onPressed: _runId == null ? null : _cancel, child: const Text('Stop')),
    ]);
  }
}
