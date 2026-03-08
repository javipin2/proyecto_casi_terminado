import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LegalTextScreen extends StatelessWidget {
  final String title;
  final String body;

  const LegalTextScreen({
    super.key,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            body,
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.45,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

