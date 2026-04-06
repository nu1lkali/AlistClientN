# Excel 预览样式优化

## 修改内容

优化了 Excel 文件预览时的 Sheet 标签样式，使其更加简洁美观。

## 修改文件

`android/AndroidDocViewer/docviewer/src/main/assets/excel/viewer.html`

## 样式变更

### 原样式
```css
.sheetName {
  font-size: 26px;
  margin-top: 60px;
  margin-bottom: 30px;
}
```

### 新样式
```css
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

## 改进效果

- 字体大小从 26px 减小到 14px，更加协调
- 上下边距大幅减小（60px/30px → 20px/12px），减少空白
- 添加了浅灰色背景和绿色左边框，视觉层次更清晰
- 添加了内边距，提升可读性
- 整体风格更加现代简洁

## 备份

原始文件已备份为 `viewer.html.bak`
