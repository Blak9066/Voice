import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:opus_dart/opus_dart.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _rate = 48000;
const _frame = 960; // 20 ms @ 48 kHz

class Peer {
  final int id;
  final String name;
  final double dist;
  final bool muted;
  Peer(this.id, this.name, this.dist, this.muted);
}

class _Speaker {
  final decoder = SimpleOpusDecoder(sampleRate: _rate, channels: 1);
  final queue = Queue<Int16List>();
  double gain = 1, pan = 0;
  int lastMs = 0;
}

class VoiceClient extends ChangeNotifier {
  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  Completer<String?>? _login;
  final _rec = AudioRecorder();
  StreamSubscription<Uint8List>? _micSub;
  SimpleOpusEncoder? _enc;
  final _speakers = <int, _Speaker>{};
  Timer? _ui;
  int _seq = 0, _hang = 0;
  Uint8List _leftover = Uint8List(0);

  bool connected = false;
  bool muted = false, deafened = false, noise = true, talking = false;
  String myName = '';
  List<Peer> peers = [];
  List<InputDevice> inputs = [];
  String? inputId;

  Set<int> get speakingIds {
    final now = DateTime.now().millisecondsSinceEpoch;
    return {for (final e in _speakers.entries) if (now - e.value.lastMs < 400) e.key};
  }

  static void initService() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'voicebridge',
        channelName: 'Voice chat',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<String?> connect(String address, String name, String code) async {
    await FlutterForegroundTask.requestNotificationPermission();
    if (!await _rec.hasPermission()) return 'Microphone permission is required';

    final url = address.contains('://') ? address : 'ws://$address';
    try {
      _ws = WebSocketChannel.connect(Uri.parse(url));
      await _ws!.ready.timeout(const Duration(seconds: 8));
    } catch (_) {
      _ws = null;
      return 'Cannot reach the server';
    }
    _login = Completer<String?>();
    _wsSub = _ws!.stream.listen(_onData, onDone: _closed, onError: (_) => _closed());
    _send({'type': 'login', 'name': name, 'code': code});

    final err = await _login!.future
        .timeout(const Duration(seconds: 10), onTimeout: () => 'Server did not answer');
    if (err != null) await disconnect();
    return err;
  }

  Future<void> disconnect() async {
    try {
      await _ws?.sink.close();
    } catch (_) {}
    await _cleanup();
  }

  void _closed() {
    if (_login != null && !_login!.isCompleted) _login!.complete('Connection closed');
    _cleanup();
  }

  Future<void> _cleanup() async {
    _ui?.cancel();
    _ui = null;
    await _wsSub?.cancel();
    _wsSub = null;
    _ws = null;
    await _stopMic();
    try {
      await FlutterPcmSound.release();
    } catch (_) {}
    for (final s in _speakers.values) {
      s.decoder.destroy();
    }
    _speakers.clear();
    _enc?.destroy();
    _enc = null;
    peers = [];
    talking = false;
    if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();
    if (connected) {
      connected = false;
      notifyListeners();
    }
  }

  void _send(Map<String, dynamic> m) => _ws?.sink.add(jsonEncode(m));

  void _onData(dynamic d) {
    try {
      if (d is String) {
        _onJson(jsonDecode(d) as Map<String, dynamic>);
      } else if (d is List<int>) {
        _onFrame(d is Uint8List ? d : Uint8List.fromList(d));
      }
    } catch (e) {
      debugPrint('bad message: $e');
    }
  }

  void _onJson(Map<String, dynamic> m) {
    switch (m['type']) {
      case 'welcome':
        _welcome(m);
        break;
      case 'error':
        if (_login != null && !_login!.isCompleted) _login!.complete(m['message'] as String? ?? 'Error');
        break;
      case 'state':
        _applyState(m);
        break;
      case 'setDevice':
        if (m['kind'] == 'input') {
          inputId = m['id'] as String?;
          _startMic();
          notifyListeners();
        }
        break;
      case 'nearby':
        peers = [
          for (final p in (m['players'] as List))
            Peer(p['id'] as int, p['name'] as String, (p['dist'] as num).toDouble(), p['muted'] as bool? ?? false)
        ];
        notifyListeners();
        break;
    }
  }

  Future<void> _welcome(Map<String, dynamic> m) async {
    myName = m['name'] as String? ?? '';
    final st = m['state'] as Map<String, dynamic>?;
    if (st != null) {
      muted = st['muted'] as bool? ?? false;
      deafened = st['deafened'] as bool? ?? false;
      noise = st['noise'] as bool? ?? true;
    }
    await FlutterForegroundTask.startService(
      notificationTitle: 'VoiceBridge',
      notificationText: 'Voice chat is active',
    );
    _enc = SimpleOpusEncoder(sampleRate: _rate, channels: 1, application: Application.voip);
    await _initPlayer();
    inputs = await _rec.listInputDevices();
    inputId ??= inputs.isNotEmpty ? inputs.first.id : null;
    await _startMic();
    connected = true;
    _ui = Timer.periodic(const Duration(milliseconds: 250), (_) => notifyListeners());
    _sendDevices();
    if (_login != null && !_login!.isCompleted) _login!.complete(null);
    notifyListeners();
  }

  void _applyState(Map<String, dynamic> m) {
    muted = m['muted'] as bool? ?? muted;
    deafened = m['deafened'] as bool? ?? deafened;
    final n = m['noise'] as bool? ?? noise;
    final changed = n != noise;
    noise = n;
    if (changed && connected) _startMic();
    if (deafened) {
      for (final s in _speakers.values) {
        s.queue.clear();
      }
    }
    notifyListeners();
  }

  void setMuted(bool v) {
    muted = v;
    _sendState();
    notifyListeners();
  }

  void setDeafened(bool v) {
    deafened = v;
    if (v) {
      for (final s in _speakers.values) {
        s.queue.clear();
      }
    }
    _sendState();
    notifyListeners();
  }

  void setNoise(bool v) {
    noise = v;
    _sendState();
    _startMic();
    notifyListeners();
  }

  void setInput(String id) {
    inputId = id;
    _startMic();
    _sendDevices();
    notifyListeners();
  }

  void _sendState() => _send({'type': 'state', 'muted': muted, 'deafened': deafened, 'noise': noise});

  void _sendDevices() => _send({
        'type': 'devices',
        'inputs': [for (final d in inputs) {'id': d.id, 'name': d.label}],
        'outputs': [
          {'id': 'auto', 'name': 'Auto (speaker / headset)'}
        ],
        'selectedInput': inputId,
        'selectedOutput': 'auto',
      });

  Future<void> _startMic() async {
    await _stopMic();
    InputDevice? dev;
    for (final d in inputs) {
      if (d.id == inputId) dev = d;
    }
    final cfg = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _rate,
      numChannels: 1,
      device: dev,
      echoCancel: noise,
      noiseSuppress: noise,
      autoGain: noise,
    );
    try {
      final stream = await _rec.startStream(cfg);
      _micSub = stream.listen(_onMic);
    } catch (e) {
      debugPrint('mic error: $e');
    }
  }

  Future<void> _stopMic() async {
    await _micSub?.cancel();
    _micSub = null;
    try {
      if (await _rec.isRecording()) await _rec.stop();
    } catch (_) {}
    _leftover = Uint8List(0);
  }

  void _onMic(Uint8List chunk) {
    final b = BytesBuilder(copy: false)
      ..add(_leftover)
      ..add(chunk);
    final all = b.takeBytes();
    var off = 0;
    while (all.length - off >= _frame * 2) {
      final copy = Uint8List.fromList(all.sublist(off, off + _frame * 2));
      off += _frame * 2;
      _processFrame(copy.buffer.asInt16List());
    }
    _leftover = Uint8List.fromList(all.sublist(off));
  }

  void _processFrame(Int16List pcm) {
    var peak = 0;
    for (final s in pcm) {
      final a = s.abs();
      if (a > peak) peak = a;
    }
    if (peak > 400) {
      _hang = 15;
    } else if (_hang > 0) {
      _hang--;
    }
    talking = _hang > 0 && !muted;
    if (muted || _hang == 0 || _ws == null || _enc == null) return;

    final opus = _enc!.encode(input: pcm);
    final out = Uint8List(3 + opus.length);
    out[0] = 0x01;
    out[1] = (_seq >> 8) & 0xff;
    out[2] = _seq & 0xff;
    _seq = (_seq + 1) & 0xffff;
    out.setRange(3, out.length, opus);
    _ws!.sink.add(out);
  }

  void _onFrame(Uint8List d) {
    if (deafened || d.length < 10 || d[0] != 0x02) return;
    final bd = ByteData.sublistView(d);
    final src = bd.getInt32(1);
    final sp = _speakers.putIfAbsent(src, _Speaker.new);
    sp.gain = d[5] / 255.0;
    sp.pan = bd.getInt8(6) / 100.0;
    sp.lastMs = DateTime.now().millisecondsSinceEpoch;
    try {
      sp.queue.add(sp.decoder.decode(input: Uint8List.sublistView(d, 9)));
    } catch (_) {}
    while (sp.queue.length > 8) {
      sp.queue.removeFirst();
    }
  }

  Future<void> _initPlayer() async {
    await FlutterPcmSound.setup(sampleRate: _rate, channelCount: 2);
    await FlutterPcmSound.setFeedThreshold(_frame * 3);
    FlutterPcmSound.setFeedCallback(_onFeed);
    FlutterPcmSound.start();
  }

  void _onFeed(int remaining) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _speakers.removeWhere((id, s) {
      if (now - s.lastMs > 5000) {
        s.decoder.destroy();
        return true;
      }
      return false;
    });

    const frames = 2;
    final out = Int16List(_frame * 2 * frames);
    for (var f = 0; f < frames; f++) {
      final mix = Int32List(_frame * 2);
      for (final s in _speakers.values) {
        if (s.queue.isEmpty) continue;
        final pcm = s.queue.removeFirst();
        if (pcm.length < _frame) continue;
        final gl = s.gain * (1 - math.max(0.0, s.pan) * 0.8);
        final gr = s.gain * (1 + math.min(0.0, s.pan) * 0.8);
        for (var i = 0; i < _frame; i++) {
          mix[2 * i] += (pcm[i] * gl).round();
          mix[2 * i + 1] += (pcm[i] * gr).round();
        }
      }
      for (var i = 0; i < mix.length; i++) {
        out[f * _frame * 2 + i] = mix[i].clamp(-32768, 32767).toInt();
      }
    }
    FlutterPcmSound.feed(PcmArrayInt16.fromList(out));
  }
}
