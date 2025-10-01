import 'package:flutter/material.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        itemBuilder: (context, index) {
          return ListTile(
            leading: const Icon(Icons.article_outlined),
            title: Text('Your post #${index + 1}'),
            subtitle: const Text('User post placeholder'),
          );
        },
        itemCount: 8,
      ),
    );
  }
}
