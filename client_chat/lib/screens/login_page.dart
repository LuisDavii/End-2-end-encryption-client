import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';

import 'home_page.dart';
import 'register_page.dart';
import 'package:client_chat/database_helper.dart';

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

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
    });

    final username = _emailController.text;
    final password = _passwordController.text;


    final wsUrl = Uri.parse('ws://10.0.2.2:12345');
    final channel = WebSocketChannel.connect(wsUrl);
    final stream = channel.stream.asBroadcastStream();

    stream.listen(
      (message) async{
        final data = jsonDecode(message);
        if (data['type'] == 'auth_response') {
          if (data['status'] == 'LOGIN_SUCCESS') {
            if (mounted) {

              await DatabaseHelper.instance.initForUser(username);

              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => HomePage(
                    username: username,
                    stream: stream,
                    sink: channel.sink,
                  ),
                ),
              );
            }
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Usuário ou senha incorretos.')),
            );
            channel.sink.close();
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          }
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
      onDone: () {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      },
    );

    final loginData = {
      "type": "LOGIN",
      "username": username,
      "password": password,
    };
    channel.sink.add(jsonEncode(loginData));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Bem-vindo de volta!',
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
                    value!.isEmpty ? 'Por favor, insira o seu username' : null,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Senha',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (value) =>
                    value!.isEmpty ? 'Por favor, insira a sua senha' : null,
              ),
              const SizedBox(height: 30),
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _login,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        'Entrar',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const RegisterPage()),
                ),
                child: const Text('Não tem uma conta? Cadastre-se'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
