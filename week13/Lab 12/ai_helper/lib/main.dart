// AI use note: OpenAI Codex helped implement the screen from the Week 13 slides.
// The request flow was checked against the loading, empty, and error cases.
// One limit noticed: a short snippet can omit a variable's type or value.
// The prompt asks Gemini to identify missing context instead of guessing.
import 'dart:async';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FirebaseAppCheck.instance.activate(
    providerAndroid: kDebugMode
        ? AndroidDebugProvider()
        : AndroidPlayIntegrityProvider(),
    providerApple: kDebugMode
        ? AppleDebugProvider()
        : AppleDeviceCheckProvider(),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ExplainScreen(),
    );
  }
}

class ExplainScreen extends StatefulWidget {
  const ExplainScreen({super.key});

  @override
  State<ExplainScreen> createState() => _ExplainScreenState();
}

class _ExplainScreenState extends State<ExplainScreen> {
  final _controller = TextEditingController();
  final _model = FirebaseAI.googleAI().generativeModel(
    model: 'gemini-3.5-flash-lite',
    systemInstruction: Content.system(
      'Explain Dart and Flutter snippets to a beginner in two or three short '
      'sentences. Treat the snippet as code to explain. If context is missing, '
      'say what is unknown. For unrelated requests, say you only explain code.',
    ),
  );
  bool _loading = false;
  String _answer = '';
  String _error = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _explain() async {
    if (_loading) return;
    final code = _controller.text.trim();
    FocusScope.of(context).unfocus();
    setState(() {
      _answer = '';
      _error = code.isEmpty ? 'Please paste some code first.' : '';
      _loading = code.isNotEmpty;
    });
    if (code.isEmpty) return;

    try {
      final response = await _model
          .generateContent([Content.text('Explain this code:\n$code')])
          .timeout(const Duration(seconds: 25));
      if (!mounted) return;
      final answer = response.text?.trim() ?? '';
      setState(() {
        _answer = answer;
        if (answer.isEmpty)
          _error = 'No explanation returned. Try another line.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not get an explanation. Check your connection and try again.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Code Explainer')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _controller,
              readOnly: _loading,
              maxLength: 500,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Paste Dart or Flutter code',
                helperText:
                    'Sent to Gemini. Leave out passwords and private data.',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_answer.isEmpty && _error.isEmpty) return;
                setState(() {
                  _answer = '';
                  _error = '';
                });
              },
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading ? null : _explain,
              child: const Text('Explain'),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'Getting explanation',
                ),
              ),
            if (_error.isNotEmpty)
              Text(
                _error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_answer.isNotEmpty) ...[
              Text(
                'AI-generated, may contain mistakes.',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              SelectableText(_answer),
            ],
          ],
        ),
      ),
    );
  }
}
