# Tancy Player (Android)

按照 `gstack` 的工程节奏构建：`Think -> Plan -> Build -> Review -> Test -> Ship -> Reflect`。

## 已实现能力

- 本地音乐自动扫描（`MediaStore`）
- 播放控制：播放/暂停、上一首、下一首
- 定时停止（15 分钟、30 分钟、取消）
- 歌单创建、添加歌曲到歌单
- 收藏/取消收藏
- 重复音频提示（按 `SHA-256` 计算 hash 后分组）
- 重复模式：不重复、单曲循环、列表循环
- 通知栏控制（Media3 播放通知）
- 锁屏媒体会话控制（MediaSession）
- 前台播放服务保活（Foreground Service）
- 播放进度展示与拖动跳转（Seek）
- 耳机/蓝牙媒体按键入口（`MEDIA_BUTTON`）

## Flutter 高颜值 UI 版

- Flutter 代码目录：`flutter_player/`
- 入口文件：`flutter_player/lib/main.dart`
- 使用了更现代的视觉风格（渐变、玻璃态卡片、播放底栏、队列卡片）
- 功能已接入：
  - 自动扫描本地音乐
  - 播放/暂停、上一首、下一首、进度拖动
  - 收藏、创建歌单、加歌到歌单
  - 定时停止
  - 重复模式（不循环/单曲/列表）
  - Hash 重复音频检测提示

## GitHub Actions 自动构建 APK

- 工作流文件：`.github/workflows/flutter-android-build.yml`
- 触发方式：
  - push `flutter_player/**` 自动触发
  - 在 GitHub Actions 页面手动触发 `workflow_dispatch`
- 产物：
  - Artifact 名称：`tancy-player-flutter-release-apk`
  - 文件：`app-release.apk`

## 技术栈

- Kotlin + Jetpack Compose
- Media3 ExoPlayer
- Coroutine + StateFlow
- 本地 JSON 持久化（轻量版，便于快速迭代）

## 目录结构

- `app/src/main/java/com/tancy/player/data`: 扫描、数据模型、持久化、Hash
- `app/src/main/java/com/tancy/player/player`: 播放器封装、定时器
- `app/src/main/java/com/tancy/player/ui`: UI 状态和 ViewModel
- `app/src/main/java/com/tancy/player/MainActivity.kt`: 页面和交互入口

## 运行方式

1. 使用 Android Studio 打开 `E:\case\tancyPlayer`
2. 等待 Gradle Sync 完成
3. 连接真机或模拟器（Android 8+）
4. 首次启动授予音频读取权限
5. 点击“扫描音乐”开始建立本地库

## 测试建议

- 扫描后歌曲列表数量是否正确
- 上一首/下一首是否按队列切换
- 定时停止到点后是否暂停
- 歌单创建后能否添加歌曲
- 收藏状态重启后是否保留
- Hash 查重是否能识别同内容不同文件名音频
