import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'models.dart';
import 'theme.dart';

class ResultsView extends StatefulWidget {
  const ResultsView({
    super.key,
    required this.result,
    required this.clip,
    required this.onTrackAgain,
    required this.onOpenClip,
  });

  final RunResult result;
  final ClipInfo clip;
  final VoidCallback onTrackAgain;
  final VoidCallback onOpenClip;

  @override
  State<ResultsView> createState() => _ResultsViewState();
}

class _ResultsViewState extends State<ResultsView> {
  VideoPlayerController? _video;
  String? _videoProblem;

  @override
  void initState() {
    super.initState();
    final controller = VideoPlayerController.file(File(widget.result.video));
    _video = controller;
    controller.initialize().then((_) {
      if (!mounted) return;
      controller.setLooping(true);
      controller.play();
      setState(() {});
    }).catchError((Object e) {
      if (mounted) {
        setState(() => _videoProblem = 'The annotated video was saved, but this Mac could not play it in the app. '
            'Open it from Finder instead.');
      }
    });
    controller.addListener(_onTick);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _video?.removeListener(_onTick);
    _video?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final v = _video;
    if (v == null || !v.value.isInitialized) return;
    v.value.isPlaying ? v.pause() : v.play();
  }

  Future<void> _reveal(String path) => Process.run('open', ['-R', path]);
  Future<void> _open(String path) => Process.run('open', [path]);

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.space): _togglePlay},
      child: Focus(
        autofocus: true,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _player()),
          Container(
            width: 360,
            decoration: const BoxDecoration(
              color: Brand.surface,
              border: Border(left: BorderSide(color: Brand.line)),
            ),
            child: _summary(),
          ),
        ]),
      ),
    );
  }

  Widget _player() {
    final v = _video;
    final ready = v != null && v.value.isInitialized;
    return Column(children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Center(
            child: _videoProblem != null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_videoProblem!, textAlign: TextAlign.center, style: const TextStyle(color: Brand.muted)),
                  )
                : !ready
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : AspectRatio(
                        aspectRatio: v.value.aspectRatio,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: GestureDetector(onTap: _togglePlay, child: VideoPlayer(v)),
                        ),
                      ),
          ),
        ),
      ),
      if (ready)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 20, 16),
          child: Row(children: [
            IconButton(
              tooltip: v.value.isPlaying ? 'Pause (space)' : 'Play (space)',
              onPressed: _togglePlay,
              icon: Icon(v.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: VideoProgressIndicator(
                v,
                allowScrubbing: true,
                padding: const EdgeInsets.symmetric(vertical: 10),
                colors: const VideoProgressColors(
                  playedColor: Brand.accent,
                  bufferedColor: Brand.raised,
                  backgroundColor: Brand.line,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Text(_clock(v.value.position, v.value.duration), style: mono(size: 12)),
          ]),
        ),
    ]);
  }

  String _clock(Duration p, Duration d) {
    String f(Duration x) => '${x.inMinutes}:${(x.inMilliseconds / 1000 % 60).toStringAsFixed(1).padLeft(4, '0')}';
    return '${f(p)} / ${f(d)}';
  }

  Widget _summary() {
    final r = widget.result;
    final s = r.summary;
    final losses = s.events.where((e) => e.kind == 'LOST').toList();
    return ListView(padding: const EdgeInsets.fromLTRB(22, 22, 22, 28), children: [
      const Text('Done', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4)),
      const SizedBox(height: 6),
      Text(
        '${s.frames} frames from frame ${r.startFrame}, in ${r.seconds.toStringAsFixed(1)} s with ${s.tracker?.toUpperCase() ?? 'the tracker'}.',
        style: const TextStyle(color: Brand.muted, height: 1.45),
      ),
      if (s.error != null) ...[
        const SizedBox(height: 14),
        Text(s.error!, style: const TextStyle(color: Brand.lost)),
      ],
      const SizedBox(height: 22),
      for (var i = 0; i < s.fencers.length && i < 2; i++) _fencerStats(i == 0 ? Fencer.a : Fencer.b, s.fencers[i]),
      const SizedBox(height: 10),
      const Divider(height: 28),
      const Text('What it could not see', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      if (s.events.isEmpty)
        const Text(
          'No losses. It stayed on both fencers for every processed frame.',
          style: TextStyle(color: Brand.muted, height: 1.45),
        )
      else
        for (final e in s.events) _eventRow(e),
      const SizedBox(height: 14),
      Text(
        losses.isEmpty
            ? 'Staying on a fencer is not proof it was the right fencer. Watch the clip before you trust a number.'
            : 'A loss means it refused to guess. Those frames are blank in the spreadsheet rather than filled with the last thing it saw.',
        style: const TextStyle(color: Brand.faint, fontSize: 12.5, height: 1.5),
      ),
      const Divider(height: 36),
      FilledButton.icon(
        onPressed: () => _reveal(r.video),
        icon: const Icon(Icons.folder_open_rounded, size: 18),
        label: const Text('Show in Finder'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: File(r.csv).existsSync() ? () => _open(r.csv) : null,
        icon: const Icon(Icons.table_chart_outlined, size: 18),
        label: const Text('Open the spreadsheet'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: widget.onTrackAgain,
        icon: const Icon(Icons.replay_rounded, size: 18),
        label: const Text('Track another phrase'),
      ),
      const SizedBox(height: 8),
      TextButton(onPressed: widget.onOpenClip, child: const Text('Open a different clip')),
      const SizedBox(height: 18),
      SelectableText(r.folder, style: mono(size: 11, color: Brand.faint)),
    ]);
  }

  Widget _fencerStats(Fencer f, FencerStats st) {
    Widget row(String label, double pct, String help) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Tooltip(
            message: help,
            child: Row(children: [
              Expanded(child: Text(label, style: const TextStyle(color: Brand.muted))),
              Text('${pct.toStringAsFixed(0)}%', style: mono(size: 14, color: Brand.ink, weight: FontWeight.w600)),
            ]),
          ),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: Brand.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Brand.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 10, height: 10, color: Brand.box(f)),
          const SizedBox(width: 8),
          Text(f.label, style: TextStyle(color: Brand.text(f), fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        row('Tracked', st.trackedPct, 'Frames where it had a position for this fencer.'),
        row('Body landmarks', st.posePct, 'Of those frames, how many also got a skeleton.'),
      ]),
    );
  }

  Widget _eventRow(RunEvent e) {
    final isLoss = e.kind == 'LOST';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        SizedBox(
          width: 86,
          child: Text(e.kind, style: mono(size: 12, color: isLoss ? Brand.lost : Brand.muted, weight: FontWeight.w600)),
        ),
        Expanded(child: Text(e.who ?? 'Both boxes', style: const TextStyle(fontSize: 13))),
        Text('frame ${e.frame}', style: mono(size: 12)),
      ]),
    );
  }
}
