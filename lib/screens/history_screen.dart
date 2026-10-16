import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';
import '../providers/history_provider.dart';

/// Riwayat Perintah screen.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final history = context.watch<HistoryProvider>();
    final items = history.items;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Perintah'),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Hapus riwayat',
              onPressed: () => context.read<HistoryProvider>().clear(),
            ),
        ],
      ),
      body: SafeArea(
        child: items.isEmpty
            ? const Center(child: Text('Belum ada riwayat perintah.'))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final time =
                      intl.DateFormat('EEEE, HH:mm', 'id_ID').format(item.timestamp);
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        item.icon,
                        color: item.isError ? Colors.red : null,
                      ),
                      title: Text(item.title),
                      subtitle: Text('${item.value}\n$time'),
                      isThreeLine: true,
                    ),
                  );
                },
              ),
      ),
    );
  }
}
