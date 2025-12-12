import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'home_page.dart';
import 'register_page.dart';
import 'package:client_chat/database_helper.dart';
import 'package:client_chat/secure_channel_wrapper.dart';
import 'package:client_chat/user_preferences.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _loginWithPassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; });

    final username = _emailController.text;
    final password = _passwordController.text;

    try {
      final secureChannel = SecureChannelWrapper();
      await secureChannel.connectAndHandshake('ws://10.0.2.2:12345');

      final algorithm = Ed25519();
      final newKeyPair = await algorithm.newKeyPair();
      
      final publicKey = await newKeyPair.extractPublicKey();
      final privateKeyBytes = await newKeyPair.extractPrivateKeyBytes();
      
      final publicKeyBase64 = base64Url.encode(publicKey.bytes);
      final privateKeyBase64 = base64Url.encode(privateKeyBytes);

      secureChannel.send(jsonEncode({
        "type": "LOGIN",
        "username": username,
        "password": password,
        "new_public_key": publicKeyBase64, 
      }));

      secureChannel.stream.listen((message) async {
        final data = jsonDecode(message);
        
        if (data['type'] == 'auth_response') {
          if (data['status'] == 'LOGIN_SUCCESS') {
            try {
              await DatabaseHelper.instance.initForUser(username);
              await DatabaseHelper.instance.saveKeyPair(privateKeyBase64, publicKeyBase64);
              await UserPreferences.saveUser(username);
              await UserPreferences.setLoggedIn(true);

              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (context) => HomePage(
                      username: username,
                      secureChannel: secureChannel,
                    ),
                  ),
                  (route) => false, 
                );
              }
            } catch (e) {
               print("Erro ao salvar dados locais: $e");
            }
          } else {
            // Falha
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Falha no login: ${data['status']}')),
              );
            }
            secureChannel.close();
            setState(() { _isLoading = false; });
          }
        }
      }, onError: (e) {
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
         setState(() { _isLoading = false; });
      });

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
      setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entrar com Senha')),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Acessar Conta',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 30),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) => value!.isEmpty ? 'Insira o username' : null,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Senha',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (value) => value!.isEmpty ? 'Insira a senha' : null,
              ),
              const SizedBox(height: 30),
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _loginWithPassword,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Entrar', style: TextStyle(fontSize: 18)),
                    ),
              const SizedBox(height: 15),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const RegisterPage()),
                ),
                child: const Text('Criar nova conta'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}