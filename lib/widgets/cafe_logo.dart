import 'package:flutter/material.dart';

class CafeLogo extends StatelessWidget {
  const CafeLogo({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: Image.asset(
      'assets/images/logo.jpg',
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: 'Klasik Grounds Cafe logo',
    ),
  );
}
