import 'package:alist/entity/emby_config.dart';
import 'package:alist/util/emby_config_manager.dart';
import 'package:flutter/material.dart';

/// 弹出“每次随机数量”设置对话框（滑块 + 数字显示，1~100）。
Future<void> showEmbyLimitDialog(BuildContext context) async {
  final scheme = Theme.of(context).colorScheme;
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      var value = EmbyConfigManager.randomLimit;
      return StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('每次随机数量'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('随机播放时从媒体库抽取的视频个数',
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Text('$value 个',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary)),
              Slider(
                value: value.toDouble(),
                min: EmbyRandomSettings.minLimit.toDouble(),
                max: EmbyRandomSettings.maxLimit.toDouble(),
                divisions:
                    EmbyRandomSettings.maxLimit - EmbyRandomSettings.minLimit,
                label: '$value',
                onChanged: (v) =>
                    setDialogState(() => value = v.round()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${EmbyRandomSettings.minLimit}',
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                  Text('最多 ${EmbyRandomSettings.maxLimit}',
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child:
                  Text('取消', style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
            FilledButton(
              onPressed: () {
                EmbyConfigManager.setRandomLimit(value);
                Navigator.of(ctx).pop();
              },
              style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8))),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    },
  );
}

/// 弹出“Emby 随机播放使用说明”对话框。
void showEmbyHelpDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('使用说明'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Text(
            _helpContent,
            style: const TextStyle(fontSize: 13.5, height: 1.6),
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8))),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

const String _helpContent = '''
【功能简介】
从 Emby 服务器指定媒体库中随机抽取一批视频，自动进入“视界流”播放器，上下滑动即可沉浸式连续播放。

【一、配置 Emby 服务器】
进入「设置 → Emby 随机播放 → Emby 服务器管理」，点击右上角 + 新增：
· 备注名：便于区分，如「家里 NAS」（可选，建议填写）；
· 协议：http:// 或 https://，与你的 Emby 部署一致；
· 服务器地址与端口：如 192.168.2.124:8097（不要带 http:// 前缀）；
· API Key：Emby 控制台 → 设置 → 高级 → API 密钥 中生成/复制。
支持同时维护多个服务器，点击列表项即可切换“主服务器”（随机播放永远使用主服务器）。
列表项与编辑弹窗内均提供「测试连接」，会实时向服务器发起 GET /Users 并反馈结果，方便你确认地址与密钥无误。

【二、配置媒体库】
进入「Emby 随机播放 → 媒体库管理」，点击右上角 + 新增：
· 备注名：如「电影库」「短视频」；
· ParentId：该媒体库的 Id。
获取方式：用浏览器打开 Emby Web，点击左侧你想抽取的媒体库进入其页面，
浏览器地址栏形如：…/index.html#!/details?id=1115732&serverId=…
其中 id= 后面的一串数字（如 1115732）即为 ParentId。
支持维护多个媒体库并添加备注，点击列表项选择“当前要参与随机播放的目标媒体库”。

【三、每次随机数量】
在「Emby 随机播放」分组中点击「每次随机数量」，可设置 1~100 个（默认 10 个）。

【四、开始随机播放】
回到首页（文件列表页），点击右上角「随机播放」图标按钮：
· 应用会先读取当前主服务器与目标媒体库配置；
· 若尚未缓存用户，自动请求 GET /Users 取第一个用户（成功后自动缓存，无需重复获取）；
· 再按 SortBy=Random 随机抽取视频并拼接播放直链；
· 成功后自动进入“视界流”开始播放；失败会弹出友好提示。

【注意事项】
· 播放使用 Emby 静态直链（…/Videos/{id}/stream），需保证此应用与 Emby 服务器网络可达；
· https 若使用自签名证书可能导致播放失败，建议使用有效证书或改用 http。
''';
