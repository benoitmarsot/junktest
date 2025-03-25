
// import 'package:flutter/material.dart';
// import 'package:codechatui/src/home_page.dart';
// import 'package:codechatui/src/chat_page.dart';
// import 'package:codechatui/src/models/project.dart';

// class App extends StatelessWidget {
//   const App({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'CodeChat',
//       theme: ThemeData(
//         primarySwatch: Colors.blue,
//       ),
//       home: const HomePage(),
//       onGenerateRoute: (settings) {
//         if (settings.name == 'chat') {
//           final project = settings.arguments as Project;
//           return MaterialPageRoute(
//             builder: (context) => ChatPage(project: project),
//           );
//         }
//         return null;
//       },
//     );
//   }
// }
