import 'package:alist/screen/iptv/model/iptv_channel.dart';
import 'package:alist/screen/iptv/iptv_player_screen.dart';
import 'package:alist/screen/iptv/util/m3u_parser.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// IPTV 播放列表页面
/// 支持从 alist 文件 URL 或直接 URL 导入 M3U/M3U8/TXT 播放列表
/// 按 group-title 分组，保持原始分类顺序
class IptvScreen extends StatefulWidget {
  const IptvScreen({super.key});

  @override
  State<IptvScreen> createState() => _IptvScreenState();
}

class _IptvScreenState extends State<IptvScreen> {
  // 从路由参数获取
  late final String _title;
  late final String _url; // 播放列表文件的直链 URL

  List<IptvChannel> _allChannels = [];
  List<String> _groupOrder = [];
  String? _selectedGroup;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments as Map<String, dynamic>;
    _title = args['name'] ?? 'IPTV';
    _url = args['url'] ?? '';

    // 如果调用方已经准备好了频道列表（如文件列表页），直接跳播放器
    final prebuiltChannels = args['channels'];
    if (prebuiltChannels != null && prebuiltChannels is List && prebuiltChannels.isNotEmpty) {
      final channels = List<IptvChannel>.from(prebuiltChannels);
      final index = (args['index'] as int? ?? 0).clamp(0, channels.length - 1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Get.off(() => const IptvPlayerScreen(), arguments: {
          'channel': channels[index],
          'playlist': channels,
          'index': index,
        });
      });
      return;
    }

    _loadPlaylist();
  }

  Future<void> _loadPlaylist() async {
    if (_url.isEmpty) {
      setState(() {
        _error = '无效的播放列表地址';
        _loading = false;
      });
      return;
    }
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final result = await M3uParser.parseFromUrl(_url);
      if (!mounted) return;

      // HLS 流直接跳播放器
      if (result.isHlsStream) {
        final channel = IptvChannel(name: _title, url: _url);
        Get.off(() => const IptvPlayerScreen(), arguments: {
          'channel': channel,
          'playlist': [channel],
          'index': 0,
        });
        return;
      }

      // 解析结果为空，当作直播流直接播放
      if (result.channels.isEmpty) {
        final channel = IptvChannel(name: _title, url: _url);
        Get.off(() => const IptvPlayerScreen(), arguments: {
          'channel': channel,
          'playlist': [channel],
          'index': 0,
        });
        return;
      }

      setState(() {
        _allChannels = result.channels;
        _groupOrder = result.groupOrder;
        _selectedGroup = result.groupOrder.isNotEmpty ? result.groupOrder.first : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败: $e';
        _loading = false;
      });
    }
  }

  List<IptvChannel> get _filteredChannels {
    if (_selectedGroup == null) return _allChannels;
    return _allChannels.where((c) => c.groupName == _selectedGroup).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPlaylist,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadPlaylist, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_allChannels.isEmpty) {
      return const Center(child: Text('播放列表为空'));
    }

    return Row(
      children: [
        // 左侧分组列表
        SizedBox(
          width: 120,
          child: _buildGroupList(),
        ),
        const VerticalDivider(width: 1),
        // 右侧频道列表
        Expanded(child: _buildChannelList()),
      ],
    );
  }

  Widget _buildGroupList() {
    return ListView.builder(
      itemCount: _groupOrder.length,
      itemBuilder: (context, index) {
        final group = _groupOrder[index];
        final isSelected = group == _selectedGroup;
        return InkWell(
          onTap: () => setState(() => _selectedGroup = group),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            color: isSelected
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            child: Text(
              group,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : null,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChannelList() {
    final channels = _filteredChannels;
    return ListView.builder(
      itemCount: channels.length,
      itemBuilder: (context, index) {
        final channel = channels[index];
        return ListTile(
          leading: _buildChannelLogo(channel),
          title: Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            channel.groupName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          onTap: () => _playChannel(channel, channels, index),
        );
      },
    );
  }

  Widget _buildChannelLogo(IptvChannel channel) {
    if (channel.logoUrl != null && channel.logoUrl!.isNotEmpty) {
      return SizedBox(
        width: 40,
        height: 40,
        child: Image.network(
          channel.logoUrl!,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(Icons.tv),
        ),
      );
    }
    return const Icon(Icons.tv);
  }

  void _playChannel(IptvChannel channel, List<IptvChannel> playlist, int index) {
    Get.toNamed(
      '/iptvPlayer',
      arguments: {
        'channel': channel,
        'playlist': playlist,
        'index': index,
      },
    );
  }
}
