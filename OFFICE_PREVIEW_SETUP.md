# Office 文件预览功能集成说明

## 当前状态

已经完成了 Office 文件预览功能的代码框架，但 AndroidDocViewer 库暂时无法通过 JitPack 下载。

## 已完成的工作

1. ✅ 创建了 `office_reader_screen.dart` - Office 文件预览界面
2. ✅ 创建了 `DocViewerHelper.kt` - 原生文档预览辅助类
3. ✅ 修改了 `AlistPlugin.kt` - 添加了 `openDocument` 方法
4. ✅ 修改了 `alist_plugin.dart` - 添加了 Flutter 端调用方法
5. ✅ 修改了文件列表和搜索界面 - 支持 Office 文件预览

## 需要手动完成的步骤

### 方案一：使用 JitPack（推荐，但需要等待）

在 `android/app/build.gradle` 的 dependencies 中添加：

```gradle
implementation 'com.github.seapeak233:AndroidDocViewer:master-SNAPSHOT'
```

或者等待作者发布正式版本后使用：
```gradle
implementation 'com.github.seapeak233:AndroidDocViewer:1.0.0'
```

### 方案二：使用本地 AAR 文件

1. 从 GitHub 下载 AndroidDocViewer 项目：
   ```bash
   git clone https://github.com/seapeak233/AndroidDocViewer.git
   ```

2. 在 Android Studio 中打开该项目并构建 AAR：
   ```bash
   ./gradlew assembleRelease
   ```

3. 将生成的 AAR 文件复制到你的项目：
   ```
   android/app/libs/AndroidDocViewer.aar
   ```

4. 在 `android/app/build.gradle` 中添加：
   ```gradle
   dependencies {
       implementation files('libs/AndroidDocViewer.aar')
       // 还需要添加 AndroidDocViewer 的依赖
       implementation 'androidx.webkit:webkit:1.8.0'
   }
   ```

### 方案三：使用其他 Office 预览库

如果 AndroidDocViewer 不可用，可以考虑：

1. **TBS X5 内核**（腾讯浏览服务）
   - 优点：功能强大，支持多种格式
   - 缺点：需要收费，体积较大

2. **flutter_power_file_view**
   - 优点：Flutter 插件，集成简单
   - 缺点：依赖 dio 4.x（当前项目使用 dio 5.x）

3. **直接使用 WebView + Office Online**
   - 优点：无需本地渲染
   - 缺点：需要网络，隐私问题

## 使用方式

一旦 AndroidDocViewer 库集成成功，用户点击 Office 文件（Word/Excel/PPT）时：

1. 自动下载文件到本地（如果未下载）
2. 显示下载进度
3. 下载完成后显示"预览文档"按钮
4. 点击按钮使用 AndroidDocViewer 在应用内预览文档

## 功能特性

- ✅ 支持 Word (.doc, .docx)
- ✅ 支持 Excel (.xls, .xlsx)
- ✅ 支持 PowerPoint (.ppt, .pptx)
- ✅ 支持 PDF
- ✅ 支持 TXT
- ✅ 支持 Markdown
- ✅ 自动文件类型识别
- ✅ 文件缓存（下载一次，多次预览）
- ✅ 错误处理和重试机制

## 测试

集成 AndroidDocViewer 后，可以通过以下方式测试：

1. 在文件列表中点击任意 Office 文件
2. 等待文件下载完成
3. 点击"预览文档"按钮
4. 应该能看到文档内容在应用内显示

## 故障排除

如果遇到问题：

1. 检查 AndroidDocViewer 是否正确集成
2. 查看 Logcat 中的错误信息
3. 确认文件已成功下载到本地
4. 检查文件路径是否正确

## 参考资料

- [AndroidDocViewer GitHub](https://github.com/seapeak233/AndroidDocViewer)
- [JitPack 使用说明](https://jitpack.io/)
