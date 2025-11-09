import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Asistente de Voz IA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  bool _isLoading = false;

  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _voiceInput = "";

  final FlutterTts _tts = FlutterTts();
  String? _userId;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initTTS();
    _loadOrCreateUserId();
  }

  // 🧍 Cargar o generar ID de usuario
  Future<void> _loadOrCreateUserId() async {
    final prefs = await SharedPreferences.getInstance();
    String? savedId = prefs.getString('userId');
    if (savedId == null) {
      savedId = 'user_${Random().nextInt(100000)}';
      await prefs.setString('userId', savedId);
    }
    setState(() => _userId = savedId);
    print('🧍 ID de usuario: $_userId');
  }

  // ⚙️ Configurar TTS
  Future<void> _initTTS() async {
    await _tts.setLanguage("es-ES");
    await _tts.setSpeechRate(0.9);
    await _tts.setPitch(1.0);
    _tts.setCompletionHandler(() {
      _startListening();
    });
  }

  // 🎙️ Escuchar voz
  Future<void> _startListening() async {
    bool available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'notListening') {
          _stopListening();
          if (_voiceInput.isNotEmpty) {
            sendMessage();
          }
        }
      },
      onError: (error) {
        print('❌ Error al escuchar: $error');
        setState(() => _isListening = false);
      },
    );

    if (available) {
      setState(() => _isListening = true);
      _speech.listen(
        onResult: (result) {
          setState(() {
            _voiceInput = result.recognizedWords;
            _controller.text = _voiceInput;
          });
        },
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 2),
        localeId: "es_ES",
      );
    } else {
      print("No se pudo inicializar el reconocimiento de voz.");
    }
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _isListening = false);
  }

  // 💬 Enviar mensaje al backend (n8n)
  Future<void> sendMessage() async {
    if (_userId == null) return;

    final message = _controller.text.trim();
    if (message.isEmpty) return;

    setState(() {
      _messages.add({'role': 'user', 'text': message});
      _isLoading = true;
      _controller.clear();
    });

    try {
      final url = Uri.parse('https://williansmalque.app.n8n.cloud/webhook-test/assistant');

      final body = {
        "userId": _userId,
        "inputType": "text",
        "message": message,
        "audioBase64": "",
        "responseType": "text"
      };

      print("📤 Enviando a n8n: ${jsonEncode(body)}");

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'FlutterApp/1.0'
        },
        body: jsonEncode(body),
      );

      print("📥 Código de respuesta: ${response.statusCode}");
      print("📦 Respuesta: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reply = data['output'] ?? data['reply'] ?? 'No se recibió respuesta del asistente.';

        setState(() {
          _messages.add({'role': 'ai', 'text': reply});
          _isLoading = false;
        });

        await _tts.speak(reply);
      } else {
        setState(() {
          _messages.add({
            'role': 'ai',
            'text': 'Error del servidor (${response.statusCode})'
          });
          _isLoading = false;
        });
      }
    } catch (e, stacktrace) {
      print('❌ Error al enviar mensaje: $e');
      print('🧱 Stacktrace: $stacktrace');
      setState(() {
        _messages.add({
          'role': 'ai',
          'text': 'Error de conexión: $e'
        });
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Asistente IA de Voz 🎧')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['role'] == 'user';
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.blueAccent : Colors.grey[800],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      msg['text']!,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _isListening ? Icons.mic_off : Icons.mic,
                  color: _isListening ? Colors.red : Colors.white,
                ),
                onPressed: _isListening ? _stopListening : _startListening,
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: 'Habla o escribe un mensaje...',
                  ),
                  onSubmitted: (_) => sendMessage(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: sendMessage,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
