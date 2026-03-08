import 'package:flutter/material.dart';
import 'package:reserva_canchas/screens/legal/legal_text_screen.dart';
import 'package:reserva_canchas/screens/legal/legal_texts.dart';

class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalTextScreen(
      title: 'Términos y Condiciones',
      body: kTermsAndConditionsText,
    );
  }
}

