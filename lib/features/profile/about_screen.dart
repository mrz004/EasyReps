import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/ui.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('About / Licences')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(APP_NAME, style: text.headlineSmall),
          Text('Version $APP_VERSION'),
          const SizedBox(height: 8),
          const Text(
            'A personal gym and food tracker. Your data stays on this phone, '
            'and optionally in your own Google Drive. No ads, no accounts, no analytics.',
          ),
          const SectionHeader('Food data'),
          const Text(
            'Food search uses Open Food Facts (openfoodfacts.org). The data is available '
            'under the Open Database License (ODbL); contributions are welcome on their site.',
          ),
          const SectionHeader('Exercise data'),
          const Text(
            'Exercises and images come from free-exercise-db '
            '(github.com/yuhonas/free-exercise-db), published under the Unlicense (public domain).',
          ),
          const SectionHeader('Open source licences'),
          OutlinedButton(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: APP_NAME,
              applicationVersion: APP_VERSION,
            ),
            child: const Text('View package licences'),
          ),
        ],
      ),
    );
  }
}
