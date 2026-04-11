import 'package:alist/entity/copy_move_req.dart';
import 'package:alist/entity/file_rename_req.dart';
import 'package:alist/entity/file_list_resp_entity.dart';
import 'package:alist/net/dio_utils.dart';
import 'package:alist/util/file_organize_task.dart';
import 'package:alist/util/log_utils.dart';

/// 文件整理任务执行器
class FileOrganizeExecutor {
  final String? password;
  
  FileOrganizeExecutor({this.password});
  
  /// 执行单个文件整理任务
  Future<void> executeTask(FileOrganizeTask task) async {
    task.status = FileOrganizeTaskStatus.processing;
    
    try {
      // 1. 检查目标目录是否有同名文件
      final targetFileName = await _handleNameConflict(task);
      
      // 2. 执行移动
      final moveSuccess = await _moveFile(
        task.sourcePath,
        task.targetPath,
        targetFileName,
      );
      
      if (moveSuccess) {
        task.status = FileOrganizeTaskStatus.success;
        Log.d('文件整理成功: ${task.fileName} -> ${task.targetPath}/$targetFileName');
      } else {
        throw Exception('移动失败');
      }
    } catch (e) {
      task.status = FileOrganizeTaskStatus.failed;
      task.errorType = _parseErrorType(e.toString());
      task.errorMessage = e.toString();
      Log.e('文件整理失败: ${task.fileName}, error: $e');
    }
  }
  
  /// 处理文件名冲突
  Future<String> _handleNameConflict(FileOrganizeTask task) async {
    // 获取目标目录现有文件
    Set<String> existingFiles = {};
    await DioUtils.instance.requestNetwork<FileListRespEntity>(
      Method.post,
      'fs/list',
      params: {
        'path': task.targetPath,
        'password': password ?? '',
        'page': 1,
        'per_page': 0,
        'refresh': false,
      },
      onSuccess: (data) {
        existingFiles = (data?.content ?? []).map((f) => f.name).toSet();
      },
      onError: (_, __) {},
    );
    
    // 如果没有冲突，直接返回原文件名
    if (!existingFiles.contains(task.fileName)) {
      return task.fileName;
    }
    
    // 生成唯一文件名
    final uniqueName = _generateUniqueFileName(task.fileName, existingFiles);
    
    // 重命名文件
    final renameReq = FileRenameReq();
    renameReq.path = '${task.sourcePath}/${task.fileName}';
    renameReq.name = uniqueName;
    
    bool renamed = false;
    await DioUtils.instance.requestNetwork<String?>(
      Method.post,
      'fs/rename',
      params: renameReq.toJson(),
      onSuccess: (_) { renamed = true; },
      onError: (code, msg) {
        Log.e('重命名失败: ${task.fileName} -> $uniqueName, code=$code msg=$msg');
      },
    );
    
    if (!renamed) {
      throw Exception('重命名失败: ${task.fileName} -> $uniqueName');
    }
    
    return uniqueName;
  }
  
  /// 移动文件
  Future<bool> _moveFile(String srcDir, String dstDir, String fileName) async {
    final req = CopyMoveReq();
    req.srcDir = srcDir;
    req.dstDir = dstDir;
    req.names = [fileName];
    
    bool success = false;
    await DioUtils.instance.requestNetwork<String?>(
      Method.post,
      'fs/move',
      params: req.toJson(),
      onSuccess: (_) { success = true; },
      onError: (code, msg) {
        Log.e('移动文件失败: $fileName, code=$code msg=$msg');
      },
    );
    
    return success;
  }
  
  /// 生成唯一文件名
  String _generateUniqueFileName(String originalName, Set<String> existingNames) {
    final lastDotIndex = originalName.lastIndexOf('.');
    String nameWithoutExt;
    String extension;
    
    if (lastDotIndex > 0 && lastDotIndex < originalName.length - 1) {
      nameWithoutExt = originalName.substring(0, lastDotIndex);
      extension = originalName.substring(lastDotIndex);
    } else {
      nameWithoutExt = originalName;
      extension = '';
    }
    
    int counter = 1;
    String newName;
    do {
      newName = '$nameWithoutExt($counter)$extension';
      counter++;
    } while (existingNames.contains(newName));
    
    return newName;
  }
  
  /// 解析错误类型
  FileOrganizeErrorType _parseErrorType(String error) {
    final lowerError = error.toLowerCase();
    
    if (lowerError.contains('occupied') || lowerError.contains('in use') || lowerError.contains('被占用')) {
      return FileOrganizeErrorType.fileOccupied;
    } else if (lowerError.contains('permission') || lowerError.contains('权限')) {
      return FileOrganizeErrorType.permissionDenied;
    } else if (lowerError.contains('network') || lowerError.contains('网络')) {
      return FileOrganizeErrorType.networkError;
    } else if (lowerError.contains('invalid') || lowerError.contains('非法')) {
      return FileOrganizeErrorType.invalidFileName;
    } else if (lowerError.contains('exists') || lowerError.contains('已存在')) {
      return FileOrganizeErrorType.targetExists;
    }
    
    return FileOrganizeErrorType.unknown;
  }
}
