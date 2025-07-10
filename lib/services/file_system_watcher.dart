import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as path;
import '../models/song.dart';
import 'database_service.dart';
import 'macos_file_scanner.dart';

/// 文件系统监控服务
/// 用于监控音乐文件夹的变化并自动更新音乐库
class FileSystemWatcher {
  final DatabaseService _databaseService = DatabaseService();
  final MacOSFileScanner _scanner = MacOSFileScanner();
  final Map<String, StreamSubscription<FileSystemEvent>> _watchers = {};
  final Map<String, Timer> _debounceTimers = {};

  static const Duration _debounceDelay = Duration(seconds: 2);

  /// 开始监控指定文件夹
  Future<void> startWatching(String directoryPath) async {
    try {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        return;
      }

      // 如果已经在监控，先停止
      await stopWatching(directoryPath);

      // 创建文件系统监控器
      final watcher = directory.watch(events: FileSystemEvent.all, recursive: true);

      final subscription = watcher.listen(
        (event) => _handleFileSystemEvent(event),
        onError: (error) {
          print('文件系统监控错误: $error');
        },
      );

      _watchers[directoryPath] = subscription;
      print('开始监控文件夹: $directoryPath');
    } catch (e) {
      print('启动文件系统监控失败: $e');
    }
  }

  /// 停止监控指定文件夹
  Future<void> stopWatching(String directoryPath) async {
    final subscription = _watchers.remove(directoryPath);
    await subscription?.cancel();

    // 取消任何挂起的防抖定时器
    _debounceTimers[directoryPath]?.cancel();
    _debounceTimers.remove(directoryPath);

    print('停止监控文件夹: $directoryPath');
  }

  /// 停止所有监控
  Future<void> stopAllWatching() async {
    final futures = _watchers.keys.map((path) => stopWatching(path)).toList();
    await Future.wait(futures);
  }

  /// 处理文件系统事件
  void _handleFileSystemEvent(FileSystemEvent event) {
    final filePath = event.path;

    // 检查是否为音乐文件
    if (!_scanner.isSupportedAudioFile(filePath)) {
      return;
    }

    // 检查是否应该忽略此文件
    if (_scanner.shouldIgnoreFile(filePath)) {
      return;
    }

    // 使用防抖来避免频繁的事件处理
    final directoryPath = path.dirname(filePath);
    _debounceTimers[directoryPath]?.cancel();

    _debounceTimers[directoryPath] = Timer(_debounceDelay, () {
      _processFileEvent(event);
    });
  }

  /// 处理具体的文件事件
  Future<void> _processFileEvent(FileSystemEvent event) async {
    try {
      switch (event.type) {
        case FileSystemEvent.create:
          await _handleFileCreated(event.path);
          break;
        case FileSystemEvent.modify:
          await _handleFileModified(event.path);
          break;
        case FileSystemEvent.delete:
          await _handleFileDeleted(event.path);
          break;
        case FileSystemEvent.move:
          if (event is FileSystemMoveEvent) {
            await _handleFileMoved(event.path, event.destination);
          }
          break;
      }
    } catch (e) {
      print('处理文件事件失败: $e');
    }
  }

  /// 处理文件创建事件
  Future<void> _handleFileCreated(String filePath) async {
    print('检测到新文件: $filePath');

    // 检查文件是否已存在于数据库中
    if (await _databaseService.songExists(filePath)) {
      return;
    }

    // 处理新文件
    final file = File(filePath);
    if (await file.exists()) {
      final song = await _scanner.processMusicFile(file);
      if (song != null) {
        await _databaseService.insertSong(song);
        print('自动添加新音乐文件: ${song.title}');

        // 通知UI更新（可以通过回调或事件总线实现）
        _onSongAdded?.call(song);
      }
    }
  }

  /// 处理文件修改事件
  Future<void> _handleFileModified(String filePath) async {
    print('检测到文件修改: $filePath');

    // 检查文件是否存在于数据库中
    if (!await _databaseService.songExists(filePath)) {
      // 如果不存在，作为新文件处理
      await _handleFileCreated(filePath);
      return;
    }

    // 重新读取文件元数据并更新
    final file = File(filePath);
    if (await file.exists()) {
      final song = await _scanner.processMusicFile(file);
      if (song != null) {
        await _databaseService.updateSong(song);
        print('自动更新音乐文件: ${song.title}');

        _onSongUpdated?.call(song);
      }
    }
  }

  /// 处理文件删除事件
  Future<void> _handleFileDeleted(String filePath) async {
    print('检测到文件删除: $filePath');

    // 从数据库中删除歌曲记录
    final songs = await _databaseService.getSongsByFilePath(filePath);
    for (final song in songs) {
      await _databaseService.deleteSong(song.id);
      print('自动删除音乐文件记录: ${song.title}');

      _onSongDeleted?.call(song);
    }
  }

  /// 处理文件移动事件
  Future<void> _handleFileMoved(String oldPath, String? newPath) async {
    print('检测到文件移动: $oldPath -> $newPath');

    if (newPath == null) {
      // 视为删除
      await _handleFileDeleted(oldPath);
      return;
    }

    // 更新数据库中的文件路径
    final songs = await _databaseService.getSongsByFilePath(oldPath);
    for (final song in songs) {
      final updatedSong = song.copyWith(filePath: newPath);
      await _databaseService.updateSong(updatedSong);
      print('自动更新文件路径: ${song.title}');

      _onSongUpdated?.call(updatedSong);
    }
  }

  // 事件回调
  Function(Song)? _onSongAdded;
  Function(Song)? _onSongUpdated;
  Function(Song)? _onSongDeleted;

  /// 设置事件回调
  void setEventCallbacks({
    Function(Song)? onSongAdded,
    Function(Song)? onSongUpdated,
    Function(Song)? onSongDeleted,
  }) {
    _onSongAdded = onSongAdded;
    _onSongUpdated = onSongUpdated;
    _onSongDeleted = onSongDeleted;
  }

  /// 获取当前监控的文件夹列表
  List<String> get watchedDirectories => _watchers.keys.toList();

  /// 检查是否正在监控指定文件夹
  bool isWatching(String directoryPath) => _watchers.containsKey(directoryPath);
}
