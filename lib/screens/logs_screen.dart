import 'package:flutter/material.dart';

import '../diagnostics/app_logger.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  String _content = 'Loading...';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final content = await AppLogger.readAll();
    if (mounted) setState(() => _content = content);
  }

  Future<void> _clear() async {
    await AppLogger.clear();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics log'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh, tooltip: 'Refresh'),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _clear, tooltip: 'Clear log'),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(_content, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      ),
    );
  }
}
