# AlistClient

基于 [AList](https://github.com/alist-org/alist) 的 Flutter 移动客户端，支持 Android 平台。
fork至[BFWXKJGS/AlistClient](https://github.com/BFWXKJGS/AlistClient)
在原仓库代码做了一些功能改进

## 功能

**文件浏览**
- 列表 / 网格两种视图，可随时切换
- 文件过滤：不过滤 / 仅视频 / 仅图片
- 多种排序方式：文件名、文件类型、修改时间、文件大小、随机
- 网格视图下文件夹自动加载封面缩略图
- 下拉刷新、强制刷新
- 目录密码支持

**文件操作**
- 多选模式：批量下载、批量删除、批量移动
- 单文件：复制、移动、重命名、删除、收藏、复制链接、下载
- 新建文件夹
- 上传文件 / 上传照片

**媒体播放**
- 视频播放（阿里云播放器内核，支持手势控制亮度/音量/进度）


**其他**
- 多账号管理
- 收藏夹
- 最近浏览记录
- 文件搜索
- 下载管理器

## 构建

依赖 Flutter 3.13.8：

```bash
flutter pub get
flutter build apk --release
```

产物路径：`build/app/outputs/flutter-apk/app-release.apk`

## 依赖

- [AList](https://github.com/alist-org/alist) — 后端服务
- flutter_aliplayer — 视频播放
- floor — 本地数据库
- get — 状态管理 / 路由
- dio — 网络请求
- extended_image — 图片加载


# ALClient

![banner](https://raw.githubusercontent.com/BFWXKJGS/AlistClient/main/github/banner.jpg)

## AppStore
![banner](https://raw.githubusercontent.com/BFWXKJGS/AlistClient/main/github/appstore.png)

## Android（蓝奏云下载）
https://wwxv.lanzoul.com/b002uv0t2b
密码：alist

## Android
![banner](https://raw.githubusercontent.com/BFWXKJGS/AlistClient/main/github/android_github.png)

ALClient is a mobile application developed using Flutter based on [the AList project](https://github.com/alist-org/alist), supporting both Android and IOS platforms. It provides various functions, including online browsing of files, online viewing of videos, audios, and browsing of documents in the AList project. It also supports file uploading (to be developed) and file management (to be developed). Users can easily access and watch various types of media files in the AList project through ALClient.
