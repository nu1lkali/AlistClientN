/// IPTV 频道模型
class IptvChannel {
  final String name;
  final String url;
  final String? logoUrl;
  final String groupName;
  final String? epgId;

  const IptvChannel({
    required this.name,
    required this.url,
    this.logoUrl,
    this.groupName = 'Uncategorized',
    this.epgId,
  });
}
