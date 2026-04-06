/* parse workbook */
const params = new URLSearchParams(window.location.search);
const fileUrl = params.get("file");
var xhr = new XMLHttpRequest();

xhr.onload = function () {
  try {
    const workbook = XLSX.read(xhr.response);
    var sheetNames = workbook.SheetNames;
    var divHtml = "";
    
    sheetNames.forEach(function(sheetName, index) {
      var sheet = workbook.Sheets[sheetName];
      
      // 添加 Sheet 标签
      divHtml += '<p class="sheetName">' + sheetName + '</p>';
      
      // 添加表格容器
      divHtml += '<div class="table-container">';
      
      // 转换为 HTML 表格
      var tableHtml = XLSX.utils.sheet_to_html(sheet, {
        header: '',
        footer: ''
      });
      
      // 处理表格，添加表头标识
      if (tableHtml) {
        // 将第一行标记为表头
        tableHtml = tableHtml.replace(/<tr>/, '<thead><tr>');
        tableHtml = tableHtml.replace(/<\/tr>/, '</tr></thead><tbody>');
        tableHtml = tableHtml.replace(/<\/table>/, '</tbody></table>');
        
        // 为数字单元格添加属性
        tableHtml = tableHtml.replace(/<td>(-?\d+\.?\d*)<\/td>/g, '<td data-t="n"></td>');
      }
      
      divHtml += tableHtml;
      divHtml += '</div>';
    });

    const content = document.getElementById("excelPreview");
    content.innerHTML = divHtml;
    
    // 添加表格增强功能
    enhanceTables();
  } catch (error) {
    document.getElementById("excelPreview").innerHTML = 
      '<div style="padding: 20px; color: #d32f2f;">加载失败: ' + error.message + '</div>';
  }
};

xhr.onerror = function () {
  document.getElementById("excelPreview").innerHTML = 
    '<div style="padding: 20px; color: #d32f2f;">文件加载失败</div>';
};

xhr.open('GET', fileUrl, true);
xhr.responseType = "arraybuffer";
xhr.send(null);

// 表格增强功能
function enhanceTables() {
  const tables = document.querySelectorAll('table');
  
  tables.forEach(function(table) {
    // 如果没有 thead，将第一行转为 thead
    if (!table.querySelector('thead') && table.rows.length > 0) {
      const thead = document.createElement('thead');
      const firstRow = table.rows[0];
      table.insertBefore(thead, table.firstChild);
      thead.appendChild(firstRow);
    }
    
    // 为空单元格添加标记
    const cells = table.querySelectorAll('td');
    cells.forEach(function(cell) {
      if (cell.textContent.trim() === '') {
        cell.classList.add('empty-cell');
      }
      
      // 检测数字并右对齐
      const text = cell.textContent.trim();
      if (text && !isNaN(text) && text !== '') {
        cell.setAttribute('data-t', 'n');
      }
    });
  });
}
