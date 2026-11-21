import 'package:intl/intl.dart';

class Money {
  final double amount;
  final String currency;

  const Money({
    required this.amount,
    required this.currency,
  });

  String format({bool includeSign = false}) {
    final format = NumberFormat.simpleCurrency(name: currency);
    final formatted = format.format(amount.abs());
    if (includeSign) {
      if (amount > 0) return '+$formatted';
      if (amount < 0) return '-$formatted';
    }
    return amount < 0 ? '-$formatted' : formatted;
  }

  @override
  String toString() => '$currency ${amount.toStringAsFixed(2)}';
}
