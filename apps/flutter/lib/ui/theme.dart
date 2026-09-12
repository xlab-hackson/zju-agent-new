import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

const paper = Color(0xfff3ecdc),
    paperCard = Color(0xfffdfaf2),
    ink = Color(0xff22304e),
    blue = Color(0xff003f88),
    gold = Color(0xffb08d3e),
    seal = Color(0xffb03a2e);
ThemeData paperTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: paper,
  fontFamily: 'NotoSerifSC',
  colorScheme: ColorScheme.fromSeed(
    seedColor: blue,
    surface: paperCard,
    error: seal,
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w800,
      color: ink,
    ),
    headlineMedium: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: ink,
    ),
    bodyMedium: TextStyle(color: ink, height: 1.65),
  ),
  cardTheme: CardThemeData(
    color: paperCard,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(3),
      side: const BorderSide(color: Color(0x2422304e)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: paperCard,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(3)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
    ),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: paper,
    foregroundColor: ink,
    elevation: 0,
  ),
);

class Paper extends StatelessWidget {
  const Paper({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? paperCard,
      border: Border.all(color: ink.withValues(alpha: .14)),
      borderRadius: BorderRadius.circular(3),
      boxShadow: const [
        BoxShadow(color: Color(0x110e1c38), offset: Offset(2, 3)),
      ],
    ),
    child: child,
  );
}

class PaperLines extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ink.withValues(alpha: .025)
      ..strokeWidth = .5;
    for (double y = 0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(PaperLines oldDelegate) => false;
}

class NoScrollbarScrollBehavior extends MaterialScrollBehavior {
  const NoScrollbarScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}
