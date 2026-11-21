import 'package:flutter/material.dart';

class PreviewUser {
  final String id;
  final String name;
  final String email;
  final String defaultCurrency;
  final bool isPro;

  const PreviewUser({
    required this.id,
    required this.name,
    required this.email,
    this.defaultCurrency = 'USD',
    this.isPro = false,
  });
}

class PreviewGroup {
  final String id;
  final String name;
  final String type;
  final String currency;
  final int memberCount;
  final double netBalance;
  final String inviteCode;

  const PreviewGroup({
    required this.id,
    required this.name,
    required this.type,
    required this.currency,
    required this.memberCount,
    required this.netBalance,
    required this.inviteCode,
  });
}

class PreviewFriend {
  final String id;
  final String name;
  final String email;
  final double netBalance;
  final String currency;

  const PreviewFriend({
    required this.id,
    required this.name,
    required this.email,
    required this.netBalance,
    required this.currency,
  });
}

class PreviewExpense {
  final String id;
  final String description;
  final String category;
  final String groupName;
  final String dateFormatted;
  final double totalAmount;
  final String currency;
  final String paidBy;
  final double yourNetShare;
  final List<String> participants;

  const PreviewExpense({
    required this.id,
    required this.description,
    required this.category,
    required this.groupName,
    required this.dateFormatted,
    required this.totalAmount,
    required this.currency,
    required this.paidBy,
    required this.yourNetShare,
    required this.participants,
  });
}

class PreviewActivity {
  final String id;
  final String title;
  final String subtitle;
  final String timestamp;
  final IconData icon;
  final Color iconColor;

  const PreviewActivity({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.icon,
    required this.iconColor,
  });
}

/// Explicit Development Preview Repository
class MockPreviewData {
  static const currentUser = PreviewUser(
    id: 'usr_current',
    name: 'Abhay Gupta',
    email: 'abhay@evenbill.app',
    defaultCurrency: 'USD',
    isPro: false,
  );

  static const List<PreviewGroup> groups = [
    PreviewGroup(
      id: 'grp_1',
      name: 'Apartment 404',
      type: 'Home',
      currency: 'USD',
      memberCount: 4,
      netBalance: 60.00,
      inviteCode: 'APT404EB',
    ),
    PreviewGroup(
      id: 'grp_2',
      name: 'Alps Ski Trip 2026',
      type: 'Trip',
      currency: 'EUR',
      memberCount: 6,
      netBalance: -17.50,
      inviteCode: 'ALPS2026',
    ),
    PreviewGroup(
      id: 'grp_3',
      name: 'Tokyo Autumn Odyssey',
      type: 'Trip',
      currency: 'JPY',
      memberCount: 3,
      netBalance: 142.00,
      inviteCode: 'TYO2026X',
    ),
    PreviewGroup(
      id: 'grp_4',
      name: 'Weekend Dining Club',
      type: 'Other',
      currency: 'USD',
      memberCount: 5,
      netBalance: 0.00,
      inviteCode: 'DINECLUB',
    ),
  ];

  static const List<PreviewFriend> friends = [
    PreviewFriend(
      id: 'fr_1',
      name: 'Elena Rostova',
      email: 'elena@example.com',
      netBalance: 45.00,
      currency: 'USD',
    ),
    PreviewFriend(
      id: 'fr_2',
      name: 'Marco Rossi',
      email: 'marco@example.com',
      netBalance: -25.00,
      currency: 'EUR',
    ),
    PreviewFriend(
      id: 'fr_3',
      name: 'Priya Patel',
      email: 'priya@example.com',
      netBalance: 80.00,
      currency: 'USD',
    ),
    PreviewFriend(
      id: 'fr_4',
      name: 'Sarah Jenkins',
      email: 'sarah@example.com',
      netBalance: 12.50,
      currency: 'GBP',
    ),
    PreviewFriend(
      id: 'fr_5',
      name: 'Kenji Sato',
      email: 'kenji@example.com',
      netBalance: 0.00,
      currency: 'JPY',
    ),
  ];

  static const List<PreviewExpense> expenses = [
    PreviewExpense(
      id: 'exp_1',
      description: 'Supermarket Grocery Stock-up',
      category: 'Groceries',
      groupName: 'Apartment 404',
      dateFormatted: 'Today, 2:15 PM',
      totalAmount: 120.00,
      currency: 'USD',
      paidBy: 'You paid \$120.00',
      yourNetShare: 90.00, // 3 roommates owe $30 each
      participants: ['Abhay', 'Elena', 'Marco', 'Priya'],
    ),
    PreviewExpense(
      id: 'exp_2',
      description: 'Chalet Booking Deposit',
      category: 'Travel',
      groupName: 'Alps Ski Trip 2026',
      dateFormatted: 'Yesterday',
      totalAmount: 350.00,
      currency: 'EUR',
      paidBy: 'Elena paid €350.00',
      yourNetShare: -58.33,
      participants: ['Elena', 'Abhay', 'Marco', 'Sarah', 'Kenji', 'Priya'],
    ),
    PreviewExpense(
      id: 'exp_3',
      description: 'High-speed Fiber Internet',
      category: 'Utilities',
      groupName: 'Apartment 404',
      dateFormatted: 'Oct 18',
      totalAmount: 75.00,
      currency: 'USD',
      paidBy: 'You paid \$75.00',
      yourNetShare: 56.25,
      participants: ['Abhay', 'Elena', 'Marco', 'Priya'],
    ),
    PreviewExpense(
      id: 'exp_4',
      description: 'Omakase Sushi Dinner',
      category: 'Food',
      groupName: 'Weekend Dining Club',
      dateFormatted: 'Oct 15',
      totalAmount: 185.00,
      currency: 'USD',
      paidBy: 'Sarah paid \$185.00',
      yourNetShare: -37.00,
      participants: ['Sarah', 'Abhay', 'Elena', 'Kenji', 'Priya'],
    ),
    PreviewExpense(
      id: 'exp_5',
      description: 'Movie Night & Popcorn',
      category: 'Entertainment',
      groupName: 'Direct Expense',
      dateFormatted: 'Oct 12',
      totalAmount: 32.00,
      currency: 'USD',
      paidBy: 'Marco paid \$32.00',
      yourNetShare: -16.00,
      participants: ['Marco', 'Abhay'],
    ),
  ];

  static const List<PreviewActivity> activities = [
    PreviewActivity(
      id: 'act_1',
      title: 'Elena Rostova settled up with you',
      subtitle: 'Recorded \$45.00 payment via UPI',
      timestamp: '10m ago',
      icon: Icons.handshake_rounded,
      iconColor: Color(0xFF0F9B6C),
    ),
    PreviewActivity(
      id: 'act_2',
      title: 'You added "Supermarket Grocery Stock-up"',
      subtitle: 'Apartment 404 • Total \$120.00',
      timestamp: '2h ago',
      icon: Icons.receipt_long_rounded,
      iconColor: Color(0xFF153C32),
    ),
    PreviewActivity(
      id: 'act_3',
      title: 'Elena added "Chalet Booking Deposit"',
      subtitle: 'Alps Ski Trip 2026 • Total €350.00',
      timestamp: 'Yesterday',
      icon: Icons.flight_takeoff_rounded,
      iconColor: Color(0xFF0284C7),
    ),
    PreviewActivity(
      id: 'act_4',
      title: 'Kenji Sato joined "Tokyo Autumn Odyssey"',
      subtitle: 'Joined using invite code TYO2026X',
      timestamp: '3d ago',
      icon: Icons.person_add_rounded,
      iconColor: Color(0xFF8B5CF6),
    ),
  ];
}
