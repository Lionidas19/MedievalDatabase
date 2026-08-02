import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_controller.dart';

/// Shown only very briefly on startup while the bundled database loads, or
/// if that load somehow fails (in which case it offers to retry).
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: scheme.primaryContainer,
                child: Icon(Icons.castle_outlined, size: 36, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(height: 24),
              Text('Medieval Price Explorer', style: textTheme.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              if (app.error == null) ...[
                const SizedBox(height: 8),
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text('Loading database…', style: TextStyle(color: scheme.onSurfaceVariant)),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    app.error!,
                    style: TextStyle(color: scheme.onErrorContainer),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: app.isLoading ? null : () => app.resetToBundledDefault(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
