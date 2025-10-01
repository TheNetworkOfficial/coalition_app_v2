import 'package:flutter/material.dart';

class CreateEntryPage extends StatelessWidget {
  const CreateEntryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create'),
      ),
      body: const Center(
        child: Text('TODO: Select media to create a new entry'),
      ),
    );
  }
}
