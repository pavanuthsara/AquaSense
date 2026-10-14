import 'package:flutter/material.dart';

class DevelopmentPlaceholder extends StatelessWidget {
  const DevelopmentPlaceholder({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.description,
    this.action,
    this.uppercaseEyebrow = true,
    super.key,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String description;
  final Widget? action;
  final bool uppercaseEyebrow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Icon(
                        icon,
                        size: 38,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  uppercaseEyebrow ? eyebrow.toUpperCase() : eyebrow,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(title, style: theme.textTheme.headlineMedium),
                const SizedBox(height: 14),
                Text(
                  description,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                if (action != null) ...[const SizedBox(height: 36), action!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
