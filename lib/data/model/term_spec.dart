/// 学期规格
class TermSpec {
  final int xnm; // 学年起始年，如2026表示2026-2027学年
  final int term; // 1=秋季学期, 2=春季学期

  const TermSpec(this.xnm, this.term);

  @override
  bool operator ==(Object other) =>
      other is TermSpec && other.xnm == xnm && other.term == term;

  @override
  int get hashCode => Object.hash(xnm, term);

  @override
  String toString() => '$xnm-${xnm + 1}学年第${term == 1 ? "一" : "二"}学期';
}
