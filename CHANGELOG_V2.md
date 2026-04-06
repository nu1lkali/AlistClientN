# 更新日志 v2

## 发布日期
2026-04-06

## 主要更新

### 1. Excel 预览样式优化 ✨
- 优化了 Excel 文件预览时的 Sheet 标签样式
- 字体大小从 26px 减小到 14px，更加协调
- 上下边距大幅减小（60px/30px → 20px/12px），减少空白
- 添加了浅灰色背景和绿色左边框，视觉层次更清晰
- 整体风格更加现代简洁

**修改文件：**
- `android/AndroidDocViewer/docviewer/src/main/assets/excel/viewer.html`

### 2. GitHub 依赖配置修复 🔧
- 将 AndroidDocViewer 依赖从绝对路径改为相对路径
- 添加了 `.gitmodules` 文件配置 Git Submodule
- 项目现在可以直接上传到 GitHub，其他开发者可以正常克隆和编译

**修改文件：**
- `android/settings.gradle` - 使用相对路径 `android/AndroidDocViewer/docviewer`
- `.gitmodules` - 配置 Git Submodule
- `SETUP_GUIDE.md` - 更新构建指南

**原配置：**
```gradle
project(':docviewer').projectDir = new File('C:\\AndroidDocViewer-main\\docviewer')
```

**新配置：**
```gradle
project(':docviewer').projectDir = new File(rootProject.projectDir, 'AndroidDocViewer/docviewer')
```

## 构建信息
- APK 大小：73.3 MB
- 输出路径：`E:\alist-client-with-office-preview-v2.apk`
- 构建时间：142.5 秒
- 最低 Android 版本：8.0 (API 26)

## 功能特性
- ✅ TXT 文件预览（智能编码检测：UTF-8、GBK、GB2312、Latin1）
- ✅ Office 文件预览（Word、Excel、PPT）
- ✅ PDF 预览
- ✅ 图片、视频、音频播放
- ✅ 文件搜索和管理
- ✅ 优化的 Excel Sheet 标签样式

## 技术细节

### Excel 样式改进
```css
/* 新样式 */
.sheetName {
  font-size: 14px;
  font-weight: 500;
  margin-top: 20px;
  margin-bottom: 12px;
  padding: 8px 12px;
  background-color: #f5f5f5;
  border-left: 3px solid #4CAF50;
  color: #333;
}
```

### Git Submodule 使用
克隆项目时需要初始化子模块：
```bash
git clone <your-repo-url>
cd <your-repo>
git submodule update --init --recursive
```

## 已知问题
- 首次运行时 X5 内核可能需要初始化
- 部分 Android 设备可能需要手动授予存储权限

## 下一步计划
- [ ] 添加更多文档格式支持
- [ ] 优化文档加载速度
- [ ] 添加文档搜索功能
- [ ] 支持文档注释和标记

## 相关文档
- `SETUP_GUIDE.md` - 项目构建指南
- `EXCEL_STYLING_IMPROVEMENTS.md` - Excel 样式优化详情
- `OFFICE_PREVIEW_SETUP.md` - Office 预览功能设置
