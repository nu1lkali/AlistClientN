# 项目构建指南

## 依赖说明

本项目使用了 AndroidDocViewer 库来实现 Office 文件预览功能。该库已作为 Git Submodule 集成到项目中。

## 构建步骤

### 方案 A：克隆项目（推荐）

1. 克隆项目并初始化子模块：
```bash
git clone <your-repo-url>
cd <your-repo>
git submodule update --init --recursive
```

2. 构建项目：
```bash
flutter pub get
flutter build apk --release
```

### 方案 B：手动下载依赖库

如果 Git Submodule 初始化失败，可以手动下载：

1. 下载 AndroidDocViewer：
```bash
cd android
git clone https://github.com/seapeak233/AndroidDocViewer.git
```

2. 构建项目：
```bash
cd ..
flutter pub get
flutter build apk --release
```

### 方案 C：使用 JitPack（如果可用）

如果 AndroidDocViewer 在 JitPack 上可用，可以直接在 `android/app/build.gradle` 中添加：

```gradle
dependencies {
    implementation 'com.github.seapeak233:AndroidDocViewer:master-SNAPSHOT'
}
```

然后修改 `android/settings.gradle` 移除本地模块配置。

## 系统要求

- Flutter SDK
- Android SDK (minSdkVersion 26+)
- JDK 17+

## 功能特性

- ✅ TXT 文件预览（智能编码检测）
- ✅ Office 文件预览（Word、Excel、PPT）
- ✅ PDF 预览
- ✅ 图片、视频、音频播放
- ✅ 文件搜索和管理

## 注意事项

- 首次运行时 X5 内核可能需要初始化
- Office 预览功能需要 Android 8.0 (API 26) 及以上
- APK 大小约 73MB（包含 X5 内核）
