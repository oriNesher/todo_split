import 'package:flutter/material.dart';
import 'pages/split_todo_page.dart';

void main() => runApp(const TaskSplitApp());

class TaskSplitApp extends StatelessWidget {
  const TaskSplitApp({super.key});

  @override
  Widget build(BuildContext context) {
    // צבע הכתום של הגביע (תתאימי אם תרצי טון אחר)
    const trophyOrange = Color(0xFFFFA733);
    const darkBackground = Color(0xFF05060A); // רקע כללי מאוד כהה
    const darkSurface = Color(0xFF14151F); // כרטיסים, דיאלוגים וכו'

    final darkColorScheme = ColorScheme.fromSeed(
      seedColor: trophyOrange,
      brightness: Brightness.dark,
    );

    final darkTheme = ThemeData(
      useMaterial3: true,
      colorScheme: darkColorScheme.copyWith(
        background: darkBackground,
        surface: darkSurface,
      ),
      scaffoldBackgroundColor: darkBackground,
      cardTheme: CardThemeData(
        color: darkSurface,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
    );

    return MaterialApp(
      title: 'Split To-Do',
      debugShowCheckedModeBanner: false,
      theme: darkTheme, // נשתמש בדארק כ־theme רגיל
      darkTheme: darkTheme, // future-proof, אם תוסיפי לייט־מוד
      themeMode: ThemeMode.dark, // ברירת מחדל: דארק מוד
      home: const SplitTodoPage(),
    );
  }
}
