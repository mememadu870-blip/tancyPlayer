# Plan

## 架构

- `UI`: Compose + `MainViewModel`
- `Domain`: 播放控制、定时器、去重逻辑
- `Data`:
  - `MusicScanner` 读取 `MediaStore`
  - `LibraryRepository` 管理本地 JSON（曲库、歌单、收藏）
  - `HashUtils` 计算音频内容 `SHA-256`

## 核心流程

1. 授权读取媒体权限
2. 扫描本地音频，生成曲库
3. 提交队列给 `ExoPlayer`
4. UI 执行播放控制与管理操作
5. 查重时逐首读取音频流计算 hash，按 hash 分组并提示

## 关键权衡

- 第一版使用 JSON 持久化，减少实现复杂度，后续可平滑升级到 Room
- Hash 计算以准确性优先，采用整文件读取
- UI 采用单页操作流，优先保证功能闭环
