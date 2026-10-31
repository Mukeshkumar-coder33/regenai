import 'package:flutter/material.dart';

/// Role-aware Calendar Event Model
class CalendarEventModel {
  final String id;
  final String title;
  final DateTime dateTime;
  final String time;
  final String category; // 'Meeting', 'Discussion', 'Review', 'Holiday', 'Shift', 'Audit'
  final String? description;
  final String? location;
  final String? createdBy;
  final String? companyId;
  final String roleAccess; // 'all', 'company', 'admin'
  final Color? color;
  final Color? bg;
  final IconData? icon;

  const CalendarEventModel({
    required this.id,
    required this.title,
    required this.dateTime,
    required this.time,
    required this.category,
    this.description,
    this.location,
    this.createdBy,
    this.companyId,
    this.roleAccess = 'all',
    this.color,
    this.bg,
    this.icon,
  });

  factory CalendarEventModel.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(json['date'] ?? json['dateTime'] ?? DateTime.now().toIso8601String());
    } catch (_) {
      parsedDate = DateTime.now();
    }

    return CalendarEventModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      title: (json['title'] ?? json['name'] ?? 'Event').toString(),
      dateTime: parsedDate,
      time: (json['time'] ?? '10:00 AM - 11:00 AM').toString(),
      category: (json['category'] ?? (json['isHoliday'] == true ? 'Holiday' : 'Meeting')).toString(),
      description: json['description']?.toString(),
      location: json['location']?.toString(),
      createdBy: json['createdBy']?.toString(),
      companyId: json['companyId']?.toString(),
      roleAccess: (json['roleAccess'] ?? 'all').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'dateTime': dateTime.toIso8601String(),
      'time': time,
      'category': category,
      'description': description,
      'location': location,
      'createdBy': createdBy,
      'companyId': companyId,
      'roleAccess': roleAccess,
    };
  }

  CalendarEventModel copyWith({
    String? id,
    String? title,
    DateTime? dateTime,
    String? time,
    String? category,
    String? description,
    String? location,
    String? createdBy,
    String? companyId,
    String? roleAccess,
    Color? color,
    Color? bg,
    IconData? icon,
  }) {
    return CalendarEventModel(
      id: id ?? this.id,
      title: title ?? this.title,
      dateTime: dateTime ?? this.dateTime,
      time: time ?? this.time,
      category: category ?? this.category,
      description: description ?? this.description,
      location: location ?? this.location,
      createdBy: createdBy ?? this.createdBy,
      companyId: companyId ?? this.companyId,
      roleAccess: roleAccess ?? this.roleAccess,
      color: color ?? this.color,
      bg: bg ?? this.bg,
      icon: icon ?? this.icon,
    );
  }
}

