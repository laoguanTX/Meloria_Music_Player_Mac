import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../providers/music_provider.dart';

/// macOS 文件扫描优化设置组件
class MacOSOptimizationSettings extends StatefulWidget {
  const MacOSOptimizationSettings({super.key});

  @override
  State<MacOSOptimizationSettings> createState() => _MacOSOptimizationSettingsState();
}

class _MacOSOptimizationSettingsState extends State<MacOSOptimizationSettings> {
  bool _isScanning = false;
  List<String> _suggestedDirectories = [];

  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS) {
      _loadSuggestedDirectories();
    }
  }

  Future<void> _loadSuggestedDirectories() async {
    if (!mounted) return;

    final musicProvider = context.read<MusicProvider>();
    final suggestions = await musicProvider.getSuggestedMusicDirectories();

    if (mounted) {
      setState(() {
        _suggestedDirectories = suggestions;
      });
    }
  }

  Future<void> _addSuggestedDirectory(String directoryPath) async {
    setState(() {
      _isScanning = true;
    });

    try {
      final musicProvider = context.read<MusicProvider>();

      // 使用新的方法直接添加指定路径的文件夹
      await musicProvider.addSpecificMusicFolder(directoryPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已添加文件夹: ${directoryPath.split('/').last}'),
            backgroundColor: Colors.green,
          ),
        );

        // 重新加载建议文件夹列表
        await _loadSuggestedDirectories();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('添加文件夹失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.apple,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'macOS 优化',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '智能文件夹检测',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '系统已为您检测到以下可能包含音乐文件的文件夹：',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 12),
            if (_suggestedDirectories.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: theme.colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '未检测到常见的音乐文件夹',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...(_suggestedDirectories.map((dir) => _buildSuggestedDirectoryTile(dir, theme))),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.settings_outlined,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'macOS 特殊优化',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildOptimizationFeature(
              theme,
              '智能文件过滤',
              '自动忽略 .DS_Store、._* 等 macOS 系统文件',
              Icons.filter_alt_outlined,
              true,
            ),
            const SizedBox(height: 8),
            _buildOptimizationFeature(
              theme,
              '实时文件监控',
              '自动检测音乐文件夹中的文件变化',
              Icons.visibility_outlined,
              true,
            ),
            const SizedBox(height: 8),
            _buildOptimizationFeature(
              theme,
              '并发扫描优化',
              '使用多线程扫描，专为 macOS 文件系统优化',
              Icons.speed_outlined,
              true,
            ),
            const SizedBox(height: 8),
            _buildOptimizationFeature(
              theme,
              'ALAC/AIFF 支持',
              '完整支持 Apple 无损音频格式',
              Icons.high_quality_outlined,
              true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestedDirectoryTile(String directory, ThemeData theme) {
    final folderName = directory.split('/').last;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.3),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(
          Icons.folder_outlined,
          color: theme.colorScheme.primary,
        ),
        title: Text(
          folderName,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          directory,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _isScanning
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => _addSuggestedDirectory(directory),
                tooltip: '添加此文件夹',
              ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }

  Widget _buildOptimizationFeature(
    ThemeData theme,
    String title,
    String description,
    IconData icon,
    bool isEnabled,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isEnabled ? theme.colorScheme.primaryContainer.withOpacity(0.3) : theme.colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: isEnabled ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: isEnabled ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isEnabled ? theme.colorScheme.onPrimaryContainer.withOpacity(0.8) : theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            isEnabled ? Icons.check_circle : Icons.info_outline,
            size: 16,
            color: isEnabled ? Colors.green : theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
