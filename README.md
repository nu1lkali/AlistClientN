# AlistClient N

基于 [AlistClient](https://github.com/BFWXKJGS/AlistClient) 的增强版 Android 客户端，感谢原作者 [BFWXKJGS](https://github.com/BFWXKJGS) 的开源贡献。


## 下载

**GitHub Releases**
https://github.com/nu1lkali/AlistClientN/releases

**蓝奏云**
https://wwanb.lanzoum.com/b016kpl6ub
密码:cwc3

## 新增功能

**文件列表**
- 目录过滤：不过滤 / 仅视频 / 仅图片
- 网格视图文件夹封面（优先视频 thumb，其次图片）
- 视频文件显示观看进度条
- 图片/视频按日期分组显示
- 多选模式：批量下载、删除、移动
- 文件夹详情支持计算大小
- 排序新增随机模式、按文件大小排序
- 一键按文件类型分类
- 提取并整理：递归提取子文件夹文件并按类型归类
- 随机播放视频：当前目录随机选择视频播放
- 递归随机播放：使用随机路径探测算法在子目录中查找视频并播放
    
    随机路径探测算法是一种以空间换时间的优化策略，通过牺牲"找到所有视频"的完整性，换取"快速找到一个视频"的效率。在大型文件系统中，这种算法能将用户等待时间从分钟级降低到秒级，极大提升用户体验。
    这个算法的核心价值在于：不是找到最优解，而是快速找到可用解。

- 智能预加载缓存：局域网环境下自动预加载子目录（可在设置中关闭）
- **路径导航增强**：
  - 点击 AppBar 路径显示完整导航菜单
  - 支持直接跳转到根目录
  - 保留页面栈，避免重复页面创建
  - 优化返回逻辑，确保返回操作正确导航到预期页面

**IPTV 直播**
- 支持 M3U/M3U8/TXT 播放列表，可从 Alist 文件 URL 或直接 URL 导入
- 按 group-title 分组显示频道，保持原始分类顺序，左侧分组导航 + 右侧频道列表
- 频道 Logo 显示
- 使用 media_kit 播放 HLS/m3u8 直播流，支持 rtmp/rtsp/mms 等协议
- 自动检测 HLS 流，直接跳转播放器无需解析频道列表
- 大文件（>500KB）使用 Isolate 异步解析，不阻塞 UI
- 播放器支持上一个/下一个频道切换，控制栏 4 秒无操作自动隐藏

**视频播放器**
- 播放列表侧边栏（顶部栏按钮触发，支持全屏模式）
- 视频截图保存到相册
- 播放中删除当前视频
- 视频信息查看：文件名、大小、时长、分辨率、目录路径
- 冷门格式（rmvb/avi/wmv 等）自动切换 ijkplayer 内核
- 新增更多视频格式支持（webm/divx/m2ts 等）
- 全屏模式下所有按钮完全适配
- 播放进度自动记录，下次打开从上次位置继续

**图片画廊**
- 图片旋转
- 幻灯片自动播放
- 图片信息弹窗（分辨率、大小、EXIF 信息等）
  - 相机型号、拍摄时间
  - ISO、光圈、快门速度、焦距
  - GPS 位置信息
- 智能预加载：前后各预加载 5 张图片
- 内存与磁盘缓存优化
- HEIC/HEIF 格式支持（自动转换为 JPEG 显示）

**文件搜索**
- 搜索结果支持多选批量下载
- 搜索历史记录
- 快速重复搜索
- 一键清空历史

**缓存管理**
- 视频缓存统计与清理
- 一键清除全部缓存

**收藏夹**
- 随机打开收藏的图片
- 随机播放收藏的视频

**UI 优化**
- 圆角卡片设计，增强视觉层次
- 优化图标透明度和配色
- 改进颜色选择器交互体验
- 音乐播放器支持获取音频封面文件

## UI 截图

### 文件列表界面
![文件列表](https://img.erpweb.eu.org/imgs/2026/04/2ff3cae272e1915f.jpg)

### 路径导航菜单
![路径导航](https://img.erpweb.eu.org/imgs/2026/04/aa7518e5d18fbd96.jpg)

### 视频播放器
![视频播放器](https://img.erpweb.eu.org/imgs/2026/04/ef361608e25743f7.jpg)

### 图片画廊
![图片画廊](https://img.erpweb.eu.org/imgs/2026/04/7f71f3cf43822283.jpg)

### IPTV 直播
![IPTV 直播](https://img.erpweb.eu.org/imgs/2026/04/91ca257bb62f2d09.jpg)

### 搜索功能
![搜索功能](https://img.erpweb.eu.org/imgs/2026/04/c96448889173df98.jpg)

### 收藏夹
![收藏夹](https://img.erpweb.eu.org/imgs/2026/04/64442e665e6bca3b.jpg)

## 构建

需要 Flutter 3.13.8：

```bash
flutter pub get
flutter build apk --release --no-tree-shake-icons
```

构建产物位于 `build/app/outputs/flutter-apk/` 目录，包含以下 APK：
- `app-arm64-v8a-release.apk` (ARM 64位，推荐大多数手机)
- `app-armeabi-v7a-release.apk` (ARM 32位)
- `app-x86_64-release.apk` (x86 64位，适用于模拟器)
- `app-release.apk` (通用包，包含所有架构)

## 致谢

本项目基于 [AlistClient](https://github.com/BFWXKJGS/AlistClient) 开发，感谢原作者的开源贡献。

---

## 更新记录（近期新增）

**IPTV 直播**
- 支持 M3U/M3U8/TXT 播放列表，可从 Alist 文件 URL 或直接 URL 导入
- 按 group-title 分组显示频道，保持原始分类顺序，左侧分组导航 + 右侧频道列表
- 频道 Logo 显示
- 使用 media_kit 播放 HLS/m3u8 直播流，支持 rtmp/rtsp/mms 等协议
- 自动检测 HLS 流，直接跳转播放器无需解析频道列表
- 大文件（>500KB）使用 Isolate 异步解析，不阻塞 UI
- 播放器支持上一个/下一个频道切换，控制栏 4 秒无操作自动隐藏

**视频播放器**
- 播放进度自动记录，下次打开从上次位置继续
- 视频截图保存到相册

**收藏夹**
- 随机打开收藏的图片
- 随机播放收藏的视频

**文件列表**
- 递归随机播放 LRU 路径惩罚：80% 概率跳过最近访问过的目录，避免重复

