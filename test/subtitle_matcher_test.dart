import 'package:alist/util/subtitle/subtitle_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  int score(String v, String s) => SubtitleMatcher.fuzzyMatchScore(v, s);

  group('不应匹配（误命中回归）', () {
    test('1.mp4 不应命中 13333.srt', () {
      expect(score('1.mp4', '13333.srt'), 0);
    });
    test('12.mp4 不应命中 1234.srt', () {
      expect(score('12.mp4', '1234.srt'), 0);
    });
    test('123.mp4 不应命中 1234.srt（纯数字只比数值）', () {
      expect(score('123.mp4', '1234.srt'), 0);
    });
    test('视频 2.mp4 不应命中 2020.srt', () {
      expect(score('2.mp4', '2020.srt'), 0);
    });
    test('番号不同不应匹配', () {
      expect(score('MIAA-003.mp4', 'MIAA-004.srt'), 0);
    });
    test('相邻集数不应互相匹配', () {
      expect(score('Friends.S01E02.1080p.mp4', 'Friends.S01E03.srt'), 0);
    });
    test('完全不同的中文名不应匹配', () {
      expect(score('让子弹飞.mp4', '疯狂的石头.srt'), 0);
    });
    test('字幕名比视频名多出另一部作品不应匹配', () {
      expect(score('MIAA-003.mp4', 'MIAA-0034.srt'), 0);
    });
  });

  group('应该匹配', () {
    test('同名（仅后缀不同）', () {
      expect(score('复仇者联盟.mp4', '复仇者联盟.srt'), 100);
    });
    test('字幕带语言标记', () {
      expect(score('复仇者联盟.mp4', '复仇者联盟.zh-CN.srt'), 100);
    });
    test('视频带分辨率/编码/来源噪音', () {
      expect(
        score('复仇者联盟.2012.1080p.BluRay.x264.AAC.mp4', '复仇者联盟.srt'),
        greaterThanOrEqualTo(70),
      );
    });
    test('字幕带额外年份标记', () {
      expect(score('复仇者联盟.mp4', '复仇者联盟.2012.srt'),
          greaterThanOrEqualTo(70));
    });
    test('番号完全一致（含广告前缀/分卷）', () {
      expect(score('www.98T.la@HEYZO-0806_iris2.mp4', 'HEYZO-0806.srt'),
          greaterThanOrEqualTo(70));
    });
    test('番号点号分隔写法', () {
      expect(score('HEYZO.0806.mp4', 'HEYZO-0806.srt'),
          greaterThanOrEqualTo(70));
    });
    test('FC2 番号', () {
      expect(score('FC2-PPV-123456.mp4', 'FC2-123456.srt'),
          greaterThanOrEqualTo(70));
    });
    test('剧集同季同集', () {
      expect(score('Friends.S01E02.1080p.WEB-DL.x264.mp4',
          'Friends.S01E02.srt'), 100);
    });
    test('纯数字名数值相等（前导零）', () {
      expect(score('0123.mp4', '123.srt'), greaterThanOrEqualTo(70));
    });
    test('英文片名带年份', () {
      expect(score('The.Matrix.1999.1080p.mp4', 'The.Matrix.1999.srt'),
          greaterThanOrEqualTo(70));
    });
  });

  group('排序与模式', () {
    test('100 分的 .ass 不应被 80 分的 .srt 压过', () {
      final pool = ['MIAA-003.srt', 'MIAA-003.ass'];
      final res = SubtitleMatcher.findMatchedSubtitles(
          'MIAA-003.mp4', pool, SubtitleMatchMode.fuzzy);
      // 分数相同时按格式优先级 .srt > .ass，因此两者分数必须都拿到满分
      expect(res.length, 2);
      expect(res.first, 'MIAA-003.srt');
    });

    test('精确模式只认同名', () {
      final pool = ['1.srt', '13333.srt'];
      final res = SubtitleMatcher.findMatchedSubtitles(
          '1.mp4', pool, SubtitleMatchMode.exact);
      expect(res, ['1.srt']);
    });

    test('双模式：精确命中优先', () {
      final pool = ['复仇者联盟.srt', '复仇者联盟2.srt'];
      final res = SubtitleMatcher.findMatchedSubtitles(
          '复仇者联盟.mp4', pool, SubtitleMatchMode.dual);
      expect(res.first, '复仇者联盟.srt');
    });

    test('1.mp4 在模糊/双模式下都不该命中 13333.srt', () {
      final pool = ['13333.srt', '13334.srt'];
      expect(
          SubtitleMatcher.findMatchedSubtitles(
              '1.mp4', pool, SubtitleMatchMode.fuzzy),
          isEmpty);
      expect(
          SubtitleMatcher.findMatchedSubtitles(
              '1.mp4', pool, SubtitleMatchMode.dual),
          isEmpty);
    });
  });
}
