import 'dart:ui';

import 'package:flutter/material.dart';

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.sigma = 24,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double sigma;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .18),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: dark
                  ? Colors.black.withValues(alpha: .4)
                  : Colors.white.withValues(alpha: .6),
              borderRadius: borderRadius,
              border: Border.all(
                color: Colors.white.withValues(alpha: dark ? .16 : .85),
                width: 1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class GlassBottomNavigation extends StatelessWidget {
  const GlassBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  static const height = 64.0;
  static const sideMargin = 12.0;
  static const bottomMargin = 12.0;
  static const contentInset = height + bottomMargin + 8;

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final idle = dark
        ? Colors.white.withValues(alpha: .78)
        : Colors.black.withValues(alpha: .62);
    return GlassPanel(
      borderRadius: const BorderRadius.all(Radius.circular(32)),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            for (final (index, destination) in destinations.indexed)
              Expanded(
                child: Semantics(
                  container: true,
                  button: true,
                  selected: index == selectedIndex,
                  child: Tooltip(
                    message: destination.label,
                    excludeFromSemantics: true,
                    child: InkWell(
                      key: ValueKey('glass-nav-$index'),
                      onTap: () => onDestinationSelected(index),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: index == selectedIndex
                                    ? colors.primary.withValues(
                                        alpha: dark ? .26 : .16,
                                      )
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: IconTheme(
                                data: IconThemeData(
                                  size: 21,
                                  color: index == selectedIndex
                                      ? colors.primary
                                      : idle,
                                ),
                                child: index == selectedIndex
                                    ? destination.selectedIcon ??
                                          destination.icon
                                    : destination.icon,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              destination.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.1,
                                fontWeight: index == selectedIndex
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: index == selectedIndex
                                    ? colors.primary
                                    : idle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class GlassBackToTopButton extends StatelessWidget {
  const GlassBackToTopButton({
    super.key,
    required this.visible,
    this.onPressed,
  });

  static const size = 46.0;

  final bool visible;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, .35),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: IgnorePointer(
          ignoring: !visible,
          child: GlassPanel(
            borderRadius: const BorderRadius.all(Radius.circular(size / 2)),
            child: SizedBox(
              width: size,
              height: size,
              child: IconButton(
                key: const ValueKey('glass-back-to-top'),
                tooltip: '回到顶部',
                onPressed: onPressed,
                icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 28),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
