import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class GroupAvatar extends StatelessWidget {
  final String groupType;
  final double size;

  const GroupAvatar({
    super.key,
    required this.groupType,
    this.size = 44.0,
  });

  IconData _getIcon(String type) {
    switch (type.toUpperCase()) {
      case 'HOME':
        return Icons.home_rounded;
      case 'TRIP':
        return Icons.flight_takeoff_rounded;
      case 'COUPLE':
        return Icons.favorite_rounded;
      case 'OTHER':
      default:
        return Icons.group_rounded;
    }
  }

  Color _getColor(String type) {
    switch (type.toUpperCase()) {
      case 'HOME':
        return AppColors.categoryHome;
      case 'TRIP':
        return AppColors.categoryTravel;
      case 'COUPLE':
        return AppColors.categoryEntertainment;
      case 'OTHER':
      default:
        return AppColors.forestGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = _getIcon(groupType);
    final color = _getColor(groupType);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: color.withOpacity(0.25), width: 1.0),
      ),
      child: Icon(icon, color: color, size: size * 0.52),
    );
  }
}
