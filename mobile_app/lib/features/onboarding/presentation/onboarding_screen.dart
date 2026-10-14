import 'package:flutter/material.dart';

import '../../../app/routing/app_routes.dart';
import '../domain/onboarding_repository.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    required this.onboardingRepository,
    this.isReplay = false,
    super.key,
  });

  final OnboardingRepository onboardingRepository;
  final bool isReplay;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _pages = [
    _OnboardingPageData(
      icon: Icons.grid_view_rounded,
      accentIcon: Icons.water_drop_rounded,
      eyebrow: 'Organize with ease',
      title: 'All tanks, one clear view',
      description:
          'Group and find every tank quickly, even when your aquarium grows '
          'to hundreds of tanks.',
    ),
    _OnboardingPageData(
      icon: Icons.auto_awesome_rounded,
      accentIcon: Icons.schedule_rounded,
      eyebrow: 'Feed intelligently',
      title: 'Feed by appetite, not only the clock',
      description:
          'At each scheduled session, AquaSense checks the guppy count and '
          'appetite before calculating a safe portion.',
    ),
    _OnboardingPageData(
      icon: Icons.notifications_active_rounded,
      accentIcon: Icons.verified_user_rounded,
      eyebrow: 'Always in control',
      title: 'Stay informed and in control',
      description:
          'Follow feeding history and alerts, while keeping safe manual '
          'control available when it is needed.',
    ),
  ];

  late final PageController _pageController;
  int _pageIndex = 0;
  bool _isFinishing = false;

  bool get _isLastPage => _pageIndex == _pages.length - 1;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_isFinishing) {
      return;
    }

    setState(() => _isFinishing = true);

    try {
      await widget.onboardingRepository.completeOnboarding();

      if (!mounted) {
        return;
      }

      if (widget.isReplay && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
        return;
      }

      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.signIn, (route) => false);
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save your progress. Please try again.'),
        ),
      );
      setState(() => _isFinishing = false);
    }
  }

  Future<void> _next() async {
    if (_isLastPage) {
      await _finish();
      return;
    }

    await _pageController.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(
                children: [
                  Icon(Icons.water_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'AquaSense',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (!widget.isReplay)
                    TextButton(
                      onPressed: _isFinishing ? null : _finish,
                      child: const Text('Skip'),
                    )
                  else
                    IconButton(
                      tooltip: 'Close onboarding',
                      onPressed: _isFinishing
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (index) => setState(() => _pageIndex = index),
                itemBuilder: (context, index) =>
                    _OnboardingPage(data: _pages[index], pageNumber: index + 1),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                children: [
                  Semantics(
                    label: 'Page ${_pageIndex + 1} of ${_pages.length}',
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _pages.length,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: index == _pageIndex ? 28 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: index == _pageIndex
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _isFinishing ? null : _next,
                    child: _isFinishing
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _isLastPage
                                ? widget.isReplay
                                      ? 'Done'
                                      : 'Get started'
                                : 'Next',
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.data, required this.pageNumber});

  final _OnboardingPageData data;
  final int pageNumber;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.sizeOf(context).height - 260,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _OnboardingIllustration(data: data, pageNumber: pageNumber),
            const SizedBox(height: 36),
            Text(
              data.eyebrow.toUpperCase(),
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              data.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              data.description,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingIllustration extends StatelessWidget {
  const _OnboardingIllustration({required this.data, required this.pageNumber});

  final _OnboardingPageData data;
  final int pageNumber;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      label: 'AquaSense feature illustration $pageNumber',
      image: true,
      child: AspectRatio(
        aspectRatio: 1.45,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.primaryContainer,
                colorScheme.tertiaryContainer,
              ],
            ),
            borderRadius: BorderRadius.circular(32),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: 24,
                top: 24,
                child: _Bubble(
                  size: 52,
                  color: colorScheme.surface.withValues(alpha: 0.58),
                ),
              ),
              Positioned(
                right: 30,
                bottom: 24,
                child: _Bubble(
                  size: 70,
                  color: colorScheme.surface.withValues(alpha: 0.42),
                ),
              ),
              Container(
                width: 124,
                height: 124,
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(36),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withValues(alpha: 0.12),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Icon(data.icon, size: 62, color: colorScheme.primary),
              ),
              Positioned(
                right: 28,
                top: 24,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Icon(
                      data.accentIcon,
                      size: 26,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.icon,
    required this.accentIcon,
    required this.eyebrow,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final IconData accentIcon;
  final String eyebrow;
  final String title;
  final String description;
}
