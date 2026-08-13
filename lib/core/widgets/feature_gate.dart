import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../version/panel_feature.dart';
import '../version/panel_version_provider.dart';
import 'animated_reveal.dart';

/// 功能不受当前面板版本支持时，显示在页面主体最上方的提示条。
///
/// 功能可用（或面板版本未知）时渲染为 [SizedBox.shrink]，因此可以无条件
/// 插入到页面布局中。尚未随正式版发布的功能用 tertiaryContainer 配色，
/// 版本过低的功能用 errorContainer 配色。
class FeatureUnsupportedBanner extends ConsumerWidget {
  const FeatureUnsupportedBanner({super.key, required this.feature});

  final PanelFeature feature;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(cachedPanelVersionProvider);
    final unsupported = !isFeatureSupported(feature, version);
    // 面板版本是异步探测的，横幅往往比页面主体晚一步；直接返回不同高度会让
    // 整页内容被顶下去，这里改为展开。
    return AnimatedReveal(
      visible: unsupported,
      child: unsupported
          ? _buildBanner(context, version)
          : const SizedBox.shrink(),
    );
  }

  Widget _buildBanner(BuildContext context, PanelVersion? version) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final unreleased = requiredVersionOf(feature) == kUnreleasedVersion;
    final background = unreleased
        ? colorScheme.tertiaryContainer
        : colorScheme.errorContainer;
    final foreground = unreleased
        ? colorScheme.onTertiaryContainer
        : colorScheme.onErrorContainer;

    return Material(
      color: background,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  featureUnsupportedMessage(feature, version),
                  style: theme.textTheme.bodySmall?.copyWith(color: foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 按面板版本控制整块内容的可见性。
///
/// 功能可用（或面板版本未知）时渲染 [child]；不可用时渲染 [unsupported]，
/// 未提供 [unsupported] 时渲染一个居中的说明页（图标 + 提示文案 + 返回按钮）。
class FeatureGate extends ConsumerWidget {
  const FeatureGate({
    super.key,
    required this.feature,
    required this.child,
    this.unsupported,
  });

  final PanelFeature feature;
  final Widget child;

  /// 功能不可用时的替代内容；不传则使用默认说明页。
  final Widget? unsupported;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(cachedPanelVersionProvider);
    if (isFeatureSupported(feature, version)) return child;
    if (unsupported != null) return unsupported!;

    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.system_update_alt_rounded,
                  size: 56,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  kFeatureNames[feature] ?? '功能不可用',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  featureUnsupportedMessage(feature, version),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.tonal(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('返回'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
