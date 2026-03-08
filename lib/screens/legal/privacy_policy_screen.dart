import 'package:flutter/material.dart';
import 'package:reserva_canchas/screens/legal/legal_text_screen.dart';
import 'package:reserva_canchas/screens/legal/legal_texts.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalTextScreen(
      title: 'Política de Privacidad',
      body: kPrivacyPolicyText,
    );
  }
}

