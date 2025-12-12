import 'package:flutter/material.dart';
import 'package:client_chat/models/chat_models.dart';

class ChatDrawer extends StatelessWidget {
  final String myUsername;
  final List<ChatUser> users;
  final Set<String> typingUsers;
  final Function(String) onUserSelected;
  final VoidCallback onLogout;

  const ChatDrawer({
    super.key,
    required this.myUsername,
    required this.users,
    required this.typingUsers,
    required this.onUserSelected,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Theme.of(context).primaryColor),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    backgroundColor: Colors.white,
                    child: Icon(Icons.person),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Olá, $myUsername',
                    style: const TextStyle(color: Colors.white, fontSize: 20),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ...users
                    .where((u) => u.isOnline && u.username != myUsername)
                    .map((user) => _buildUserTile(user)),
                
                if (users.any((u) => !u.isOnline && u.username != myUsername))
                  const Divider(),
                ...users
                    .where((u) => !u.isOnline && u.username != myUsername)
                    .map((user) => _buildUserTile(user)),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Sair', style: TextStyle(color: Colors.red)),
            onTap: onLogout,
          ),
        ],
      ),
    );
  }

  Widget _buildUserTile(ChatUser user) {
    final isTyping = typingUsers.contains(user.username);
    return ListTile(
      leading: Stack(
        children: [
          const Icon(Icons.account_circle, size: 40, color: Colors.grey),
          Positioned(
            right: 0,
            bottom: 0,
            child: Icon(
              Icons.circle,
              color: user.isOnline ? Colors.green : Colors.grey,
              size: 14,
            ),
          ),
        ],
      ),
      title: Text(user.username, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: isTyping
          ? const Text(
              'digitando...',
              style: TextStyle(fontStyle: FontStyle.italic, color: Colors.deepPurple),
            )
          : Text(user.isOnline ? 'Online' : 'Offline', style: TextStyle(color: Colors.grey[600])),
      onTap: () => onUserSelected(user.username),
    );
  }
}