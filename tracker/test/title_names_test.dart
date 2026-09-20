import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/core/constants.dart';

/// 季号识别只用于「聚合与去重」，不改写条目名字——
/// 从豆瓣导入的条目保留原始标题（如「仙逆 年番2」），靠这里认出它属于哪部剧、第几季。
void main() {
  group('baseNameOf', () {
    test('第N季写法', () {
      expect(TitleNames.baseNameOf('仙逆 第2季'), '仙逆');
    });

    test('中文数字写法', () {
      expect(TitleNames.baseNameOf('仙逆 第一季'), '仙逆');
      expect(TitleNames.baseNameOf('仙逆 第十一季'), '仙逆');
    });

    test('年番写法（豆瓣常见）', () {
      expect(TitleNames.baseNameOf('仙逆 年番2'), '仙逆');
      expect(TitleNames.baseNameOf('仙逆 年番3'), '仙逆');
    });

    test('英文写法', () {
      expect(TitleNames.baseNameOf('Perfect World Season 2'), 'Perfect World');
      expect(TitleNames.baseNameOf('Perfect World S2'), 'Perfect World');
    });

    test('无季号原样返回', () {
      expect(TitleNames.baseNameOf('漫长的季节'), '漫长的季节');
    });

    test('去掉尾部分隔符', () {
      expect(TitleNames.baseNameOf('仙逆 · 第一季'), '仙逆');
      expect(TitleNames.baseNameOf('仙逆 - 年番2'), '仙逆');
    });
  });

  group('seasonNoOf', () {
    test('各种写法都能取出季号', () {
      expect(TitleNames.seasonNoOf('仙逆 第2季'), 2);
      expect(TitleNames.seasonNoOf('仙逆 第二季'), 2);
      expect(TitleNames.seasonNoOf('仙逆 第十一季'), 11);
      expect(TitleNames.seasonNoOf('仙逆 年番3'), 3);
      expect(TitleNames.seasonNoOf('Perfect World Season 2'), 2);
    });

    test('识别不出季号视为第 1 季', () {
      expect(TitleNames.seasonNoOf('仙逆'), 1);
      expect(TitleNames.seasonNoOf('漫长的季节'), 1);
    });
  });
}
