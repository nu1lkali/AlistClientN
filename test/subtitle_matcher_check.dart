// 纯 Dart 校验脚本（不依赖 flutter_test，命令行直接跑）：
//   dart --packages=.dart_tool/package_config.json test/subtitle_matcher_check.dart
import 'package:alist/util/subtitle/subtitle_matcher.dart';

int _pass = 0;
int _fail = 0;

void expectTrue(String desc, bool ok, String detail) {
  if (ok) {
    _pass++;
    print('  PASS  $desc  [$detail]');
  } else {
    _fail++;
    print('  FAIL  $desc  [$detail]');
  }
}

void expectScore(String video, String sub, bool shouldMatch) {
  final s = SubtitleMatcher.fuzzyMatchScore(video, sub);
  final matched = s >= kFuzzyAcceptScore;
  expectTrue(shouldMatch ? '应匹配  $video  <->  $sub' : '不应匹配 $video  <->  $sub',
      matched == shouldMatch, 'score=$s');
}

void main() {
  print('== 误命中回归 ==');
  expectScore('1.mp4', '13333.srt', false);
  expectScore('12.mp4', '1234.srt', false);
  expectScore('123.mp4', '1234.srt', false);
  expectScore('2.mp4', '2020.srt', false);
  expectScore('MIAA-003.mp4', 'MIAA-004.srt', false);
  expectScore('MIAA-003.mp4', 'MIAA-0034.srt', false);
  expectScore('Friends.S01E02.1080p.mp4', 'Friends.S01E03.srt', false);
  expectScore('让子弹飞.mp4', '疯狂的石头.srt', false);
  expectScore('电影A.mp4', '电影B.srt', false);

  print('== 正常匹配 ==');
  expectScore('复仇者联盟.mp4', '复仇者联盟.srt', true);
  expectScore('复仇者联盟.mp4', '复仇者联盟.zh-CN.srt', true);
  expectScore('复仇者联盟.2012.1080p.BluRay.x264.AAC.mp4', '复仇者联盟.srt', true);
  expectScore('复仇者联盟.mp4', '复仇者联盟.2012.srt', true);
  expectScore('www.98T.la@HEYZO-0806_iris2.mp4', 'HEYZO-0806.srt', true);
  expectScore('HEYZO.0806.mp4', 'HEYZO-0806.srt', true);
  expectScore('FC2-PPV-123456.mp4', 'FC2-123456.srt', true);
  expectScore('Friends.S01E02.1080p.WEB-DL.x264.mp4', 'Friends.S01E02.srt', true);
  expectScore('0123.mp4', '123.srt', true);
  expectScore('The.Matrix.1999.1080p.mp4', 'The.Matrix.1999.srt', true);
  expectScore('[Thz.la]neob-017中文字幕.mp4', 'neob-017.srt', true);

  print('== 模式与排序 ==');
  final pool = ['13333.srt', '13334.srt', '123456.srt'];
  final fuzzy = SubtitleMatcher.findMatchedSubtitles('1.mp4', pool, SubtitleMatchMode.fuzzy);
  expectTrue('1.mp4 模糊模式不应命中任何纯数字字幕', fuzzy.isEmpty, '$fuzzy');
  final dual = SubtitleMatcher.findMatchedSubtitles('1.mp4', pool, SubtitleMatchMode.dual);
  expectTrue('1.mp4 双模式不应命中任何纯数字字幕', dual.isEmpty, '$dual');

  final exact = SubtitleMatcher.findMatchedSubtitles('1.mp4', ['1.srt', '13333.srt'], SubtitleMatchMode.exact);
  expectTrue('1.mp4 精确模式只认 1.srt', exact.length == 1 && exact.first == '1.srt', '$exact');

  final rank = SubtitleMatcher.findMatchedSubtitles(
      'MIAA-003.mp4', ['MIAA-003.ass', 'MIAA-003.srt'], SubtitleMatchMode.fuzzy);
  expectTrue('同分时按格式优先级 .srt 优先', rank.first == 'MIAA-003.srt', '$rank');

  final mixed = SubtitleMatcher.findMatchedSubtitles(
      'HEYZO-0806.mp4', ['HEYZO-0807.srt', 'HEYZO-0806.ass', 'HEYZO-0806.srt'],
      SubtitleMatchMode.fuzzy);
  expectTrue('高分排在低分前', mixed.first == 'HEYZO-0806.srt' && !mixed.contains('HEYZO-0807.srt'), '$mixed');

  print('');
  print('通过 $_pass 项，失败 $_fail 项');
}
