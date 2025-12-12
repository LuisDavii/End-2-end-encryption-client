import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';

import 'package:client_chat/user_preferences.dart';
import 'package:client_chat/e2ee_session.dart';
import 'package:client_chat/models/chat_models.dart';
import 'package:client_chat/database_helper.dart';
import 'package:client_chat/secure_channel_wrapper.dart';

import 'package:client_chat/widgets/chat_drawer.dart';
import 'package:client_chat/widgets/chat_area.dart';
import 'welcome_page.dart'; 

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
  final Set<String> _typingUsers = {};

  final Map<String, E2EESession> _e2eeSessions = {};
  late final StreamSubscription _streamSubscription;
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    _streamSubscription = widget.secureChannel.stream.listen(_handleServerMessage);

    widget.secureChannel.send(jsonEncode({"type": "REQUEST_USER_LIST"}));
    widget.secureChannel.send(jsonEncode({"type": "REQUEST_OFFLINE_MESSAGES"}));
  }

  @override
  void dispose() {
    _streamSubscription.cancel();
    _typingTimer?.cancel();
    _controller.dispose();
    widget.secureChannel.close();
    super.dispose();
  }

  E2EESession _getSession(String peerUsername) {
    if (_e2eeSessions.containsKey(peerUsername)) {
      return _e2eeSessions[peerUsername]!;
    }

    final session = E2EESession(
      myUsername: widget.username,
      peerUsername: peerUsername,

      isPeerOnline: () {
        final user = _users.firstWhere(
          (u) => u.username == peerUsername, 
          orElse: () => ChatUser(username: peerUsername, isOnline: false)
        );
        return user.isOnline;
      },

      sendToServer: (type, payload) {
        widget.secureChannel.send(jsonEncode({
          "type": type,
          "to": peerUsername,
          "payload": payload
        }));
      },
      
      onMessageReceived: (text) {
        if (mounted) {
          setState(() {
            if (_currentChatPartner == peerUsername) {
              _messages.add(ChatMessage(from: peerUsername, content: text));
            }

             DatabaseHelper.instance.insertMessage(
               ChatMessage(from: peerUsername, content: text), 
               widget.username
             );
          });
        }
      },
    );

    session.init();
    
    _e2eeSessions[peerUsername] = session;
    return session;
  }

  void _handleServerMessage(dynamic message) async {
    final data = jsonDecode(message);
    final type = data['type'];

    if (type == 'user_list_update') {
      _updateUserList(data['users']);
    } 
    else if (type == 'TYPING_STATUS_UPDATE') {
      _updateTypingStatus(data);
    }

    else if (type == "E2E_HANDSHAKE" || type == "E2E_AUTH" || type == "E2E_MSG") {
      final fromUser = data['from'];
      final session = _getSession(fromUser);
      await session.handleSignal(data); 
    }

    else if (type == 'chat_message') {
       final fromUser = data['from'];
       final content = data['content'];
       final msg = ChatMessage(from: fromUser, content: content);
       
       await DatabaseHelper.instance.insertMessage(msg, widget.username);
       if (fromUser == _currentChatPartner && mounted) {
          setState(() {
            _messages.add(msg);
            _typingUsers.remove(fromUser);
          });
       }
    }
  }

  void _updateUserList(List usersFromServer) {
    if (!mounted) return;
    setState(() {
      _users = usersFromServer.map((user) => ChatUser(
        username: user['username'],
        isOnline: user['isOnline'],
      )).toList();
    });
  }

  void _updateTypingStatus(dynamic data) {
    if (!mounted) return;
    setState(() {
      final fromUser = data['from'];
      final isTyping = data['isTyping'] as bool;
      if (isTyping) {
        _typingUsers.add(fromUser);
      } else {
        _typingUsers.remove(fromUser);
      }
    });
  }

  void _onUserSelected(String username) async {
    List<ChatMessage> history = await DatabaseHelper.instance
        .getConversationHistory(widget.username, username);

    setState(() {
      _currentChatPartner = username;
      _messages.clear();
      _messages.addAll(history);
    });

    Navigator.of(context).pop(); 
    
    final session = _getSession(username);

    if (!session.isReady) {
       session.startHandshake();
    }
  }

  void _onTextChanged(String text) {
    if (_currentChatPartner == null) return;

    if (_typingTimer?.isActive ?? false) _typingTimer?.cancel();

    if (_typingUsers.add(widget.username)) {
      widget.secureChannel.send(
        jsonEncode({"type": "START_TYPING", "to": _currentChatPartner}),
      );
    }

    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (_currentChatPartner != null) {
        widget.secureChannel.send(
          jsonEncode({"type": "STOP_TYPING", "to": _currentChatPartner}),
        );
      }
      _typingUsers.remove(widget.username);
    });
  }

  void _sendMessage() async {
    if (_controller.text.isEmpty || _currentChatPartner == null) return;

    final text = _controller.text;
    final partner = _currentChatPartner!;
    
    _typingTimer?.cancel();
    widget.secureChannel.send(jsonEncode({"type": "STOP_TYPING", "to": partner}));

    try {
      final session = _getSession(partner);

      await session.sendChatMessage(text);

      final sentMessage = ChatMessage(from: widget.username, content: text);
      await DatabaseHelper.instance.insertMessage(sentMessage, partner);

      setState(() {
        _messages.add(sentMessage);
        _controller.clear();
      });

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Não foi possível enviar: ${e.toString().replaceAll('Exception: ', '')}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _logout() async{

    await UserPreferences.setLoggedIn(false);

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const WelcomePage()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isPartnerTyping = _currentChatPartner != null && 
                                 _typingUsers.contains(_currentChatPartner);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_currentChatPartner ?? "Chat Seguro"),
            if (isPartnerTyping)
              const Text(
                'Digitando...',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
          ],
        ),
      ),
      drawer: ChatDrawer(
        myUsername: widget.username,
        users: _users,
        typingUsers: _typingUsers,
        onUserSelected: _onUserSelected,
        onLogout: _logout,
      ),
      body: ChatArea(
        myUsername: widget.username,
        currentChatPartner: _currentChatPartner,
        messages: _messages,
        controller: _controller,
        onTextChanged: _onTextChanged,
        onSendMessage: _sendMessage,
      ),
    );
  }
}