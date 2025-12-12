import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:client_chat/database_helper.dart';
import 'package:client_chat/secure_channel_wrapper.dart';
import 'package:client_chat/user_preferences.dart';
import 'login_page.dart';
import 'home_page.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  String? _savedUser;
  bool _isLoading = true;
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    _checkSavedUser();
  }

  Future<void> _checkSavedUser() async {
    final user = await UserPreferences.getUser();
    if (user == null) {

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
        );
      }
    } else {

      setState(() {
        _savedUser = user;
        _isLoading = false;
      });
    }
  }

  Future<void> _continueWithChallenge() async {
    if (_savedUser == null) return;
    
    setState(() { _isAuthenticating = true; });
    final username = _savedUser!;

    try {
      await DatabaseHelper.instance.initForUser(username);
      final storedPrivateKey = await DatabaseHelper.instance.getPrivateKey();

      if (storedPrivateKey == null) {

        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chave não encontrada. Faça login com senha.')));
           Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginPage()));
        }
        return;
      }

      final secureChannel = SecureChannelWrapper();
      await secureChannel.connectAndHandshake('ws://10.0.2.2:12345');

      secureChannel.send(jsonEncode({
        "type": "LOGIN_CHALLENGE_REQUEST",
        "username": username,
      }));

      secureChannel.stream.listen((message) async {
        final data = jsonDecode(message);

        if (data['type'] == 'LOGIN_CHALLENGE') {
          final nonceBase64 = data['nonce'];
          final nonceBytes = base64Url.decode(nonceBase64);

          final algorithm = Ed25519();
          final privateKeyBytes = base64Url.decode(storedPrivateKey);
          final keyPair = await algorithm.newKeyPairFromSeed(privateKeyBytes);

          final signature = await algorithm.sign(
            nonceBytes,
            keyPair: keyPair,
          );

          secureChannel.send(jsonEncode({
            "type": "LOGIN_CHALLENGE_RESPONSE",
            "username": username,
            "signature": base64Url.encode(signature.bytes),
          }));

        } else if (data['type'] == 'auth_response') {
          if (data['status'] == 'LOGIN_SUCCESS') {
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => HomePage(
                    username: username,
                    secureChannel: secureChannel,
                  ),
                ),
              );
            }
          } else {
             if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Falha na autenticação.')));
             secureChannel.close();
             setState(() { _isAuthenticating = false; });
          }
        }
      }, onError: (e) {
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
         setState(() { _isAuthenticating = false; });
      });

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro de conexão: $e')));
      setState(() { _isAuthenticating = false; });
    }
  }

  void _goToDifferentAccount() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.lock_person_rounded, size: 80, color: Colors.deepPurple),
            const SizedBox(height: 32),
            
            Text(
              'Bem-vindo de volta,',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              _savedUser ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            
            const SizedBox(height: 48),

            _isAuthenticating 
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton(
                  onPressed: _continueWithChallenge,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.deepPurple,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Continuar', style: TextStyle(fontSize: 18, color: Colors.white)),
                ),

            const SizedBox(height: 24),
            
            TextButton(
              onPressed: _goToDifferentAccount,
              child: const Text('Não é você? Entrar com outra conta'),
            ),
          ],
        ),
      ),
    );
  }
}