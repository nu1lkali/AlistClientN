# Office 文件预览功能设置指南

## 功能概述
本项目集成了 AndroidDocViewer 库，支持在 Android 应用内直接预览 Office 文档，无需安装第三方应用。

## 支持的文件格式
- Word: .doc, .docx
- Excel: .xls, .xlsx
- PowerPoint: .ppt, .pptx
- PDF: .pdf
- 文本: .txt
- Markdown: .md

## 技术实现
- 使用腾讯 X5 内核进行文档渲染
- 本地渲染，无需联网
- 支持文档缩放、翻页等基本操作

## 最新优化 (v2)

### Excel 预览样式优化
Excel 文件预览时的 Sheet 标签样式已优化，更加简洁美观：
- 字体大小：26px → 14px
- 上边距：60px → 20px
- 下边距：30px → 12px
- 添加了浅灰色背景和绿色左边框
- 整体风格更加现代

详见：`EXCEL_STYLING_IMPROVEMENTS.md`

## 依赖配置

### Git Submodule 方式（推荐）
项目已配置 AndroidDocViewer 作为 Git Submodule：

```bash
# 克隆项目时自动初始化子模块
git clone --recurse-submodules <your-repo-url>

# 或者克隆后手动初始化
git clone <your-repo-url>
cd <your-repo>
git submodule update --init --recursive
```

### 手动下载方式
如果 Git Submodule 不可用：

```bash
cd android
git clone https://github.com/seapeak233/AndroidDocViewer.git
```

## 配置文件

### android/settings.gradle
```gradle
include ':app'
include ':docviewer'
project(':docviewer').projectDir = new File(rootProject.projectDir, 'AndroidDocViewer/docviewer')
```

### android/app/build.gradle
```gradle
dependencies {
    implementation project(':docviewer')
    // ... 其他依赖
}

android {
    defaultConfig {
        minSdkVersion 26  // AndroidDocViewer 要求
    }
}
```

## 使用方法

### Flutter 端调用
```dart
import 'package:alist/util/alist_plugin.dart';

// 打开文档预览
await AlistPlugin.openDocument(localFilePath, documentTitle);
```

### 原生端实现
```kotlin
import com.seapeak.docviewer.DocViewerActivity

// 打开文档
DocViewerActivity.startWithFile(context, filePath, title)
```

## 系统要求
- Android 8.0 (API 26) 及以上
- 存储权限（用于读取文档文件）

## 注意事项
1. 首次运行时 X5 内核需要初始化，可能需要几秒钟
2. APK 大小会增加约 50MB（包含 X5 内核）
3. 大型文档可能需要较长加载时间
4. 建议在真机上测试，模拟器可能存在兼容性问题

## 故障排除

### 文档无法打开
- 检查文件路径是否正确
- 确认文件格式是否支持
- 检查存储权限是否已授予

### X5 内核初始化失败
- 清除应用数据后重试
- 确保设备有足够的存储空间
- 检查网络连接（首次初始化可能需要下载组件）

### 编译错误
- 确保 minSdkVersion >= 26
- 检查 AndroidDocViewer 模块是否正确引入
- 运行 `flutter clean` 后重新编译

## 相关文件
- `lib/screen/office_reader_screen.dart` - Office 预览界面
- `android/app/src/main/kotlin/com/github/alist/util/DocViewerHelper.kt` - 原生辅助类
- `lib/util/alist_plugin.dart` - Flutter 插件接口
- `android/AndroidDocViewer/` - AndroidDocViewer 库源码

## 更新日志
- v2 (2026-04-06): 优化 Excel Sheet 标签样式，修复 GitHub 依赖配置
- v1 (初始版本): 集成 AndroidDocViewer 库，支持基本文档预览

## 参考资源
- [AndroidDocViewer GitHub](https://github.com/seapeak233/AndroidDocViewer)
- [腾讯 X5 内核文档](https://x5.tencent.com/docs/index.html)
