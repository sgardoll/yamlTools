import 'package:flutter/material.dart';

class ProjectHeader extends StatelessWidget {
  final String projectName;

  const ProjectHeader({
    Key? key,
    required this.projectName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Color(0xFF1E293B), // Slate-800
        border: Border(
          bottom: BorderSide(color: Color(0xFF334155), width: 1), // Slate-700
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Color(0xFF3B82F6).withOpacity(0.1), // Blue with opacity
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Color(0xFF3B82F6).withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Icon(
              Icons.folder_outlined,
              color: Color(0xFF3B82F6), // Blue-500
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Project:',
            style: TextStyle(
              color: Color(0xFF94A3B8), // Slate-400
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            constraints: BoxConstraints(maxWidth: 300),
            child: Text(
              projectName,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.25,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
