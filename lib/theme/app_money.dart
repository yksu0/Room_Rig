/// Display currency for catalog / upgrade prices (Philippine peso).
class AppMoney {
  AppMoney._();

  static const symbol = '₱';

  /// Formats a whole-peso amount, e.g. `₱1,250`.
  static String format(num amount) {
    final n = amount.round();
    final digits = n.abs().toString();
    final buf = StringBuffer(n < 0 ? '-$symbol' : symbol);
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return buf.toString();
  }
}
