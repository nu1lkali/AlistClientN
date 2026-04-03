# AlistClient N

基于 [AlistClient](https://github.com/BFWXKJGS/AlistClient) 的增强版 Android 客户端，感谢原作者 [BFWXKJGS](https://github.com/BFWXKJGS) 的开源贡献。

## 下载

**GitHub Releases**
https://github.com/nu1lkali/AlistClientN/releases

**蓝奏云**
https://wwanb.lanzoum.com/iycRi3m99qch
密码：9854

## 新增功能

**文件列表**
- 目录过滤：不过滤 / 仅视频 / 仅图片
- 网格视图文件夹封面（优先视频 thumb，其次图片）
- 视频文件显示观看进度条
- 图片/视频按日期分组显示
- 多选模式：批量下载、删除、移动
- 文件夹详情支持计算大小
- 排序新增随机模式

**图片画廊**
- 图片旋转
- 幻灯片自动播放
- 图片信息弹窗（分辨率、大小等）

**视频播放器**
- 播放列表侧边栏（顶部栏按钮触发）
- 视频截图保存到相册
- 播放中删除当前视频
- 冷门格式（rmvb/avi/wmv 等）自动切换 ijkplayer 内核
- 新增更多视频格式支持（webm/divx/m2ts 等）

**文件搜索**
- 搜索结果支持多选批量下载

**缓存管理**
- 视频缓存统计与清理
- 一键清除全部缓存

## 构建

需要 Flutter 3.13.8：

```bash
flutter pub get
flutter build apk --release
```

## 致谢

本项目基于 [AlistClient](https://github.com/BFWXKJGS/AlistClient) 开发，感谢原作者的开源工作。
