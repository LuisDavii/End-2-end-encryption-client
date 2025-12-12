import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:client_chat/database_helper.dart';
import 'package:client_chat/secure_channel_wrapper.dart';
import 'package:client_chat/user_preferences.dart';
import 'home_page.dart';
import 'welcome_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    await Future.delayed(const Duration(milliseconds: 500));

    final isLoggedIn = await UserPreferences.isLoggedIn();
    final username = await UserPreferences.getUser();

    if (isLoggedIn && username != null) {
      await _performAutoLogin(username);
    } else {
      _navigateToWelcome();
    }
  }

  Future<void> _performAutoLogin(String username) async {
    try {
      print("[Splash] Tentando login automático para $username...");

      await DatabaseHelper.instance.initForUser(username);
      final storedPrivateKey = await DatabaseHelper.instance.getPrivateKey();

      if (storedPrivateKey == null) {
        throw Exception("Chave privada não encontrada.");
      }

      final secureChannel = SecureChannelWrapper();
      await secureChannel.connectAndHandshake('ws://10.0.2.2:12345');

      secureChannel.send(jsonEncode({
        "type": "LOGIN_CHALLENGE_REQUEST",
        "username": username,
      }));

      await for (final message in secureChannel.stream.timeout(const Duration(seconds: 5))) {
        final data = jsonDecode(message);

        if (data['type'] == 'LOGIN_CHALLENGE') {
          final nonceBase64 = data['nonce'];
          final nonceBytes = base64Url.decode(nonceBase64);
          final algorithm = Ed25519();
          final privateKeyBytes = base64Url.decode(storedPrivateKey);
          final keyPair = await algorithm.newKeyPairFromSeed(privateKeyBytes);
          final signature = await algorithm.sign(nonceBytes, keyPair: keyPair);

          secureChannel.send(jsonEncode({
            "type": "LOGIN_CHALLENGE_RESPONSE",
            "username": username,
            "signature": base64Url.encode(signature.bytes),
          }));

        } else if (data['type'] == 'auth_response') {
          if (data['status'] == 'LOGIN_SUCCESS') {
            print("[Splash] Login automático com sucesso!");
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
            return; 
          } else {
            throw Exception("Falha na autenticação automática.");
          }
        }
      }
    } catch (e) {
      print("[Splash] Erro no login automático: $e");
      _navigateToWelcome();
    }
  }

  void _navigateToWelcome() {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const WelcomePage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat, size: 80, color: Colors.deepPurple),
            SizedBox(height: 24),
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Conectando de forma segura...", style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}