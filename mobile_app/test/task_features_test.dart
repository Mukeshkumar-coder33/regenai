import 'package:flutter_test/flutter_test.dart';
import 'package:regen_mobile/features/tasks/data/task_model.dart';
import 'package:regen_mobile/features/tasks/presentation/tasks_view.dart';

void main() {
  group('Enterprise Task Features Tests', () {
    test('TaskAttachmentModel serialization and size calculation', () {
      final doc = TaskAttachmentModel(
        name: 'architecture_diagram.pdf',
        fileType: 'pdf',
        size: 2048 * 1024, // 2 MB
        data: 'JVBERi0xLjQKJ...',
      );

      expect(doc.name, 'architecture_diagram.pdf');
      expect(doc.displaySize, '2.0 MB');

      final json = doc.toJson();
      expect(json['name'], 'architecture_diagram.pdf');
      expect(json['data'], 'JVBERi0xLjQKJ...');

      final parsed = TaskAttachmentModel.fromJson(json);
      expect(parsed.name, 'architecture_diagram.pdf');
      expect(parsed.displaySize, '2.0 MB');
    });

    test('TaskProgressUpdateModel serialization and percentage handling', () {
      final update = TaskProgressUpdateModel(
        date: '2026-11-24T18:00:00Z',
        updateText: 'Completed 60% of backend schema migration',
        percentage: 60,
        employeeName: 'Mukesh Tester',
        employeeId: 'EMP-101',
      );

      final json = update.toJson();
      expect(json['percentage'], 60);
      expect(json['updateText'], contains('backend schema'));

      final parsed = TaskProgressUpdateModel.fromJson(json);
      expect(parsed.percentage, 60);
      expect(parsed.employeeName, 'Mukesh Tester');
    });

    test('TaskCompletionReportModel captures exact work times and employee details', () {
      final report = TaskCompletionReportModel(
        reportText: 'All task deliverables tested and verified.',
        submittedAt: '2026-11-24T18:30:00Z',
        startDay: 'Monday, Nov 24, 2026',
        startTime: '10:00 AM',
        endDay: 'Monday, Nov 24, 2026',
        endTime: '06:30 PM',
        employeeName: 'Vyshwa Admin',
        employeeId: 'EMP-001',
        workingTime: '8 hrs 30 mins',
      );

      final json = report.toJson();
      expect(json['startDay'], 'Monday, Nov 24, 2026');
      expect(json['startTime'], '10:00 AM');
      expect(json['endDay'], 'Monday, Nov 24, 2026');
      expect(json['endTime'], '06:30 PM');
      expect(json['workingTime'], '8 hrs 30 mins');
      expect(json['employeeName'], 'Vyshwa Admin');

      final parsed = TaskCompletionReportModel.fromJson(json);
      expect(parsed.startDay, 'Monday, Nov 24, 2026');
      expect(parsed.workingTime, '8 hrs 30 mins');
    });

    test('TaskExtensionRequestModel captures deadline extension and status transitions', () {
      final req = TaskExtensionRequestModel(
        requestedDueDate: '2026-11-28',
        requestedDueTime: '06:00 PM',
        reason: 'Client requested additional features and edge-case testing',
        status: 'pending',
        requestedAt: '2026-11-24T18:15:00Z',
      );

      expect(req.isPending, isTrue);
      expect(req.isAccepted, isFalse);

      final json = req.toJson();
      expect(json['status'], 'pending');

      final parsed = TaskExtensionRequestModel.fromJson(json);
      expect(parsed.requestedDueDate, '2026-11-28');
      expect(parsed.isPending, isTrue);
    });

    test('TaskModel integrates attachments, progressUpdates, completionReport, and extensionRequest', () {
      final task = TaskModel(
        id: 'task-full-1',
        title: 'Complete Mobile App Tasks Redux Refactor',
        status: 'in_progress',
        priority: 'high',
        assignedTo: 'EMP-101',
        attachments: [
          const TaskAttachmentModel(name: 'spec.docx', size: 1024),
        ],
        progressPercentage: 75,
        progressUpdates: [
          const TaskProgressUpdateModel(
            date: '2026-11-24T12:00:00Z',
            updateText: 'Day 1 completed',
            percentage: 50,
          ),
          const TaskProgressUpdateModel(
            date: '2026-11-24T16:00:00Z',
            updateText: 'Day 2 completed',
            percentage: 75,
          ),
        ],
        extensionRequest: const TaskExtensionRequestModel(
          requestedDueDate: '2026-11-27',
          status: 'pending',
        ),
      );

      expect(task.attachments.length, 1);
      expect(task.progressUpdates.length, 2);
      expect(task.progressPercentage, 75);
      expect(task.extensionRequest?.isPending, isTrue);

      final json = task.toJson();
      expect((json['attachments'] as List).length, 1);
      expect((json['progressUpdates'] as List).length, 2);

      final parsed = TaskModel.fromJson(json);
      expect(parsed.attachments.first.name, 'spec.docx');
      expect(parsed.progressUpdates.last.percentage, 75);
      expect(parsed.extensionRequest?.requestedDueDate, '2026-11-27');
    });

    test('TasksView.computeEndDateTime computes auto calculated deadline', () {
      final res = TasksView.computeEndDateTime('2026-11-24', 3, 'days');
      expect(res['endDate'], '2026-11-27');
      expect(res['dueTime'], '18:00');
    });

    test('Daily progress percentage initializes directly to current progress', () {
      final taskWith42 = TaskModel(
        id: 't-42',
        title: 'Feature Work',
        status: 'in_progress',
        progressPercentage: 42,
      );
      expect(taskWith42.progressPercentage.clamp(0, 100), 42);

      final taskZero = TaskModel(
        id: 't-0',
        title: 'Feature Work',
        status: 'pending',
        progressPercentage: 0,
      );
      expect(taskZero.progressPercentage.clamp(0, 100), 0);
    });
  });
}
