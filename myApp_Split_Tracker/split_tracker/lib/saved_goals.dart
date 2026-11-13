import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// The signed-in user's Firestore collection is the only persistent goal store.
CollectionReference<Map<String, dynamic>> userGoals() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) {
    throw StateError('Please log in before accessing saved goals.');
  }
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('goals');
}

Future<void> saveSplitGoal({
  required String distance,
  required double goalSeconds,
}) async {
  await userGoals().add({
    'distance': distance,
    'goalSeconds': goalSeconds,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });
}

String _formatGoal(double seconds) {
  final hundredths = (seconds * 100).round();
  final hours = hundredths ~/ 360000;
  final minutes = (hundredths ~/ 6000) % 60;
  final secs = (hundredths ~/ 100) % 60;
  final decimals = hundredths % 100;
  final secText = secs.toString().padLeft(2, '0') +
      '.' + decimals.toString().padLeft(2, '0');
  if (hours > 0) {
    return hours.toString() + ':' +
        minutes.toString().padLeft(2, '0') + ':' + secText;
  }
  return minutes.toString() + ':' + secText;
}

class SavedGoalsSection extends StatefulWidget {
  const SavedGoalsSection({super.key});

  @override
  State<SavedGoalsSection> createState() => _SavedGoalsSectionState();
}

class _SavedGoalsSectionState extends State<SavedGoalsSection> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = userGoals()
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'My Saved Split Goals',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _stream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Could not load saved goals. Check your connection.'),
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(18),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final docs = snapshot.data!.docs;
            if (docs.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'No goals saved yet. Calculate your splits, then tap Save Goal to Cloud.',
                  ),
                ),
              );
            }
            return Column(
              children: docs.map((doc) {
                final data = doc.data();
                final distance = (data['distance'] ?? '5K').toString();
                final seconds = (data['goalSeconds'] as num?)?.toDouble() ?? 0;
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.timer_outlined, color: Colors.blue),
                    title: Text(distance + ' • ' + _formatGoal(seconds)),
                    subtitle: const Text('Saved to your account in Firestore'),
                    trailing: Wrap(
                      spacing: 0,
                      children: [
                        IconButton(
                          tooltip: 'Edit goal',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => _EditGoalDialog(
                              document: doc.reference,
                              distance: distance,
                              goalSeconds: seconds,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Delete goal',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            try {
                              await doc.reference.delete();
                            } catch (_) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Could not delete goal. Try again.'),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _EditGoalDialog extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> document;
  final String distance;
  final double goalSeconds;

  const _EditGoalDialog({
    required this.document,
    required this.distance,
    required this.goalSeconds,
  });

  @override
  State<_EditGoalDialog> createState() => _EditGoalDialogState();
}

class _EditGoalDialogState extends State<_EditGoalDialog> {
  final _hours = TextEditingController();
  final _minutes = TextEditingController();
  final _seconds = TextEditingController();
  late String _distance;
  String _error = '';
  bool _saving = false;

  static const _distances = [
    '5K',
    '8K',
    '10K',
    'Half Marathon',
    'Marathon',
  ];

  @override
  void initState() {
    super.initState();
    _distance = _distances.contains(widget.distance) ? widget.distance : '5K';
    final t = (widget.goalSeconds * 100).round();
    _hours.text = (t ~/ 360000).toString();
    _minutes.text = ((t ~/ 6000) % 60).toString();
    _seconds.text = ((t % 6000) / 100).toStringAsFixed(2);
  }

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    _seconds.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final h = int.tryParse(_hours.text.trim());
    final m = int.tryParse(_minutes.text.trim());
    final s = double.tryParse(_seconds.text.trim());
    if (h == null || m == null || s == null ||
        h < 0 || m < 0 || m >= 60 || s < 0 || s >= 60 ||
        (h == 0 && m == 0 && s == 0)) {
      setState(() => _error = 'Enter a valid time (minutes and seconds under 60).');
      return;
    }
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await widget.document.update({
        'distance': _distance,
        'goalSeconds': h * 3600 + m * 60 + s,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not update goal. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Split Goal'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _distance,
              decoration: const InputDecoration(labelText: 'Distance'),
              items: _distances
                  .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                  .toList(),
              onChanged: _saving ? null : (d) {
                if (d != null) setState(() => _distance = d);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hours,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Hours'),
            ),
            TextField(
              controller: _minutes,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Minutes (0–59)'),
            ),
            TextField(
              controller: _seconds,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Seconds (0–59.99)'),
            ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving...' : 'Save Changes'),
        ),
      ],
    );
  }
}
