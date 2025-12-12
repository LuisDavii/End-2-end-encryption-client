import 'package:flutter/material.dart';
import 'package:cryptography/cryptography.dart';
import 'package:client_chat/database_helper.dart';
import 'package:client_chat/secure_channel_wrapper.dart'; 
import 'dart:convert';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
    });

    final username = _emailController.text;
    final password = _passwordController.text;

    try {
      final algorithm = Ed25519();
      final keyPair = await algorithm.newKeyPair();

      final publicKey = await keyPair.extractPublicKey();
      final publicKeyBase64 = base64Url.encode(publicKey.bytes);

      final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
      final privateKeyBase64 = base64Url.encode(privateKeyBytes);

      final secureChannel = SecureChannelWrapper();
      await secureChannel.connectAndHandshake('ws://10.0.2.2:12345');

      secureChannel.stream.listen(
        (message) async {
          final data = jsonDecode(message);
          String feedbackMessage = "Ocorreu um erro.";

          if (data['type'] == 'auth_response') {
            if (data['status'] == 'REGISTER_SUCCESS') {
              feedbackMessage = "Usuário registado com sucesso!";
              try {
                await DatabaseHelper.instance.initForUser(username);

                await DatabaseHelper.instance.saveKeyPair(
                  privateKeyBase64,
                  publicKeyBase64,
                );

                if (mounted) Navigator.pop(context);
              } catch (e) {
                feedbackMessage = "Erro ao guardar chaves locais: $e";
              }
            } else if (data['status'] == 'REGISTER_FAILED:USERNAME_EXISTS') {
              feedbackMessage = "Este username já está em uso.";
            } else {
              feedbackMessage = "Falha no registro: ${data['message'] ?? 'Erro desconhecido'}";
            }
          }

          if (feedbackMessage.isNotEmpty && mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(feedbackMessage)));
          }

          secureChannel.close();
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        },
        onError: (error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro na conexão: $error')),
          );
          secureChannel.close();
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        },
      );

      final registerData = {
        "type": "REGISTER",
        "username": username,
        "password": password,
        "public_key": publicKeyBase64,
      };

      await secureChannel.send(jsonEncode(registerData));

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao iniciar registro: $e')),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Criar Conta')),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Crie a sua conta',
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
                validator: (value) =>
                    value!.isEmpty ? 'Por favor, insira um username' : null,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Senha',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (value) => value!.length < 6
                    ? 'A senha deve ter pelo menos 6 caracteres'
                    : null,
              ),
              const SizedBox(height: 30),
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _register,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        'Cadastrar',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}