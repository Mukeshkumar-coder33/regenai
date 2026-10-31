import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../app/app_config.dart';
import '../../../core/storage/session_storage.dart';
import '../../auth/data/auth_service.dart';
import 'project_model.dart';
import 'task_model.dart';

/// ReGen Tasks and Projects API Service
///
/// Connects to:
/// - `GET/POST /api/tasks`
/// - `PUT/DELETE /api/tasks/:id`
/// - `GET/POST /api/projects`
/// - `PUT/DELETE /api/projects/:id`
class TaskService {
  final http.Client _client;

  TaskService({http.Client? client}) : _client = client ?? http.Client();

  Future<Map<String, String>> _getHeaders({bool isSuperAdmin = false}) async {
    final token = await SessionStorage.getToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (isSuperAdmin) {
      headers['x-portal-view'] = 'superadmin';
    }
    return headers;
  }

  /// 1. Fetch All Tasks
  Future<List<TaskModel>> getTasks({bool isSuperAdmin = false}) async {
    final headers = await _getHeaders(isSuperAdmin: isSuperAdmin);
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/tasks');

    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
        return data.map((json) => TaskModel.fromJson(json as Map<String, dynamic>)).toList();
      }
      throw AuthException(message: 'Failed to load tasks (${res.statusCode})', statusCode: res.statusCode);
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }

  /// 2. Create Task
  Future<TaskModel> createTask(TaskModel task) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/tasks');

    try {
      final res = await _client.post(
        url,
        headers: headers,
        body: jsonEncode(task.toJson()),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200 || res.statusCode == 201) {
        final Map<String, dynamic> data = jsonDecode(res.body) as Map<String, dynamic>;
        return TaskModel.fromJson(data);
      }
      throw AuthException(message: 'Failed to create task (${res.statusCode})', statusCode: res.statusCode);
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }

  /// 3. Update Task
  Future<TaskModel> updateTask(String id, Map<String, dynamic> updates) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/tasks/$id');

    try {
      final res = await _client.put(
        url,
        headers: headers,
        body: jsonEncode(updates),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(res.body) as Map<String, dynamic>;
        return TaskModel.fromJson(data);
      }
      throw AuthException(message: 'Failed to update task (${res.statusCode})', statusCode: res.statusCode);
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }

  /// 4. Toggle Task Complete
  Future<TaskModel> toggleTaskComplete(String id, bool completed) async {
    return updateTask(id, {
      'status': completed ? 'done' : 'in_progress',
    });
  }

  /// 5. Delete Task
  Future<bool> deleteTask(String id) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/tasks/$id');

    try {
      final res = await _client.delete(url, headers: headers).timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }

  /// 6. Fetch Projects
  Future<List<ProjectModel>> getProjects() async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/projects');

    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
        return data.map((json) => ProjectModel.fromJson(json as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// 7. Create Project
  Future<ProjectModel> createProject(ProjectModel project) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/projects');

    try {
      final res = await _client.post(
        url,
        headers: headers,
        body: jsonEncode(project.toJson()),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200 || res.statusCode == 201) {
        final Map<String, dynamic> data = jsonDecode(res.body) as Map<String, dynamic>;
        return ProjectModel.fromJson(data);
      }
      throw AuthException(message: 'Failed to create project (${res.statusCode})', statusCode: res.statusCode);
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }

  /// 8. Delete Project
  Future<bool> deleteProject(String id) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/projects/$id');

    try {
      final res = await _client.delete(url, headers: headers).timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }
}

