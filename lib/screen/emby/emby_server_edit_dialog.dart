import 'package:alist/entity/emby_config.dart';
import 'package:alist/net/emby_api.dart';
import 'package:alist/screen/emby/emby_form_sheet.dart';
import 'package:alist/util/emby_config_manager.dart';
import 'package:flutter/material.dart';

/// 服务器新增/编辑表单（底部弹窗）。
///
/// 字段：备注名、协议（http/https 分段选择）、baseUrl（地址与端口）、
/// apiKey（支持密码掩码切换）。内置“测试连接”，使用表单当前值
/// 实时向 Emby 发起 GET /Users 并就地反馈结果。
///
/// 通过 [buildEmbyFormSheet] 承载：键盘弹出时整体上移而非被压缩变形。
/// 保存成功后通过 [Navigator.pop] 返回构造好的 [EmbyServerConfig]。
class EmbyServerEditDialog extends StatefulWidget {
  /// 为 null 表示新增，否则为编辑模式
  final EmbyServerConfig? existing;

  const EmbyServerEditDialog({super.key, this.existing});

  @override
  State<EmbyServerEditDialog> createState() => _EmbyServerEditDialogState();
}

class _EmbyServerEditDialogState extends State<EmbyServerEditDialog> {
  late final TextEditingController _remarkCtrl;
  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _apiKeyCtrl;
  late String _protocol;
  late bool _obscureKey;

  bool _testing = false;
  String? _testOkMessage;
  String? _testErrMessage;
  String? _fieldError;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _remarkCtrl = TextEditingController(text: e?.remark ?? '');
    _baseUrlCtrl = TextEditingController(text: e?.baseUrl ?? '');
    _apiKeyCtrl = TextEditingController(text: e?.apiKey ?? '');
    _protocol = e?.protocol ?? 'http';
    _obscureKey = true;
  }

  @override
  void dispose() {
    _remarkCtrl.dispose();
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  EmbyServerConfig get _draft => EmbyServerConfig(
        id: widget.existing?.id ?? EmbyConfigManager.newId(),
        remark: _remarkCtrl.text.trim(),
        protocol: _protocol,
        baseUrl: EmbyConfigManager.normalizeBaseUrl(_baseUrlCtrl.text),
        apiKey: _apiKeyCtrl.text.trim(),
        userId: widget.existing?.userId,
      );

  bool get _fieldsReady =>
      EmbyConfigManager.normalizeBaseUrl(_baseUrlCtrl.text).isNotEmpty &&
      _apiKeyCtrl.text.trim().isNotEmpty;

  Future<void> _testConnection() async {
    if (!_fieldsReady) {
      setState(() {
        _fieldError = '请先填写地址与 API Key 再测试';
        _testOkMessage = null;
        _testErrMessage = null;
      });
      return;
    }
    setState(() {
      _testing = true;
      _fieldError = null;
      _testOkMessage = null;
      _testErrMessage = null;
    });
    try {
      final msg = await EmbyApi.testConnection(_draft);
      if (!mounted) return;
      setState(() => _testOkMessage = msg);
    } on EmbyApiException catch (e) {
      if (!mounted) return;
      setState(() => _testErrMessage = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _testErrMessage = '测试连接失败：$e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _submit() {
    final draft = _draft;
    if (draft.baseUrl.isEmpty || draft.apiKey.isEmpty) {
      setState(() => _fieldError = '请填写完整的服务器地址与 API Key');
      return;
    }
    Navigator.of(context).pop(draft);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isNew = widget.existing == null;

    return buildEmbyFormSheet(
      context,
      icon: isNew ? Icons.dns_rounded : Icons.edit_rounded,
      title: isNew ? '新增 Emby 服务器' : '编辑 Emby 服务器',
      children: [
        TextField(
          controller: _remarkCtrl,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: '备注名（可选）',
            hintText: '如：家里 NAS、客厅影音',
            prefixIcon: const Icon(Icons.label_outline_rounded, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outline.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias, // 完美裁剪圆角，解决缺角问题
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.surfaceVariant.withOpacity(0.5),
                ),
                child: Row(
                  children: [
                    Text('连接协议',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                    const Spacer(),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'http', label: Text('HTTP')),
                        ButtonSegment(value: 'https', label: Text('HTTPS')),
                      ],
                      selected: {_protocol},
                      onSelectionChanged: (s) =>
                          setState(() => _protocol = s.first),
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        textStyle: MaterialStateProperty.all(
                            const TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1),
              TextField(
                controller: _baseUrlCtrl,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: '服务器地址与端口',
                  hintText: '192.168.2.124:8097',
                  prefixIcon: const Icon(Icons.link_rounded, size: 20),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.all(12),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text('地址不要带 http:// 前缀，填「主机:端口」即可',
            style: TextStyle(fontSize: 11, color: scheme.outline)),
        const SizedBox(height: 14),
        TextField(
          controller: _apiKeyCtrl,
          obscureText: _obscureKey,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'API Key（密钥）',
            hintText: 'Emby 控制台 API Key',
            prefixIcon: const Icon(Icons.key_rounded, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
            suffixIcon: IconButton(
              icon: Icon(
                  _obscureKey
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20),
              onPressed: () => setState(() => _obscureKey = !_obscureKey),
            ),
          ),
        ),
        if (widget.existing?.userId != null &&
            (widget.existing?.userId ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('已缓存用户 ID，修改地址或密钥后将自动重新获取',
              style: TextStyle(fontSize: 11, color: scheme.outline)),
        ],
        if (_fieldError != null) ...[
          const SizedBox(height: 10),
          Text(_fieldError!,
              style: TextStyle(fontSize: 12, color: scheme.error)),
        ],
      ],
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_testOkMessage != null) ...[
            _resultRow(Icons.check_circle_rounded, Colors.green.shade600,
                _testOkMessage!),
            const SizedBox(height: 8),
          ],
          if (_testErrMessage != null) ...[
            _resultRow(Icons.error_rounded, scheme.error, _testErrMessage!),
            const SizedBox(height: 8),
          ],
          _buildTestButton(scheme),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTestButton(ColorScheme scheme) {
    return OutlinedButton.icon(
      onPressed: _testing ? null : _testConnection,
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.primary,
        side: BorderSide(color: scheme.primary.withOpacity(0.5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      icon: _testing
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.wifi_tethering_rounded, size: 18),
      label: Text(_testing ? '测试中...' : '测试连接'),
    );
  }

  Widget _resultRow(IconData icon, Color color, String message) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(message,
              style: TextStyle(fontSize: 12, color: color, height: 1.4)),
        ),
      ],
    );
  }
}

/// 便捷入口：以底部表单弹出服务器编辑，保存成功后执行 [onSaved]。
Future<void> showEmbyServerEditDialog(
  BuildContext context, {
  EmbyServerConfig? existing,
  required void Function(EmbyServerConfig draft) onSaved,
}) async {
  final draft = await showModalBottomSheet<EmbyServerConfig>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => EmbyServerEditDialog(existing: existing),
  );
  if (draft != null) onSaved(draft);
}