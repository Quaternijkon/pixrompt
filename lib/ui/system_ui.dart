import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const pixromptSystemUiStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarDividerColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  systemNavigationBarIconBrightness: Brightness.light,
);

Future<void> applyPixromptSystemUi() async {
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(pixromptSystemUiStyle);
}

class PixromptEdgeToEdge extends StatefulWidget {
  const PixromptEdgeToEdge({super.key, required this.child});

  final Widget child;

  @override
  State<PixromptEdgeToEdge> createState() => _PixromptEdgeToEdgeState();
}

class _PixromptEdgeToEdgeState extends State<PixromptEdgeToEdge> {
  @override
  void initState() {
    super.initState();
    applyPixromptSystemUi();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    applyPixromptSystemUi();
  }

  @override
  void dispose() {
    applyPixromptSystemUi();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    applyPixromptSystemUi();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      key: const ValueKey('systemUi.edgeToEdge'),
      value: pixromptSystemUiStyle,
      child: widget.child,
    );
  }
}
