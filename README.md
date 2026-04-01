# Tancy Player: The Obsidian Conductor

> **Creative North Star:** "The Obsidian Conductor" —— 超越传统的工具感，打造沉浸式的、社论级的移动音乐环境。

Tancy Player 是一款专为追求极致视听体验而设计的 Android 本地音乐播放器。它拒绝传统 Android 界面的方正束缚，采用流体、高对比度的审美，将专辑艺术与播放控制视为数字艺术品。

---

## 🎨 设计哲学：The Sonic Canvas (声色画布)

本项目遵循 **"The Sonic Canvas"** 设计系统，核心原则包括：
- **Intentional Asymmetry (有意的不对称)**：打破容器边界，创造动感。
- **Tonal Depth (色调深度)**：以黑曜石深色 (`#0e0e0e`) 为基调，配合电光蓝 (`#81ecff`) 冲击视觉。
- **Glassmorphism (玻璃拟态)**：悬浮控件采用 60% 透明度结合 20px-30px 的背景模糊，营造轻盈的物理层级感。
- **Editorial Typography (社论级排版)**：Space Grotesk 赋予标题未来感，Inter 确保元数据的高可读性。

---

## 🚀 核心功能

### 已实现能力
- **本地音乐智能扫描**：自动检索媒体库，支持按时长过滤（如过滤 <30s 的铃声）。
- **专业级播放控制**：Media3 ExoPlayer 驱动，支持通知栏、锁屏媒体会话及耳机/蓝牙按键控制。
- **重复音频精准检测**：基于文件 Hash 计算的排重算法，识别内容相同但文件名不同的文件。
- **多维播放模式**：顺序播放、随机播放、单曲循环、列表循环。
- **歌单与收藏**：灵活创建歌单、添加歌曲到队列或指定歌单，收藏心动旋律。
- **前台保活服务**：确保后台稳定播放，不受系统主动杀后台影响。

### 正在进行的改进
- **定时能力重构**：从固定档位升级为 0-180 分钟无级调节，支持“播放完当前歌曲后停止”。
- **增强型交互菜单**：每首歌曲提供“下一首播放”、“发送到”、“详情展示（质量/路径/大小）”等深度操作。
- **系统级集成**：注册为 Android 系统默认音乐播放器，支持从外部文件管理器直接打开播放。
- **性能优化**：优化 Hash 计算速度，提升大规模曲库扫描体验。

---

## 🗺️ 产品路线图 (Roadmap)

1.  **阶段 1：定时器重塑** —— 引入 Slider 滑动设置、启用开关及倒计时同步显示。
2.  **阶段 2：库筛选与搜索** —— 完善时长过滤设置与多维度（标题/歌手/专辑）全局搜索。
3.  **阶段 3：沉浸式 UI** —— 移除冗余播放条，优化底部导航，释放视觉空间。
4.  **阶段 4：交互增强** —— 引入文本滚动显示（Marquee），长按获取全维度歌曲元数据。
5.  **阶段 5：歌单功能闭环** —— 完善歌单详情管理、歌曲移除及二次确认逻辑。
6.  **阶段 6：全流程回归** —— 修复构建警告，触发 GitHub Actions 自动输出发布版 APK。

---

## 🛠️ 技术栈

- **Core**: Kotlin + Jetpack Compose
- **Engine**: Media3 ExoPlayer
- **Reactive**: Coroutines + StateFlow
- **Storage**: 轻量化 JSON 持久化 (SharedPreferences 用于配置保存)
- **Design**: Space Grotesk (Headers) / Inter (Body)
- **CI/CD**: GitHub Actions (`.github/workflows/flutter-android-build.yml`)

---

## 📂 目录结构

- `app/src/main/java/com/tancy/player/data`: 核心逻辑（扫描、模型、持久化、Hash 算法）。
- `app/src/main/java/com/tancy/player/player`: 播放核心（ExoPlayer 封装、定时器管理）。
- `app/src/main/java/com/tancy/player/ui`: UI 表现层（Compose 页面、ViewModel 状态）。
- `flutter_player/`: 高颜值 Flutter UI 实验版目录。

---

## 🚦 运行与测试

1. 使用 Android Studio 打开项目根目录。
2. 首次运行请确保授予 `READ_EXTERNAL_STORAGE` 或 `READ_MEDIA_AUDIO` 权限。
3. 点击“扫描音乐”建立本地索引。
4. **测试建议**：关注 Hash 查重准确率、定时停止精度以及歌单持久化状态。

---

*Update: 2026-04-01*
