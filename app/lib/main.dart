import 'package:flutter/material.dart';
import 'package:opus_dart/opus_dart.dart';
import 'package:opus_flutter/opus_flutter.dart' as opus_flutter;
import 'package:shared_preferences/shared_preferences.dart';

import 'voice_client.dart';

const kBg = Color(0xFF04060C);
const kCard = Color(0xFF0C1322);
const kBlue = Color(0xFF1F6BFF);
const kBlueLight = Color(0xFF4D8DFF);
const kRed = Color(0xFFFF4D5E);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initOpus(await opus_flutter.load());
  VoiceClient.initService();
  runApp(const VoiceBridgeApp());
}

class VoiceBridgeApp extends StatelessWidget {
  const VoiceBridgeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'VoiceBridge',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: kBg,
          colorScheme: const ColorScheme.dark(primary: kBlue, secondary: kBlueLight, surface: kCard),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: kCard,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: kBlue,
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        home: const LoginPage(),
      );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final client = VoiceClient();
  final _addr = TextEditingController();
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      _addr.text = p.getString('addr') ?? '';
      _name.text = p.getString('name') ?? '';
    });
  }

  Future<void> _connect() async {
    if (_addr.text.trim().isEmpty || _name.text.trim().isEmpty || _code.text.trim().isEmpty) {
      setState(() => _error = 'Fill in server, name and code');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('addr', _addr.text.trim());
    await prefs.setString('name', _name.text.trim());

    final err = await client.connect(_addr.text.trim(), _name.text.trim(), _code.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err == null) {
      _code.clear();
      await Navigator.push(context, MaterialPageRoute(builder: (_) => VoicePage(client: client)));
      if (mounted) setState(() => _error = 'Disconnected. Run /vc code again to reconnect.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [kBlueLight, kBlue], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      boxShadow: [BoxShadow(color: Color(0x661F6BFF), blurRadius: 30)],
                    ),
                    child: const Icon(Icons.graphic_eq, size: 46, color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  const Text('VoiceBridge', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                  const Text('Proximity voice chat', style: TextStyle(color: Colors.white54)),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _addr,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(hintText: 'Server  (play.example.com:19132)', prefixIcon: Icon(Icons.dns_outlined)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(hintText: 'Player name', prefixIcon: Icon(Icons.person_outline)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'Code from /vc code', prefixIcon: Icon(Icons.vpn_key_outlined)),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: kRed)),
                  ],
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _busy ? null : _connect,
                    child: _busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : const Text('Connect', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}

class VoicePage extends StatefulWidget {
  final VoiceClient client;
  const VoicePage({super.key, required this.client});

  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage> {
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    widget.client.addListener(_watch);
  }

  void _watch() {
    if (!widget.client.connected && mounted && !_popped) {
      _popped = true;
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    widget.client.removeListener(_watch);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) {
            final speaking = c.speakingIds;
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(children: [
                Row(children: [
                  const Icon(Icons.graphic_eq, color: kBlueLight),
                  const SizedBox(width: 8),
                  const Text('VoiceBridge', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text(c.myName, style: const TextStyle(color: Colors.white54)),
                ]),
                const SizedBox(height: 26),
                _MicButton(muted: c.muted, talking: c.talking, onTap: () => c.setMuted(!c.muted)),
                const SizedBox(height: 10),
                Text(c.muted ? 'Muted' : (c.talking ? 'Speaking…' : 'Mic on'),
                    style: TextStyle(color: c.muted ? kRed : kBlueLight, fontWeight: FontWeight.w600)),
                const SizedBox(height: 22),
                Row(children: [
                  Expanded(
                    child: _Toggle(
                      icon: c.deafened ? Icons.headset_off : Icons.headset,
                      label: c.deafened ? 'Deafened' : 'Hearing',
                      on: !c.deafened,
                      onTap: () => c.setDeafened(!c.deafened),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Toggle(
                      icon: Icons.blur_on,
                      label: 'Noise filter',
                      on: c.noise,
                      onTap: () => c.setNoise(!c.noise),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                if (c.inputs.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: c.inputs.any((d) => d.id == c.inputId) ? c.inputId : null,
                    isExpanded: true,
                    dropdownColor: kCard,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.mic_none), labelText: 'Microphone'),
                    items: [for (final d in c.inputs) DropdownMenuItem(value: d.id, child: Text(d.label, overflow: TextOverflow.ellipsis))],
                    onChanged: (v) => v == null ? null : c.setInput(v),
                  ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('NEARBY · ${c.peers.length}',
                      style: const TextStyle(color: Colors.white38, letterSpacing: 1.4, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: c.peers.isEmpty
                      ? const Center(child: Text('Nobody within range', style: TextStyle(color: Colors.white30)))
                      : ListView.separated(
                          itemCount: c.peers.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final p = c.peers[i];
                            final on = speaking.contains(p.id);
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: kCard,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: on ? kBlueLight : Colors.transparent, width: 1.5),
                              ),
                              child: Row(children: [
                                CircleAvatar(
                                  backgroundColor: on ? kBlue : const Color(0xFF16213A),
                                  child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase()),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                                if (p.muted) const Icon(Icons.mic_off, size: 18, color: kRed),
                                const SizedBox(width: 10),
                                Text('${p.dist.toStringAsFixed(0)} m', style: const TextStyle(color: Colors.white54)),
                              ]),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: c.disconnect,
                  icon: const Icon(Icons.logout, color: kRed),
                  label: const Text('Disconnect', style: TextStyle(color: kRed)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    side: const BorderSide(color: kRed),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ]),
            );
          },
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  final bool muted, talking;
  final VoidCallback onTap;
  const _MicButton({required this.muted, required this.talking, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: muted
                ? const LinearGradient(colors: [Color(0xFF1A1F2E), Color(0xFF0C1322)], begin: Alignment.topLeft, end: Alignment.bottomRight)
                : const LinearGradient(colors: [kBlueLight, kBlue], begin: Alignment.topLeft, end: Alignment.bottomRight),
            border: Border.all(color: muted ? kRed : Colors.transparent, width: 2),
            boxShadow: [
              BoxShadow(
                color: muted ? Colors.transparent : kBlue.withOpacity(talking ? 0.8 : 0.35),
                blurRadius: talking ? 50 : 24,
                spreadRadius: talking ? 6 : 0,
              ),
            ],
          ),
          child: Icon(muted ? Icons.mic_off : Icons.mic, size: 60, color: muted ? kRed : Colors.white),
        ),
      );
}

class _Toggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _Toggle({required this.icon, required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: on ? kBlue.withOpacity(0.16) : kCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? kBlue : Colors.white12),
          ),
          child: Column(children: [
            Icon(icon, color: on ? kBlueLight : Colors.white38),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: on ? Colors.white : Colors.white54)),
          ]),
        ),
      );
}
