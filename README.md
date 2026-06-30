# AlistClient N

基于 [AlistClient](https://github.com/BFWXKJGS/AlistClient) 的增强版 Android 客户端，用于连接和管理 [Alist](https://github.com/alist-org/alist) 文件列表服务。感谢原作者 [BFWXKJGS](https://github.com/BFWXKJGS) 的开源贡献。

## 特性概览

- 📁 文件浏览与管理（列表/网格视图、多选、排序、批量操作）
- 🎬 多种视频播放模式（标准播放器、TikTok 短视频、STRM 流媒体、MediaKit/libmpv）
- 📺 IPTV 直播（M3U/M3U8/TXT 播放列表）
- 🖼️ 图片画廊（EXIF 信息、幻灯片、HEIC 支持）
- 📖 文档阅读（TXT/Markdown/PDF/Office）
- 🔒 安全锁（手势锁/密码锁）
- ⭐ 收藏夹与最近访问
- 📥 下载管理器（并发下载、断点续传）
- 🌐 多服务器/多账户管理
- 💬 外挂字幕支持

## 下载

**GitHub Releases**
https://github.com/nu1lkali/AlistClientN/releases

**蓝奏云**
https://wwanb.lanzoum.com/b016kpl6ub
密码:cwc3

## 系统要求

| 项目 | 要求 |
|---|---|
| Android 版本 | 8.0（API 26）及以上 |
| 架构 | arm64-v8a / armeabi-v7a / x86_64 |
| Alist 服务端 | 需自行部署 [Alist](https://github.com/alist-org/alist) 服务 |

## 应用导航

底部导航栏包含四个主要页面：

| Tab | 名称 | 功能 |
|---|---|---|
| 📁 | 文件 | 文件浏览、目录导航、文件操作 |
| ⏱ | 最近 | 最近浏览的文件记录，快速回访 |
| ⭐ | 收藏 | 收藏的文件和目录，支持随机播放/查看 |
| ⚙️ | 设置 | 账户管理、播放器配置、界面个性化等 |

## 新增功能

### TikTok 短视频播放器（v1.3.2 新增）
- **双入口集成**：
  - 目录级入口：文件夹「更多」菜单 → "TikTok模式播放此文件夹视频"，异步获取目录下所有视频
  - 单文件入口：视频文件「更多」菜单 → "TikTok模式播放"，自动加载同目录所有视频并定位到当前文件
- **全屏 PageView.builder 上下滑动容器**
- **视频控制器智能管理**：前后 2 个视频预加载，超出 3 个范围自动 dispose 释放内存
- **双击点赞动效**
- **单击暂停/恢复**
- **进度条拖拽**
- **右侧悬浮工具栏**：
  - 收藏/取消收藏（复用 FavoriteDao 数据库，支持双击点赞联动）
  - 不喜欢/取消不喜欢（复用 DislikedVideoDao）
  - 循环模式切换（单视频循环 ↔ 自动播放下一个）
  - 横竖屏强制切换（`SystemChrome.setPreferredOrientations`）
  - 截图保存到相册（`/Pictures/AlistClient/`）
  - 视频信息查看（黑色 BottomSheet 弹窗显示元数据）
- **随机排序联动**：文件列表开启随机排序时，TikTok 播放列表同步随机
- **控件透明度可调**：设置页 → TikTok控件透明度（0%~100%），所有 UI 控件统一透明度
- **防抖 DB 写入**：收藏/不喜欢状态乐观更新 UI，切换视频或退出播放器时批量写入数据库
- **生命周期安全**：退出时恢复竖屏、重置 SystemUI、关闭 Wakelock、释放所有控制器

### 安全锁（v1.3 新增）
- 支持手势锁和密码锁两种方式
- 自动锁定超时设置（0 = 不自动锁）
- 安全锁验证页面

### 文件列表
- 目录过滤：不过滤 / 仅视频 / 仅图片
- 网格视图文件夹封面（优先视频 thumb，其次图片）
- 视频文件显示观看进度条
- 本地视频缩略图生成（基于视频帧截图）
- 图片/视频按日期分组显示
- 多选模式：批量下载、删除、移动
- 文件夹详情支持计算大小
- 排序新增随机模式、按文件大小排序
- 随机排序按类型分组（设置中可开启）
- 一键按文件类型分类
- 提取并整理：递归提取子文件夹文件并按类型归类
- 清理空文件夹
- 随机播放视频：当前目录随机选择视频播放
- 随机播放N个视频：可配置数量（默认10个）
- 递归随机播放：使用随机路径探测算法在子目录中查找视频并播放

  随机路径探测算法是一种以空间换时间的优化策略，通过牺牲"找到所有视频"的完整性，换取"快速找到一个视频"的效率。配合 LRU 路径惩罚机制（80% 概率跳过最近访问过的目录），避免重复探索同一目录。

- 智能预加载缓存：局域网环境下自动预加载子目录（可在设置中关闭/仅WiFi）
- **路径导航增强**：
  - 点击 AppBar 路径显示完整导航菜单
  - 支持直接跳转到根目录
  - 保留页面栈，避免重复页面创建
  - 优化返回逻辑，确保返回操作正确导航到预期页面
- 扩展名过滤：可配置过滤的文件扩展名（默认 nfo）
- 浮动菜单按钮（FAB）可开关
- 文件列表浮动菜单改为底部弹窗卡片式设计
- 文件上传：支持从本地选择文件/照片上传到 Alist 服务器
- 文件复制/移动：支持跨目录复制和移动文件
- 文件重命名：支持在线重命名文件和文件夹
- 新建文件夹：支持在当前目录创建新文件夹
- 目录密码记忆：输入过的目录密码自动保存，下次访问无需重复输入
- 目录收藏：收藏当前目录，快速访问常用路径

### IPTV 直播
- 支持 M3U/M3U8/TXT 播放列表，可从 Alist 文件 URL 或直接 URL 导入
- 按 group-title 分组显示频道，保持原始分类顺序，左侧分组导航 + 右侧频道列表
- 频道 Logo 显示
- 使用 media_kit 播放 HLS/m3u8 直播流，支持 rtmp/rtsp/mms 等协议
- 自动检测 HLS 流，直接跳转播放器无需解析频道列表
- 大文件（>500KB）使用 Isolate 异步解析，不阻塞 UI
- 播放器支持上一个/下一个频道切换，控制栏 4 秒无操作自动隐藏

### STRM 流媒体播放
- **.strm 文件解析**：自动读取 .strm 文件内容，提取视频流 URL
- **专用播放器**：基于 video_player 的全功能播放器
  - 手势控制：左右滑动 seek、左侧上下滑动调节亮度、右侧上下滑动调节音量
  - 播放列表侧边栏（支持按文件名/大小排序）
  - 横竖屏自由切换
  - 单视频循环模式
  - 截图保存到相册
  - 视频信息查看
  - 控件透明度可调
  - 亮度记忆：下次播放自动恢复上次亮度
  - 横屏自动隐藏控件（2秒无操作）
- **.strm 主机替换**：将 .strm 文件中的内网地址替换为 FRP/代理后的公网地址，实现非局域网环境下的视频流播放

### 视频播放器
- 播放列表侧边栏（顶部栏按钮触发，支持全屏模式）
- 视频截图保存到相册
- 播放中删除当前视频
- 视频信息查看：文件名、大小、时长、分辨率、目录路径
- 冷门格式（rmvb/avi/wmv 等）自动切换 ijkplayer 内核
- 新增更多视频格式支持（webm/divx/m2ts 等）
- 全屏模式下所有按钮完全适配
- 播放进度自动记录，下次打开从上次位置继续
- MediaKit（libmpv）播放器选项（设置中开启）
- 自动画中画（按 Home 键自动进入 PiP）
- **MediaKit 播放器增强**：
  - 视频填充模式切换（包含/覆盖/填充）
  - 播放失败自动重试（最多 3 次）
  - 手势控制：左右滑动 seek、左侧上下滑动调节亮度、右侧上下滑动调节音量
  - 亮度记忆：下次播放自动恢复上次亮度
  - 收藏/不喜欢联动

### 图片画廊
- 图片旋转
- 幻灯片自动播放（间隔时间可配置：1~30秒）
- 图片信息弹窗（分辨率、大小、EXIF 信息等）
  - 相机型号、拍摄时间
  - ISO、光圈、快门速度、焦距
  - GPS 位置信息
- 智能预加载：前后各预加载 5 张图片
- 内存与磁盘缓存优化
- HEIC/HEIF 格式支持（Android 自动转换为 JPEG 显示）
- HEIC 文件使用 Android 原生查看器
- HEIC 预热转换：文件列表跳转前提前触发 HEIC 转换缓存

### 文件搜索
- 搜索结果支持多选批量下载
- 搜索历史记录
- 快速重复搜索
- 一键清空历史
- 搜索路径过滤规则

### 文档阅读器
- **TXT 阅读器**：纯文本文件在线查看，支持编码切换（UTF-8/GBK/GB2312 等），支持复制链接
- **Markdown 渲染**：基于 InAppWebView 的 Markdown 渲染，支持代码高亮和样式
- **PDF 阅读器**：基于 flutter_pdfview 的 PDF 在线查看，支持夜间模式和链接跳转
- **Office 文件阅读**：支持 Word/Excel/PPT 等 Office 文档在线预览
- **内置网页浏览器**：InAppWebView 内置浏览器，支持混合内容加载

### 最近访问
- 自动记录浏览过的文件
- 快速回访最近查看的文件
- 支持滑动删除记录

### 下载管理
- 并发下载任务管理（默认最多 5 个同时下载）
- 下载进度实时显示
- 支持暂停/恢复/取消下载
- 下载记录持久化存储
- 下载完成后可直接打开文件

### 多服务器/多账户管理
- 支持添加多个 Alist 服务器
- 快速切换不同服务器和账户
- 支持编辑和删除已保存的服务器配置
- 游客模式登录支持

### 外挂字幕
- 本地字幕库：指定本地字幕目录，自动匹配视频文件
- 字幕下载直接存入字幕目录
- 字幕样式可调：字体大小、背景不透明度、描边宽度
- 全局字幕开关

### 缓存管理
- 视频缓存统计与清理
- 一键清除全部缓存

### 收藏夹
- 随机打开收藏的图片
- 随机播放收藏的视频

### 不喜欢视频列表
- 查看所有标记为"不喜欢"的视频
- 支持取消不喜欢

### 设置
- 智能预加载开关 + 仅WiFi预加载
- 播放器选择：ExoPlayer / MediaKit（libmpv）/ 外部播放器
- 音频播放器风格切换（经典黑胶 / 新风格）
- 主题颜色选择（12种预设颜色）
- 显示浮动按钮开关
- 随机排序按类型分组开关
- 扩展名过滤配置
- 随机播放数量配置
- 幻灯片间隔时间配置
- TikTok 控件透明度配置
- 安全锁设置（手势/密码）
- 搜索过滤规则设置
- 流媒体地址直接播放
- .strm 主机替换配置（内网→公网地址映射）
- 外挂字幕开关与配置
- 设置页分组重构：账户与存储、网络与预加载、播放器配置、界面与个性化、过滤器与高级、关于

### UI 优化
- 圆角卡片设计，增强视觉层次
- 优化图标透明度和配色
- 改进颜色选择器交互体验
- 音乐播放器支持获取音频封面文件
- 音频新风格播放器：波形进度条（随机生成 150 个采样点，支持拖拽 seek）

## UI 截图

### 项目界面预览

| 界面预览 1 | 界面预览 2 | 界面预览 3 |
| :---: | :---: | :---: |
| <img src="https://img.erpweb.eu.org/imgs/2026/04/2ff3cae272e1915f.jpg" width="250"> | <img src="https://img.erpweb.eu.org/imgs/2026/04/aa7518e5d18fbd96.jpg" width="250"> | <img src="https://img.erpweb.eu.org/imgs/2026/04/ef361608e25743f7.jpg" width="250"> |
| <img src="https://img.erpweb.eu.org/imgs/2026/04/7f71f3cf43822283.jpg" width="250"> | <img src="https://img.erpweb.eu.org/imgs/2026/04/91ca257bb62f2d09.jpg" width="250"> | <img src="https://img.erpweb.eu.org/imgs/2026/04/c96448889173df98.jpg" width="250"> |
| <img src="https://img.erpweb.eu.org/imgs/2026/04/64442e665e6bca3b.jpg" width="250"> | | |

## 技术栈

| 类别 | 技术 |
|---|---|
| 框架 | Flutter 3.13.8 (Dart) |
| 状态管理 | GetX |
| 数据库 | Floor ORM (SQLite) |
| 网络 | Dio |
| 视频播放 | video_player / media_kit (libmpv) / flutter_aliplayer |
| 图片加载 | extended_image |
| PDF | flutter_pdfview |
| WebView | flutter_inappwebview |
| 崩溃上报 | Bugly (仅 Release) |
| 本地化 | GetX Translations (中文/英文) |

## 项目结构

```
lib/
├── main.dart              # 应用入口
├── router.dart            # 路由配置
├── database/              # Floor ORM 数据库层
│   ├── dao/               # 数据访问对象
│   └── table/             # 数据表定义
├── entity/                # API 响应实体
├── generated/             # 生成代码（颜色方案、图片引用等）
├── l10n/                  # 国际化（中文/英文）
├── net/                   # HTTP 网络层（Dio 封装）
├── screen/                # 页面/屏幕（30+ 页面）
│   ├── file_list/         # 文件列表相关
│   ├── iptv/              # IPTV 直播
│   └── security/          # 安全锁
├── util/                  # 工具类和控制器
└── widget/                # 可复用组件
```

## 构建

### 环境要求

- **Flutter 3.13.8**（推荐使用 [FVM](https://fvm.app/) 管理）
- **Java 11** 及以上
- **Android SDK**：compileSdk 36, minSdk 26, NDK 26.1.10909125

### 使用 FVM（推荐）

```bash
fvm install 3.13.8
fvm use 3.13.8
fvm flutter pub get
fvm dart run build_runner build    # 重新生成 Floor 数据库代码（修改数据库表/DAO 后必须执行）
fvm flutter build apk --release --no-tree-shake-icons
```

### 使用全局 Flutter

```bash
flutter pub get
dart run build_runner build       # 重新生成 Floor 数据库代码（修改数据库表/DAO 后必须执行）
flutter build apk --release --no-tree-shake-icons
```

> ⚠️ **重要**：修改 `lib/database/` 下的 `@Entity` 表或 `@Dao` 类后，必须运行 `dart run build_runner build` 重新生成 `lib/database/alist_database.g.dart`，否则构建会失败。

### 构建产物

构建产物位于 `build/app/outputs/flutter-apk/` 目录，包含以下 APK：

| 文件 | 架构 | 说明 |
|---|---|---|
| `app-arm64-v8a-release.apk` | ARM 64位 | 推荐大多数手机 |
| `app-armeabi-v7a-release.apk` | ARM 32位 | 旧设备 |
| `app-x86_64-release.apk` | x86 64位 | 适用于模拟器 |
| `app-release.apk` | 通用 | 包含所有架构，体积最大 |

### 签名配置

在 `android/local.properties` 中配置签名信息：

```properties
keyAlias=your_key_alias
keyPassword=your_key_password
storeFile=/path/to/your/keystore.jks
storePassword=your_store_password
```

## 开发注意事项

- `flutter_aliplayer` 来自 Git 仓库（`GeekTR/flutter_aliplayer`，分支 `feature/5.5.6.0`），非 pub.dev
- `dependency_overrides` 中固定了 `win32`、`sqflite_common`、`sqflite`、`sqflite_common_ffi` 的版本，请勿随意移除
- `flutter_aliplayer` 和 `media_kit` 都包含原生 `.so` 文件，`packagingOptions` 使用 `pickFirst` 解决冲突
- Bugly 崩溃上报仅在 Release 模式下初始化
- 数据库当前版本为 8，包含 8 个实体表，Schema 变更时必须在 `alist_database.dart` 中添加 Migration

## 致谢

本项目基于 [AlistClient](https://github.com/BFWXKJGS/AlistClient) 开发，感谢原作者的开源贡献。

## 开源许可证

本项目采用 [GNU Affero General Public License v3.0](LICENSE) 开源许可证。

---

## 更新记录

### v1.3.3
- **STRM 流媒体播放**：.strm 文件解析与专用播放器
  - 手势控制（seek/亮度/音量）
  - 播放列表侧边栏（支持排序）
  - 横竖屏切换、循环模式、截图
  - 亮度记忆、控件透明度可调
  - .strm 主机替换（内网→公网地址映射）

### v1.3.2
- **TikTok 短视频播放器**：全新的上下滑动短视频播放模式
  - 双入口（目录级/单文件）集成
  - 双击点赞动效（心形在点击位置弹出）
  - 单击暂停/恢复播放
  - 进度条拖拽
  - 循环模式切换（单视频循环/自动下一个）
  - 横竖屏强制切换
  - 截图保存到相册
  - 视频信息查看
  - 右侧工具栏（收藏/踩/循环/横竖屏/截图/信息）
  - 控件透明度可调（设置页）
  - 防抖 DB 写入（切换视频或退出时批量持久化）
  - 视频控制器智能管理（预加载+自动释放防内存泄漏）

### v1.3.0
- **安全锁**：手势锁和密码锁两种方式，自动锁定超时
- **不喜欢视频列表**：标记/取消不喜欢，独立管理页面
- **搜索过滤规则**：按路径规则过滤搜索结果和文件列表
- 扩展名过滤配置（默认过滤 nfo 文件）
- 随机播放数量可配置
- 浮动菜单按钮可开关
- 随机排序按类型分组选项
- MediaKit（libmpv）播放器选项
- 自动画中画支持
- 音频播放器风格切换

### v1.2.0
- 文件列表浮动菜单改为底部弹窗卡片式设计
- 常用操作网格 + 播放与工具网格 + 排序方式chips
- 目录收藏功能（收藏当前目录）
- 安全锁快捷入口
- 按类型归类（一键将文件移动到对应子文件夹）
- 提取并整理（递归提取子文件夹文件并按类型归类）
- 清理空文件夹
- 文件组织操作进度页面（带进度条）

### v1.1.0
- IPTV 直播功能
- 视频播放进度自动记录
- 视频截图保存到相册
- 收藏夹随机播放
- HEIC/HEIF 格式支持
- 本地视频缩略图生成
- 网格视图文件夹封面