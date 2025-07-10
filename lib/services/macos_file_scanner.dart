import 'dart:io';
import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import '../models/song.dart';
import 'database_service.dart';

/// macOS 优化的文件扫描服务
/// 专门针对 macOS 文件系统特点进行优化
class MacOSFileScanner {
  final DatabaseService _databaseService = DatabaseService();

  // macOS 常见的音乐目录
  static const List<String> macOSMusicPaths = [
    '/Users/{username}/Music',
    '/Users/{username}/Music/iTunes/iTunes Media/Music',
    '/Users/{username}/Music/Music/Media.localized/Music',
    '/Users/{username}/Downloads',
    '/System/Volumes/Data/Users/{username}/Music',
  ];

  // macOS 应该忽略的文件和目录
  static const List<String> macOSIgnorePatterns = [
    '.DS_Store',
    '.AppleDouble',
    '.LSOverride',
    'Icon\r', // macOS 图标文件
    '._*', // 资源分叉文件
    '.Spotlight-V100',
    '.Trashes',
    '.VolumeIcon.icns',
    '.com.apple.timemachine.donotpresent',
    '.fseventsd',
    '.TemporaryItems',
    'Network Trash Folder',
    'Temporary Items',
    '.apdisk',
    '.DocumentRevisions-V100',
    '.PKInstallSandboxManager',
    '.PKInstallSandboxManager-SystemSoftware',
  ];

  // 支持的音频格式
  static const List<String> supportedExtensions = ['.mp3', '.flac', '.wav', '.aac', '.m4a', '.ogg', '.wma', '.alac', '.aiff'];

  /// 检查文件是否应该被忽略（macOS 特定优化）
  bool shouldIgnoreFile(String filePath) {
    final fileName = path.basename(filePath);
    final dirName = path.dirname(filePath);

    // 检查文件名模式
    for (final pattern in macOSIgnorePatterns) {
      if (pattern.endsWith('*')) {
        final prefix = pattern.substring(0, pattern.length - 1);
        if (fileName.startsWith(prefix)) {
          return true;
        }
      } else if (fileName == pattern) {
        return true;
      }
    }

    // 忽略隐藏文件夹（以.开头的文件夹，除了一些特殊情况）
    if (dirName.contains('/.') && !dirName.contains('/.Trash')) {
      return true;
    }

    // 忽略系统保护的目录
    final systemProtectedPaths = [
      '/System/',
      '/Library/',
      '/usr/',
      '/bin/',
      '/sbin/',
      '/private/',
    ];

    for (final protectedPath in systemProtectedPaths) {
      if (filePath.startsWith(protectedPath)) {
        return true;
      }
    }

    return false;
  }

  /// 检查文件是否为支持的音频格式
  bool isSupportedAudioFile(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    return supportedExtensions.contains(extension);
  }

  /// 获取用户的音乐目录路径
  Future<List<String>> _getUserMusicDirectories() async {
    final List<String> musicDirs = [];
    final username = Platform.environment['USER'] ?? Platform.environment['USERNAME'];

    if (username != null) {
      for (final pathTemplate in macOSMusicPaths) {
        final actualPath = pathTemplate.replaceAll('{username}', username);
        final dir = Directory(actualPath);
        if (await dir.exists()) {
          musicDirs.add(actualPath);
        }
      }
    }

    // 添加一些常见的额外路径
    final additionalPaths = [
      '/Users/Shared/Music',
      '/Volumes', // 外部驱动器
    ];

    for (final additionalPath in additionalPaths) {
      final dir = Directory(additionalPath);
      if (await dir.exists()) {
        musicDirs.add(additionalPath);
      }
    }

    return musicDirs;
  }

  /// 智能扫描音乐文件
  /// 使用并发处理和智能缓存来优化性能
  Future<List<Song>> scanDirectory(
    String directoryPath, {
    bool recursive = true,
    Function(int current, int total)? onProgress,
    bool useCache = true,
  }) async {
    final List<Song> songs = [];
    final List<File> musicFiles = [];

    // 首先收集所有音频文件
    await _collectMusicFiles(directoryPath, musicFiles, recursive: recursive);

    if (onProgress != null) {
      onProgress(0, musicFiles.length);
    }

    // 并发处理文件，但限制并发数以避免过载
    const int maxConcurrency = 4; // macOS 优化的并发数
    final semaphore = Semaphore(maxConcurrency);

    final List<Future<Song?>> futures = musicFiles.map((file) async {
      await semaphore.acquire();
      try {
        if (useCache && await _databaseService.songExists(file.path)) {
          return null; // 文件已存在，跳过
        }
        return await _processMusicFile(file);
      } finally {
        semaphore.release();
      }
    }).toList();

    int completed = 0;
    for (final future in futures) {
      final song = await future;
      if (song != null) {
        songs.add(song);
      }
      completed++;
      if (onProgress != null) {
        onProgress(completed, musicFiles.length);
      }
    }

    return songs;
  }

  /// 收集目录中的所有音乐文件
  Future<void> _collectMusicFiles(
    String directoryPath,
    List<File> musicFiles, {
    bool recursive = true,
  }) async {
    try {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        return;
      }

      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File) {
          // 检查是否应该忽略此文件
          if (shouldIgnoreFile(entity.path)) {
            continue;
          }

          // 检查是否为支持的音频文件
          if (isSupportedAudioFile(entity.path)) {
            musicFiles.add(entity);
          }
        } else if (entity is Directory && recursive) {
          // 检查是否应该忽略此目录
          if (shouldIgnoreFile(entity.path)) {
            continue;
          }

          // 递归扫描子目录
          await _collectMusicFiles(entity.path, musicFiles, recursive: recursive);
        }
      }
    } catch (e) {
      // 忽略权限错误和其他访问错误，继续扫描其他目录
      print('扫描目录 $directoryPath 时出错: $e');
    }
  }

  /// 处理单个音乐文件
  Future<Song?> processMusicFile(File file) async {
    return await _processMusicFile(file);
  }

  /// 处理单个音乐文件（内部方法）
  Future<Song?> _processMusicFile(File file) async {
    try {
      final filePath = file.path;

      // 基本信息
      String title = '';
      String artist = '';
      String album = 'Unknown Album';
      Uint8List? albumArtData;
      bool hasLyrics = false;
      String? embeddedLyrics;
      Duration songDuration = Duration.zero;

      try {
        // 读取元数据
        final metadata = readMetadata(file, getImage: true);

        title = metadata.title ?? '';
        artist = metadata.artist ?? '';
        album = metadata.album ?? 'Unknown Album';

        if (metadata.pictures.isNotEmpty) {
          albumArtData = metadata.pictures.first.bytes;
        }

        songDuration = metadata.duration ?? Duration.zero;
        embeddedLyrics = metadata.lyrics;

        if (embeddedLyrics != null && embeddedLyrics.isNotEmpty) {
          hasLyrics = true;
        }
      } catch (e) {
        // 元数据读取失败，使用文件名作为备用
        print('读取元数据失败 $filePath: $e');
      }

      // 从文件名提取信息（如果元数据为空）
      if (title.isEmpty) {
        final extractedInfo = _extractTitleAndArtistFromFileName(filePath);
        title = extractedInfo['title'] ?? path.basenameWithoutExtension(filePath);
        if (artist.isEmpty) {
          artist = extractedInfo['artist'] ?? 'Unknown Artist';
        }
      }

      // 检查同名 LRC 文件
      if (!hasLyrics) {
        final lrcPath = '${path.withoutExtension(filePath)}.lrc';
        final lrcFile = File(lrcPath);
        if (await lrcFile.exists()) {
          hasLyrics = true;
        }
      }

      // 创建歌曲对象
      final song = Song(
        id: '${DateTime.now().millisecondsSinceEpoch}_${filePath.hashCode}',
        title: title,
        artist: artist,
        album: album,
        filePath: filePath,
        duration: songDuration,
        albumArt: albumArtData,
        hasLyrics: hasLyrics,
        embeddedLyrics: embeddedLyrics,
      );

      return song;
    } catch (e) {
      print('处理文件失败 ${file.path}: $e');
      return null;
    }
  }

  /// 从文件名中提取标题和艺术家信息
  Map<String, String?> _extractTitleAndArtistFromFileName(String filePath) {
    final fileName = path.basenameWithoutExtension(filePath);

    // 常见的分隔符
    final separators = [' - ', ' – ', ' — ', ' | ', '_'];

    for (final separator in separators) {
      if (fileName.contains(separator)) {
        final parts = fileName.split(separator);
        if (parts.length >= 2) {
          String part1 = parts[0].trim();
          String part2 = parts[1].trim();

          // 去除常见的曲目编号前缀
          final trackNumberPattern = RegExp(r'^\d+\.?\s*');
          part1 = part1.replaceFirst(trackNumberPattern, '');

          // 通常格式为 "艺术家 - 标题" 或 "标题 - 艺术家"
          // 根据长度和内容判断哪个更可能是标题
          if (part1.length > part2.length) {
            return {'title': part1, 'artist': part2};
          } else {
            return {'title': part2, 'artist': part1};
          }
        }
      }
    }

    // 如果没有找到分隔符，整个文件名作为标题
    String cleanTitle = fileName.replaceFirst(RegExp(r'^\d+\.?\s*'), '');
    return {'title': cleanTitle, 'artist': null};
  }

  /// 获取系统音乐目录的建议扫描路径
  Future<List<String>> getSuggestedMusicDirectories() async {
    return await _getUserMusicDirectories();
  }

  /// 快速检查目录是否包含音乐文件
  Future<bool> directoryContainsMusic(String directoryPath) async {
    try {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        return false;
      }

      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File && isSupportedAudioFile(entity.path)) {
          return true;
        } else if (entity is Directory && !shouldIgnoreFile(entity.path)) {
          // 递归检查一级子目录
          if (await directoryContainsMusic(entity.path)) {
            return true;
          }
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}

/// 简单的信号量实现，用于控制并发
class Semaphore {
  int _permits;
  final Queue<Completer<void>> _waitQueue = Queue<Completer<void>>();

  Semaphore(this._permits);

  Future<void> acquire() async {
    if (_permits > 0) {
      _permits--;
      return;
    } else {
      final completer = Completer<void>();
      _waitQueue.add(completer);
      return completer.future;
    }
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeFirst();
      completer.complete();
    } else {
      _permits++;
    }
  }
}
