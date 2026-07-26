import 'package:flutter/material.dart';

import '../theme/yoma_theme.dart';
import 'referral_screen.dart';
import 'screening_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yoma Triage'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            const Text(
              'Community Health Officer',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Screen breathing or start an emergency referral.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const Spacer(),
            Semantics(
              button: true,
              label: 'Screen Breathing',
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(72),
                  textStyle: const TextStyle(fontSize: 20),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ScreeningScreen()),
                  );
                },
                child: const Text('Screen Breathing'),
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              button: true,
              label: 'Emergency Referral',
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(72),
                  foregroundColor: YomaColors.danger,
                  side: const BorderSide(color: YomaColors.danger, width: 2),
                  textStyle: const TextStyle(fontSize: 20),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ReferralScreen()),
                  );
                },
                child: const Text('Emergency Referral'),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
