/// 编辑距离算法工具类
/// 使用 Levenshtein Distance 算法计算两个字符串的相似度
class EditDistance {
  /// 计算两个字符串的编辑距离（Levenshtein Distance）
  /// 
  /// 编辑距离是指将一个字符串转换成另一个字符串所需的最少编辑操作次数。
  /// 允许的编辑操作包括：插入、删除、替换字符
  static int calculate(String s1, String s2) {
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    // 创建 DP 表
    List<List<int>> dp = List.generate(
      s1.length + 1,
      (i) => List.filled(s2.length + 1, 0),
    );

    // 初始化
    for (int i = 0; i <= s1.length; i++) {
      dp[i][0] = i;
    }
    for (int j = 0; j <= s2.length; j++) {
      dp[0][j] = j;
    }

    // 动态规划计算
    for (int i = 1; i <= s1.length; i++) {
      for (int j = 1; j <= s2.length; j++) {
        if (s1[i - 1] == s2[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1];
        } else {
          dp[i][j] = 1 +
              [
                dp[i - 1][j],     // 删除
                dp[i][j - 1],     // 插入
                dp[i - 1][j - 1], // 替换
              ].reduce((a, b) => a < b ? a : b);
        }
      }
    }

    return dp[s1.length][s2.length];
  }

  /// 判断两个字符串是否相似
  static bool isSimilar(String s1, String s2, {int threshold = 3}) {
    final distance = calculate(s1, s2);
    return distance > 0 && distance <= threshold;
  }
}
