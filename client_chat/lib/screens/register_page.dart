import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:cryptography/cryptography.dart';
import 'package:client_chat/database_helper.dart';
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

    final algorithm = X25519();
    final keyPair = await algorithm.newKeyPair();

    // Extrai a chave pública
    final publicKey = await keyPair.extractPublicKey();
    final publicKeyBytes = publicKey.bytes;
    final publicKeyBase64 = base64UrlEncode(publicKeyBytes);

    // Extrai a chave privada
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
    final privateKeyBase64 = base64UrlEncode(privateKeyBytes);

    //enviando dados de registro ao servidor
    final wsUrl = Uri.parse('ws://10.0.2.2:12345');
    final channel = WebSocketChannel.connect(wsUrl);

    channel.stream.listen(
      (message) async {
        final data = jsonDecode(message);
        String feedbackMessage = "Ocorreu um erro.";

        if (data['type'] == 'auth_response') {
          if (data['status'] == 'REGISTER_SUCCESS') {
            feedbackMessage = "Usuário registado com sucesso!";
            try {
              // Inicializa o banco de dados para o novo usuário
              await DatabaseHelper.instance.initForUser(username);
              // Salva o par de chaves
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
          } else{
            feedbackMessage = "Falha no registro. Tente novamente.";
          }
          
        }

        if (feedbackMessage.isNotEmpty && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(feedbackMessage)));
        }
        channel.sink.close();
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      },
      onError: (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao conectar ao servidor.')),
        );
        channel.sink.close();
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
    channel.sink.add(jsonEncode(registerData));
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
