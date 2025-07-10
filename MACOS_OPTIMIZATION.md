# macOS 音乐播放器优化说明

## 概述

本项目针对 macOS 系统特点进行了深度优化，提供了比通用版本更好的性能和用户体验。

## 主要优化功能

### 1. 智能文件扫描 (`MacOSFileScanner`)

**功能特点：**
- 专门针对 macOS 文件系统特点设计
- 智能忽略系统文件和隐藏文件
- 支持并发扫描，提高扫描效率
- 自动识别常见音乐文件夹

**优化细节：**

#### 系统文件过滤
自动忽略以下 macOS 特有文件和文件夹：
- `.DS_Store` - macOS 目录服务存储文件
- `.AppleDouble` - 苹果双重格式文件
- `.LSOverride` - 启动服务覆盖文件
- `Icon\r` - macOS 自定义图标文件
- `._*` - 资源分叉文件
- `.Spotlight-V100` - Spotlight 索引文件
- `.Trashes` - 废纸篓文件夹
- `.VolumeIcon.icns` - 卷图标文件
- `.fseventsd` - 文件系统事件守护进程文件
- 其他系统保护目录

#### 音频格式支持
完整支持以下音频格式：
- `.mp3` - MPEG 音频
- `.flac` - 无损音频压缩
- `.wav` - 未压缩音频
- `.aac` - 高级音频编码
- `.m4a` - MPEG-4 音频
- `.ogg` - Ogg Vorbis
- `.wma` - Windows Media Audio
- `.alac` - Apple 无损音频编码（macOS 特有）
- `.aiff` - 音频交换文件格式（Apple 标准）

#### 智能目录检测
自动检测以下常见音乐目录：
- `/Users/{username}/Music` - 用户音乐文件夹
- `/Users/{username}/Music/iTunes/iTunes Media/Music` - iTunes 音乐库
- `/Users/{username}/Music/Music/Media.localized/Music` - Apple Music 本地文件
- `/Users/{username}/Downloads` - 下载文件夹
- `/System/Volumes/Data/Users/{username}/Music` - 系统卷数据
- `/Users/Shared/Music` - 共享音乐文件夹
- `/Volumes` - 外部驱动器挂载点

### 2. 实时文件监控 (`FileSystemWatcher`)

**功能特点：**
- 实时监控音乐文件夹变化
- 自动添加、更新、删除音乐文件记录
- 防抖处理，避免频繁事件触发
- 智能事件过滤

**监控事件：**
- `CREATE` - 新文件添加时自动导入
- `MODIFY` - 文件修改时更新元数据
- `DELETE` - 文件删除时清理数据库记录
- `MOVE` - 文件移动时更新路径

**防抖机制：**
使用 2 秒防抖延迟，避免快速文件操作时的重复处理。

### 3. 并发优化

**性能优化：**
- 限制并发数为 4（针对 macOS 优化）
- 使用信号量控制资源访问
- 异步处理文件扫描任务
- 智能缓存机制

### 4. 用户界面优化

#### macOS 优化设置面板
在设置页面中添加了专门的 macOS 优化设置面板，包含：
- 智能文件夹检测和一键添加
- 优化功能状态显示
- macOS 特有功能说明

#### 设置面板功能
- **智能文件夹检测**：自动扫描并推荐包含音乐文件的文件夹
- **一键添加**：快速添加推荐的音乐文件夹
- **功能状态**：显示各项优化功能的启用状态

## 技术实现

### 文件扫描优化

```dart
// 并发控制
const int maxConcurrency = 4; // macOS 优化的并发数
final semaphore = Semaphore(maxConcurrency);

// 智能过滤
bool shouldIgnoreFile(String filePath) {
  // 检查系统文件模式
  // 检查隐藏文件夹
  // 检查系统保护目录
}
```

### 实时监控

```dart
// 文件系统监控
final watcher = directory.watch(events: FileSystemEvent.all, recursive: true);

// 防抖处理
Timer(_debounceDelay, () {
  _processFileEvent(event);
});
```

### 元数据处理

```dart
// 使用 audio_metadata_reader 读取元数据
final metadata = readMetadata(File(filePath), getImage: true);

// 智能文件名解析
Map<String, String?> _extractTitleAndArtistFromFileName(String filePath) {
  // 处理常见分隔符: ' - ', ' – ', ' — ', ' | ', '_'
  // 去除曲目编号前缀
  // 智能判断标题和艺术家
}
```

## 配置说明

### 依赖包版本
所有依赖包版本设置为 `any`，避免版本冲突：

```yaml
dependencies:
  # 核心依赖
  audioplayers: any
  file_picker: any
  path_provider: any
  audio_metadata_reader: any
  
  # macOS 特定优化
  watcher: any  # 文件系统监控
```

### 自动扫描配置
- 新添加的文件夹默认启用自动扫描
- 可在文件夹管理界面单独控制每个文件夹的自动扫描状态
- 启用自动扫描的文件夹会实时监控文件变化

## 使用建议

### 最佳实践
1. **首次使用**：建议使用"智能文件夹检测"功能快速添加常见音乐目录
2. **大型音乐库**：对于包含大量文件的音乐库，建议分批添加文件夹
3. **外部驱动器**：外部驱动器中的音乐文件夹建议关闭自动扫描，避免设备断开时出错
4. **性能优化**：定期清理重复歌曲，保持音乐库整洁

### 注意事项
1. **权限要求**：首次访问文件夹时，macOS 可能要求授予访问权限
2. **网络驱动器**：不建议将网络驱动器设置为自动扫描，可能影响性能
3. **系统文件夹**：避免添加系统关键文件夹，程序会自动过滤但建议手动避免

## 更新历史

### v0.1.0 macOS 优化版本
- 新增 macOS 专用文件扫描器
- 新增实时文件系统监控
- 新增智能文件夹检测
- 优化并发处理性能
- 新增 macOS 特有音频格式支持
- 新增 macOS 优化设置界面

## 技术支持

如果在使用过程中遇到问题，请检查：
1. macOS 版本兼容性（建议 macOS 10.15 以上）
2. 文件夹访问权限设置
3. 磁盘空间是否充足
4. 音频文件格式是否受支持

更多技术细节请参考源代码中的注释说明。
