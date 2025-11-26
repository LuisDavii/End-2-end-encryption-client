import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';

import 'package:client_chat/models/chat_models.dart';
import 'login_page.dart';
import 'package:client_chat/database_helper.dart';
import 'package:client_chat/secure_channel_wrapper.dart';

class HomePage extends StatefulWidget {
  final String username;
  final SecureChannelWrapper secureChannel;

  const HomePage({
    super.key,
    required this.username,
    required this.secureChannel,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<ChatUser> _users = [];
  String? _currentChatPartner;
  final List<ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();

  late final StreamSubscription _streamSubscription;

  final Set<String> _typingUsers = {};
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();

    _streamSubscription = widget.secureChannel.stream.listen(_handleServerMessage);

    widget.secureChannel.send(jsonEncode({"type": "REQUEST_USER_LIST"}));

    widget.secureChannel.send(jsonEncode({"type": "REQUEST_OFFLINE_MESSAGES"}));
  }

  // processar todas as mensagens do servidor
  void _handleServerMessage(dynamic message) async {
    final data = jsonDecode(message);

    // Primeiro, processamos a mensagem e guardamos no banco de dados se necessário
    if (data['type'] == 'chat_message') {
      final receivedMessage = ChatMessage(
        from: data['from'],
        content: data['content'],
      );
      // Salva a mensagem recebida, independentemente de a conversa estar aberta
      await DatabaseHelper.instance.insertMessage(
        receivedMessage,
        widget.username,
      );
    }

    // Depois, atualizamos a interface do utilizador (UI) dentro de um único setState
    if (mounted) {
      setState(() {
        final String type = data['type'];

        if (type == 'user_list_update') {
          final List usersFromServer = data['users'];
          _users = usersFromServer
              .map(
                (user) => ChatUser(
                  username: user['username'],
                  isOnline: user['isOnline'],
                ),
              )
              .toList();
        } else if (type == 'chat_message') {
          final fromUser = data['from'];
          // Só adiciona a mensagem à UI se a conversa com aquele usuário estiver aberta
          if (fromUser == _currentChatPartner) {
            _messages.add(
              ChatMessage(from: fromUser, content: data['content']),
            );
            // Se recebemos uma mensagem, a pessoa obviamente parou de digitar
            _typingUsers.remove(fromUser);
          }
        } else if (type == 'TYPING_STATUS_UPDATE') {
          final fromUser = data['from'];
          final isTyping = data['isTyping'] as bool;

          if (isTyping) {
            _typingUsers.add(fromUser);
          } else {
            _typingUsers.remove(fromUser);
          }
        }
      });
    }
  }

  void _onTextChanged(String text) {
    if (_typingTimer?.isActive ?? false) _typingTimer?.cancel();

    // Envia o status START_TYPING
    if (_typingUsers.add(widget.username)) {
      widget.secureChannel.send(
        jsonEncode({"type": "START_TYPING", "to": _currentChatPartner}),
      );
    }

    _typingTimer = Timer(const Duration(seconds: 2), () {
      widget.secureChannel.send(
        jsonEncode({"type": "STOP_TYPING", "to": _currentChatPartner}),
      );
      _typingUsers.remove(widget.username);
    });
  }

  void _sendMessage() async {
    if (_controller.text.isNotEmpty && _currentChatPartner != null) {
      _typingTimer?.cancel();

      widget.secureChannel.send(
        jsonEncode({"type": "STOP_TYPING", "to": _currentChatPartner}),
      );

      widget.secureChannel.send(
        jsonEncode({
          "type": "chat_message",
          "to": _currentChatPartner,
          "content": _controller.text,
        }),
      );

      final sentMessage = ChatMessage(
        from: widget.username,
        content: _controller.text,
      );

      await DatabaseHelper.instance.insertMessage(
        sentMessage,
        _currentChatPartner!,
      );

      setState(() {
        _messages.add(sentMessage);
      });

      _controller.clear();
    }
  }

  void _startChatWith(String username) async {
    List<ChatMessage> history = await DatabaseHelper.instance
        .getConversationHistory(widget.username, username);

    setState(() {
      _currentChatPartner = username;
      _messages.clear();
      _messages.addAll(history);
    });

    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _streamSubscription.cancel();
    _typingTimer?.cancel();
    widget.secureChannel.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isPartnerTyping =
        _currentChatPartner != null &&
        _typingUsers.contains(_currentChatPartner);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_currentChatPartner ?? "Chat"),
            if (isPartnerTyping)
              Text(
                'Digitando...',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LoginPage()),
              );
            },
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Theme.of(context).primaryColor),
              child: Text(
                'Bem-vindo, ${widget.username}',
                style: const TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
            ..._users
                .where((u) => u.isOnline && u.username != widget.username)
                .map((user) {
                  final bool isThisUserTyping = _typingUsers.contains(
                    user.username,
                  );

                  return ListTile(
                    leading: const Icon(
                      Icons.circle,
                      color: Colors.green,
                      size: 14,
                    ),
                    title: Text(user.username),
                    subtitle: isThisUserTyping
                        ? const Text(
                            'digitando...',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.grey,
                            ),
                          )
                        : null,
                    onTap: () => _startChatWith(user.username),
                  );
                }),

            ..._users
                .where((u) => !u.isOnline && u.username != widget.username)
                .map((user) {
                  return ListTile(
                    leading: const Icon(
                      Icons.circle_outlined,
                      color: Colors.grey,
                      size: 14,
                    ),
                    title: Text(user.username),
                    onTap: () => _startChatWith(user.username),
                  );
                }),
          ],
        ),
      ),

      body: _currentChatPartner == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "Selecione um usuário no menu à esquerda para começar a conversar.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    reverse: true,
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages.reversed.toList()[index];
                      final isMe = message.from == widget.username;
                      return Align(
                        alignment: isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 8,
                          ),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isMe
                                ? Theme.of(context).primaryColorLight
                                : Colors.grey[300],
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(message.content),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          onChanged: _onTextChanged,
                          decoration: InputDecoration(
                            hintText: 'Digite uma mensagem...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _sendMessage,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
