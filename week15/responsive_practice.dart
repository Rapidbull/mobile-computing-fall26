import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(home: NotesHome()));
const notes = [
  'Buy milk',
  'Call the dentist',
  'Finish the README',
  'Plan the final demo',
];

class NoteList extends StatelessWidget {
  const NoteList({super.key, required this.selected, required this.onTap});
  final int? selected; // highlighted row, or null
  final void Function(int index) onTap; // what to do on a tap
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: notes.length,
      itemBuilder: (context, i) => ListTile(
        title: Text(notes[i]),
        selected: i == selected,
        onTap: () => onTap(i),
      ),
    );
  }
}

class NoteDetails extends StatelessWidget {
  const NoteDetails({super.key, required this.index});
  final int index; // which note to show
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        notes[index],
        style: Theme.of(context).textTheme.headlineSmall,
      ),
    );
  }
}

class NotesHome extends StatefulWidget {
  const NotesHome({super.key});

  @override
  State<NotesHome> createState() => _NotesHomeState();
}

class _NotesHomeState extends State<NotesHome> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notes')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 600) {
            return _twoPanes();
          }
          return _onePane(context);
        },
      ),
    );
  }

  Widget _twoPanes() {
    return Row(
      children: [
        SizedBox(
          width: 250,
          child: NoteList(
            selected: _selected,
            onTap: (i) => setState(() => _selected = i),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: NoteDetails(index: _selected)),
      ],
    );
  }

  Widget _onePane(BuildContext context) {
    return NoteList(
      selected: null,
      onTap: (i) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Note')),
            body: NoteDetails(index: i),
          ),
        ),
      ),
    );
  }
}
