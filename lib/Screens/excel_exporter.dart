import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';
import 'package:intl/intl.dart'; // Required for date formatting

/// A helper function to export medicine intake logs to an Excel file.
///
/// Takes a list of intake logs and patient information, then creates
/// and downloads an Excel file.
Future<void> exportMedicineIntakeToExcel({
  required List<Map<String, dynamic>> intakeLogs,
  required String patientName,
  required DateTime selectedMonth,
}) async {
  try {
    if (intakeLogs.isEmpty) {
      // We cannot show a SnackBar directly here as we don't have a BuildContext.
      // This case should be handled on the UI side when calling this function.
      print('No medicine intake data to download for this month.');
      return;
    }

    var excel = Excel.createExcel();
    Sheet sheet = excel['Medicine Intake Tracking']; // Name of the sheet

    // Add column headers
    sheet.appendRow([
      "Medicine Name",
      "Scheduled Date",
      "Scheduled Time",
      "Status",
      "Actual Taken Time"
    ]);

    // Add medicine intake log data
    for (var log in intakeLogs) {
      final String medicineName = log['medicineName'] ?? 'N/A';
      final DateTime scheduledDateTime = log['scheduledTime'];
      final String scheduledDate = DateFormat('yyyy-MM-dd').format(scheduledDateTime);
      final String scheduledTime = DateFormat('HH:mm').format(scheduledDateTime);
      final bool taken = log['taken'] ?? false;
      final DateTime? takenAt = log['takenAt'];

      final String status = taken ? "Taken" : "Not Taken";
      final String actualTakenTime = takenAt != null ? DateFormat('HH:mm').format(takenAt) : "N/A";

      sheet.appendRow([
        medicineName,
        scheduledDate,
        scheduledTime,
        status,
        actualTakenTime,
      ]);
    }

    var bytes = excel.save();
    final String fileName =
        '${patientName}_MedicineIntake_${DateFormat('yyyy-MM').format(selectedMonth)}.xlsx';
    final MimeType mimeType = MimeType.microsoftExcel;

    await FileSaver.instance.saveFile(
      name: fileName,
      bytes: Uint8List.fromList(bytes!),
      mimeType: mimeType,
    );

    print('Medicine intake data saved as: $fileName');
    // You can return true or a success message if you want to handle it on the UI side
  } catch (e) {
    print("Error during Excel download: $e");
    // Re-throw the error to allow the calling function (UI) to handle it
    rethrow;
  }
}