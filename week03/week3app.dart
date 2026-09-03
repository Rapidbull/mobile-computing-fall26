import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
Widget build(BuildContext context) {
  return MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('Lance\'s')),
      body: Center(
        child: Container(
        color: Colors.green.shade50,
        padding: EdgeInsets.all(24),
        child: Container( 
           child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(radius: 50, /* backgroundImage */),
              SizedBox(height: 12),
              Text('Lance', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              Text('Midway Student ect ect', style : TextStyle(fontSize: 15, fontWeight: FontWeight.normal), ),                
              Row(
                 mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                 children: [
                  _statBox('128', 'Followers'),
                  _statBox('12', 'Projects'),
                  _statBox('340', 'Likes'),
                  ],
                  ),
            ],
           ),
         ),
         ),
    
    ), // Checkpoint 1 replaces this
    )
    )
    ;
    
}
  Widget _statBox(String number, String label) {
return Column(children: [Text(number), Text(label)]);
     }
    }