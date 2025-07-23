import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:med_ad_admin/Screens/excel_exporter.dart';



class PatientProfile extends StatefulWidget {
  final String patientId;
  final String patientName;
  final String patientPhone;
  // final String s;

  const PatientProfile({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.patientPhone,

  });

  @override
  State<PatientProfile> createState() => _PatientProfileState();
}

class _PatientProfileState extends State<PatientProfile> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
    final Uuid uuid = Uuid();
    DateTime _selectedMonth = DateTime.now();
  // late Stream<QuerySnapshot> _medicineIntakeStream;
          // late Stream<List<Map<String, dynamic>>> _medicineIntakeStream;


  ///////
    @override
  void initState() {
    super.initState();
    

  }


  Widget _buildIntakeStatusIndicator(bool taken, DateTime? takenAt) {
    if (taken) {
      return Column(
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: 24),
          if (takenAt != null)
            Text(DateFormat('HH:mm').format(takenAt), style: TextStyle(fontSize: 10, color: Colors.green[700])),
        ],
      );
    } else {
      return Icon(Icons.cancel, color: Colors.red, size: 24);
    }
  }
 Stream<List<Map<String, dynamic>>> _fetchDailyPerformanceLogs() {
  print("Attempting to fetch daily performance logs for patient ID: ${widget.patientId}");
  return _firestore
      .collection('ActivePatient')
      .doc(widget.patientId)
      .collection('DailyPerformances') // <--- هنا التعديل! غيّرها من 'dailyPerformance' إلى 'dailyPerformances'
      .orderBy('date', descending: false)
      .snapshots()
      .map((snapshot) {
    print("Fetched ${snapshot.docs.length} daily performance documents.");
    if (snapshot.docs.isNotEmpty) {
      print("First daily performance document data: ${snapshot.docs.first.data()}");
    }
    return snapshot.docs.map((doc) => doc.data()).toList();
  });
}


double _calculateOverallAdherenceFromDailyPerformance(
    List<Map<String, dynamic>> dailyPerformanceLogs) {
  if (dailyPerformanceLogs.isEmpty) {
    return 0.0;
  }

  double totalDailyPercentages = 0.0;
  for (var log in dailyPerformanceLogs) {
    if (log.containsKey('dailyPercentage') && log['dailyPercentage'] is num) {
      totalDailyPercentages += (log['dailyPercentage'] as num).toDouble();
    }
  }
  return totalDailyPercentages / dailyPerformanceLogs.length; // Returns average
}
 // دالة لجلب بيانات تتبع الأدوية لشهر محدد
  Stream<List<Map<String, dynamic>>> _fetchMedicineIntakeForMonth(DateTime month) async* {
  DateTime firstDayOfMonth = DateTime(month.year, month.month, 1);
  DateTime lastDayOfMonth = DateTime(month.year, month.month + 1, 0);

  final patientMedicineSnapshot = await _firestore
      .collection('ActivePatient')
      .doc(widget.patientId)
      .collection('PatientMedicine')
      .get();

  List<Map<String, dynamic>> allIntakeLogs = [];

  for (final medicineDoc in patientMedicineSnapshot.docs) {
    final intakeSnapshot = await _firestore
        .collection('ActivePatient')
        .doc(widget.patientId)
        .collection('PatientMedicine')
        .doc(medicineDoc.id)
        .collection('MedicineIntakeLogs')
        .where('scheduledTime', isGreaterThanOrEqualTo: Timestamp.fromDate(firstDayOfMonth.toUtc()))
        .where('scheduledTime', isLessThanOrEqualTo: Timestamp.fromDate(lastDayOfMonth.add(const Duration(days: 1)).toUtc()))
        .orderBy('scheduledTime',
            descending:
                false)
        .get(); 


    for (final intakeDoc in intakeSnapshot.docs) {
      final intakeData = intakeDoc.data() as Map<String, dynamic>;
      allIntakeLogs.add({
        'medicineName': medicineDoc['MedicineName'] ?? 'N/A',
        'scheduledTime': (intakeData['scheduledTime'] as Timestamp).toDate().toLocal(),
        'taken': intakeData['taken'] ?? false,
        'takenAt': intakeData['takenAt'] != null ? (intakeData['takenAt'] as Timestamp).toDate().toLocal() : null,
      });
    }
  }

  // ترتيب القائمة النهائية بشكل إضافي لضمان الترتيب
  allIntakeLogs.sort((a, b) => a['scheduledTime'].compareTo(b['scheduledTime']));

  yield allIntakeLogs;
}

void _previousMonth() {
  setState(() {
    _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
  });
}

void _nextMonth() {
  setState(() {
    _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
  });
}


  double calculateAdherence(List<Map<String, dynamic>> intakeLogs) {
    if (intakeLogs.isEmpty) return 0.0;

    // Group logs by day
    Map<DateTime, List<Map<String, dynamic>>> dailyLogs = {};
    for (var log in intakeLogs) {
      DateTime date = DateTime(log['scheduledTime'].year, log['scheduledTime'].month, log['scheduledTime'].day);
      dailyLogs.putIfAbsent(date, () => []).add(log);
    }

    int totalDaysWithScheduledMedicines = 0;
    int adherentDays = 0;

    // Iterate through each day with scheduled medicines
    for (var date in dailyLogs.keys) {
      totalDaysWithScheduledMedicines++;
      bool allTakenForDay = true;
      for (var log in dailyLogs[date]!) {
        if (!log['taken']) {
          allTakenForDay = false;
          break;
        }
      }
      if (allTakenForDay) {
        adherentDays++;
      }
    }

    return totalDaysWithScheduledMedicines > 0 ? (adherentDays / totalDaysWithScheduledMedicines) : 0.0;
  }

double calculateAdherenceBasedOnScheduledDays(List<Map<String, dynamic>> intakeLogs) {
  if (intakeLogs.isEmpty) return 0.0;

  // Filter valid logs with scheduled times
  final validLogs = intakeLogs.where((log) => log['scheduledTime'] != null).toList();

  // Group logs by date
  final Map<DateTime, List<Map<String, dynamic>>> groupedByDay = {};

  for (var log in validLogs) {
    final scheduled = log['scheduledTime'];
    final dateKey = DateTime(scheduled.year, scheduled.month, scheduled.day);
    groupedByDay.putIfAbsent(dateKey, () => []).add(log);
  }

  int totalScheduledDays = groupedByDay.length;
  int fullAdherenceDays = 0;

  groupedByDay.forEach((day, logs) {
    final allTaken = logs.every((log) => log['taken'] == true);
    if (allTaken) fullAdherenceDays++;
  });

  return totalScheduledDays == 0 ? 0.0 : fullAdherenceDays / totalScheduledDays;
}

  /// Gets the start date of the medicine regimen from the earliest scheduled intake log.
  DateTime? getStartDate(List<Map<String, dynamic>> intakeLogs) {
    if (intakeLogs.isEmpty) return null;
    return intakeLogs.first['scheduledTime']; // Logs are already sorted by scheduledTime
  }


  int getAdherenceDays(DateTime? startDate) {
    if (startDate == null) return 0;
    // Normalize dates to just the day part to avoid time differences
    DateTime today = DateTime.now();
    DateTime startOfDayToday = DateTime(today.year, today.month, today.day);
    DateTime startOfDayStartDate = DateTime(startDate.year, startDate.month, startDate.day);

    // Calculate the difference in days
    return startOfDayToday.difference(startOfDayStartDate).inDays + 1; // +1 to include the start day
  }


int getAdherenceDaysFromLogs(List<Map<String, dynamic>> intakeLogs) {
  final validLogs = intakeLogs.where((log) => log['scheduledTime'] != null).toList();

  final uniqueDays = <String>{};

  for (var log in validLogs) {
    final date = log['scheduledTime'];
    final key = "${date.year}-${date.month}-${date.day}";
    uniqueDays.add(key);
  }

  return uniqueDays.length;
}


Future<void> _downloadIntakeLogsAsExcel() async {
    try {
      // 1. جلب بيانات تناول الأدوية للشهر المحدد
      // نستخدم .first للحصول على القيمة الأولى من Stream
      final List<Map<String, dynamic>> intakeLogs =
          await _fetchMedicineIntakeForMonth(_selectedMonth).first;

      // 2. التحقق مما إذا كانت هناك أي بيانات
      if (intakeLogs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد بيانات تناول دواء لتنزيلها لهذا الشهر.')),
        );
        return; // الخروج من الدالة إذا لم يكن هناك بيانات
      }

      // 3. استدعاء الدالة المساعدة لتصدير البيانات إلى Excel
      // هنا نمرر البيانات اللازمة للدالة الخارجية
      await exportMedicineIntakeToExcel(
        intakeLogs: intakeLogs,
        patientName: widget.patientName, // اسم المريض من الـ widget الحالي
        selectedMonth: _selectedMonth,   // الشهر المحدد حاليًا
      );

      // 4. عرض رسالة نجاح للمستخدم
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم حفظ بيانات تناول الأدوية بنجاح.')),
      );
    } catch (e) {
      // 5. التعامل مع أي أخطاء وعرض رسالة فشل
      print("خطأ في تنزيل Excel من الواجهة الأمامية: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل في تنزيل ملف Excel: $e')),
      );
    }
  }

  ///////////////////////////////////////////////////////////////////////////////////
  

  Future<void> addMedicine(Map<String, dynamic> medicineData) async {
    await _firestore
        .collection('ActivePatient')
        .doc(widget.patientId)
        .collection('PatientMedicine')
        .add(medicineData);
  }

  void showAddMedicineDialog() {
  TextEditingController dosageController = TextEditingController();
  TextEditingController conditionController = TextEditingController();
  TextEditingController pillsPerDoseController = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  List<String> _medicineTimes = [];
  List<String> _nowTimes = [];
  String? selectedMedicineName;
  String? selectedMedicineImageUrl;

  Future<void> _pickStartTime(BuildContext context, StateSetter dialogSetState) async {
    final TimeOfDay? picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null) {
      final now = DateTime.now();
      final dateTime = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
      final utcDateTime = dateTime.toUtc();
      dialogSetState(() {
        _medicineTimes.add('${utcDateTime.hour.toString().padLeft(2, '0')}:${utcDateTime.minute.toString().padLeft(2, '0')}');
        _nowTimes.add('${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
      });
    }
  }

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text("Add Medicine"),
        content: StatefulBuilder(
          builder: (context, setState) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FutureBuilder<QuerySnapshot>(
                    future: _firestore.collection('medicines').get(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return CircularProgressIndicator();
                      }
                      if (snapshot.hasError) {
                        return Text('Error: ${snapshot.error}');
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Text('No medicines found.');
                      }
                      List<String> medicineNames = snapshot.data!.docs.map((doc) => doc['name'].toString()).toList();
                 return   DropdownSearch<String>( // <--- تم التغيير هنا من .multiSelection إلى عادي
  items: medicineNames,
  selectedItem: selectedMedicineName, // <--- تغيير من selectedItems
  popupProps: PopupProps.menu( // <--- تم التغيير هنا من PopupPropsMultiSelection إلى PopupProps
    showSearchBox: true,
    searchFieldProps: TextFieldProps(
      decoration: InputDecoration(
        labelText: "Search Medicine",
      ),
    ),
   
  ),
  dropdownButtonProps: DropdownButtonProps(
    icon: Icon(Icons.arrow_drop_down),
  ),
  dropdownBuilder: (context, selectedItem) {
    return Text(
      selectedItem != null ? selectedItem : "Select Medicine",
    );
  },
  onChanged: (String? value) { 
    setState(() {
      selectedMedicineName = value;
      if (value != null) {
        selectedMedicineImageUrl = snapshot.data!.docs
            .firstWhere((doc) => doc['name'] == value)['imageUrl'];
      } else {
        selectedMedicineImageUrl = null;
      }
    });
  },
);
                    },
                  ),
                  TextField(controller: dosageController, decoration: InputDecoration(labelText: "Dosage")),
                  TextField(controller: conditionController, decoration: InputDecoration(labelText: "Medication Instructions")),
                  TextField(controller: pillsPerDoseController, decoration: InputDecoration(labelText: "Number of Pills Per Dose")),
                  SizedBox(height: 10),
                  ListTile(
                    title: Text(_startDate == null ? "Select Start Date" : DateFormat.yMMMd().format(_startDate!.toLocal())),
                    trailing: Icon(Icons.calendar_today),
                    onTap: () async {
                      DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() => _startDate = picked.toUtc());
                      }
                    },
                  ),
                  ListTile(
                    title: Text(_endDate == null ? "Select End Date" : DateFormat.yMMMd().format(_endDate!.toLocal())),
                    trailing: Icon(Icons.calendar_today),
                    onTap: () async {
                      DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() => _endDate = picked.toUtc());
                      }
                    },
                  ),
                  Text("Medicine Times (Local)"), // عرض الوقت المحلي هنا
                  ..._nowTimes.map((time) => ListTile(title: Text(time), trailing: Icon(Icons.check_circle, color: Colors.green))),
                  ElevatedButton(
                    onPressed: () => _pickStartTime(context, setState), // تمرير setState الخاص بالـ AlertDialog
                    child: Text("Add Time"),
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              if (selectedMedicineName != null && dosageController.text.isNotEmpty &&
                  pillsPerDoseController.text.isNotEmpty && _startDate != null && _endDate != null) {
                Map<String, dynamic> newMedicine = {
                  "MedicineName": selectedMedicineName,
                  "MedicineDosage": dosageController.text,
                  "Medication Instructions": conditionController.text,
                  "NumberOfPillsPerDose": pillsPerDoseController.text,
                  "StartDate": _startDate,
                  "EndDate": _endDate,
                  "MedicineTime": _medicineTimes,
                  "nowTime": _nowTimes,
                  "MedicineImageUrl": selectedMedicineImageUrl,
                };
                addMedicine(newMedicine);
                Navigator.pop(context);
              }
            },
            child: Text("Save"),
          ),
        ],
      );
    },
  );
}



/// تعديل دواء موجود
void showEditMedicineDialog(DocumentSnapshot medicineDoc) {
  TextEditingController nameController = TextEditingController(text: medicineDoc['MedicineName']);
  TextEditingController dosageController = TextEditingController(text: medicineDoc['MedicineDosage']);
  TextEditingController conditionController = TextEditingController(text: medicineDoc['Medication Instructions']);
  TextEditingController pillsPerDoseController = TextEditingController(text: medicineDoc['NumberOfPillsPerDose']?.toString() ?? '');
  DateTime _startDate = (medicineDoc['StartDate'] as Timestamp).toDate().toUtc();
  DateTime _endDate = (medicineDoc['EndDate'] as Timestamp).toDate().toUtc();
  // استرداد الأوقات بتوقيت UTC وعرضها بالتوقيت المحلي
  List<String> _medicineTimesUtc = List<String>.from(medicineDoc['MedicineTime'] ?? []);
  List<String> _medicineTimesLocal = _medicineTimesUtc.map((utcTimeString) {
    final parts = utcTimeString.split(':');
    final utcTime = DateTime.utc(DateTime.now().year, DateTime.now().month, DateTime.now().day, int.parse(parts[0]), int.parse(parts[1]));
    return DateFormat('HH:mm').format(utcTime.toLocal());
  }).toList();

  Future<void> _editTime(BuildContext context, String oldTimeLocal, StateSetter dialogSetState) async {
    final partsLocal = oldTimeLocal.split(':');
    final initialTime = TimeOfDay(hour: int.parse(partsLocal[0]), minute: int.parse(partsLocal[1]));
    final TimeOfDay? picked = await showTimePicker(context: context, initialTime: initialTime);
    if (picked != null) {
      dialogSetState(() {
        final now = DateTime.now();
        final dateTime = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
        final newTimeUtcString = '${dateTime.toUtc().hour.toString().padLeft(2, '0')}:${dateTime.toUtc().minute.toString().padLeft(2, '0')}';
        final newTimeLocal = DateFormat('HH:mm').format(dateTime.toLocal());

        final localIndex = _medicineTimesLocal.indexOf(oldTimeLocal);
        if (localIndex != -1) {
          _medicineTimesLocal[localIndex] = newTimeLocal;
          // تحديث القائمة الأصلية بتوقيت UTC
          _medicineTimesUtc[localIndex] = newTimeUtcString;
        }

          // تحديث nowTime في Firestore
          List<dynamic> originalNowTimes = List<dynamic>.from(medicineDoc['nowTime'] ?? []);
          if (localIndex < originalNowTimes.length) {
            originalNowTimes[localIndex] = newTimeLocal; // استخدام الوقت المحلي هنا
            medicineDoc.reference.update({'nowTime': originalNowTimes}).then((_) {
              print("nowTime updated successfully in Firestore");
            }).catchError((error) {
              print("Error updating nowTime in Firestore: $error");
            });
          }
        
      });
    }
  }
Future<void> _deleteTime(BuildContext context, int indexToDelete, StateSetter dialogSetState) async {
    dialogSetState(() {
      if (indexToDelete >= 0 && indexToDelete < _medicineTimesLocal.length) {
        // حذف الوقت المحلي
        final deletedLocalTime = _medicineTimesLocal.removeAt(indexToDelete);
        // حذف الوقت الـ UTC المقابل
        if (indexToDelete < _medicineTimesUtc.length) {
          _medicineTimesUtc.removeAt(indexToDelete);
        }

        // حذف الوقت الحالي (بدون تحويل UTC) المقابل من Firestore
        List<dynamic> originalNowTimes = List<dynamic>.from(medicineDoc['nowTime'] ?? []);
        if (indexToDelete < originalNowTimes.length) {
          originalNowTimes.removeAt(indexToDelete);
          medicineDoc.reference.update({'nowTime': originalNowTimes}).then((_) {
            print("nowTime deleted successfully in Firestore");
          }).catchError((error) {
            print("Error deleting nowTime in Firestore: $error");
          });
        }

        // تحديث MedicineTime في Firestore
        medicineDoc.reference.update({'MedicineTime': _medicineTimesUtc}).then((_) {
          print("MedicineTime updated after deletion in Firestore");
        }).catchError((error) {
          print("Error updating MedicineTime after deletion in Firestore: $error");
        });
      } 
    });
  }

  Future<void> _addTime(BuildContext context, StateSetter dialogSetState) async {
    final TimeOfDay? picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null) {
      dialogSetState(() {
        final now = DateTime.now();
        final dateTime = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
        final newTimeUtcString = '${dateTime.toUtc().hour.toString().padLeft(2, '0')}:${dateTime.toUtc().minute.toString().padLeft(2, '0')}';
        final newTimeLocal = DateFormat('HH:mm').format(dateTime.toLocal());
        _medicineTimesLocal.add(newTimeLocal);
        _medicineTimesUtc.add(newTimeUtcString);

        // إضافة الوقت الحالي (بدون تحويل UTC) إلى قائمة nowTime
        List<dynamic> originalNowTimes = List<dynamic>.from(medicineDoc['nowTime'] ?? []);
        originalNowTimes.add('${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
        medicineDoc.reference.update({'nowTime': originalNowTimes}).then((_) {
          print("nowTime added successfully in Firestore");
        }).catchError((error) {
          print("Error adding nowTime in Firestore: $error");
        });
      });
    }
  }
  

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text("Edit Medicine"),
        content: StatefulBuilder(
          builder: (context, setState) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameController, decoration: InputDecoration(labelText: "Medicine Name")),
                  TextField(controller: dosageController, decoration: InputDecoration(labelText: "Dosage")),
                  TextField(controller: conditionController, decoration: InputDecoration(labelText: "Medication Instructions")),
                  TextField(controller: pillsPerDoseController, decoration: InputDecoration(labelText: "Number of Pills Per Dose")),
                  SizedBox(height: 10),
                  ListTile(
                    title: Text(DateFormat.yMMMd().format(_startDate.toLocal())),
                    trailing: Icon(Icons.calendar_today),
                    onTap: () async {
                      DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: _startDate.toLocal(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() => _startDate = picked.toUtc());
                      }
                    },
                  ),
                  ListTile(
                    title: Text(DateFormat.yMMMd().format(_endDate.toLocal())),
                    trailing: Icon(Icons.calendar_today),
                    onTap: () async {
                      DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: _endDate.toLocal(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() => _endDate = picked.toUtc());
                      }
                    },
                  ),
                 Text("Medicine Times (Local)"),
                  ..._medicineTimesLocal.asMap().entries.map((entry) {
                    int index = entry.key;
                    String time = entry.value;
                    return ListTile(
                      title: Text(time),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.edit),
                            onPressed: () => _editTime(context, time, setState),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete),
                            onPressed: () => _deleteTime(context, index, setState),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  ElevatedButton(
                    onPressed: () => _addTime(context, setState),
                    child: Text("Add Time"),
                  ),
                 
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              await _firestore
                  .collection('ActivePatient')
                  .doc(widget.patientId)
                  .collection('PatientMedicine')
                  .doc(medicineDoc.id)
                  .update({
                "MedicineName": nameController.text,
                "MedicineDosage": dosageController.text,
                "Medication Instructions": conditionController.text,
                "NumberOfPillsPerDose": pillsPerDoseController.text,
                "StartDate": _startDate,
                "EndDate": _endDate,
                "MedicineTime": _medicineTimesUtc, // حفظ قائمة UTC المعدلة
              }).then((_) {
                print("Medicine details updated successfully in Firestore");
                Navigator.pop(context);
              }).catchError((error) {
                print("Error updating medicine details in Firestore: $error");
              });
            },
            child: Text("Update"),
          ),
        ],
      );
    },
  );
}



void deleteMedicine(String medicineId) {
showDialog(
context: context,
builder: (context) {
return AlertDialog(
title: Text("Delete Medicine"),
content: Text("Are you sure you want to delete this medicine?"),
actions: [
TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel")),
ElevatedButton(
onPressed: () async {
await _firestore
    .collection('ActivePatient')
    .doc(widget.patientId)
    .collection('PatientMedicine')
    .doc(medicineId)
    .delete();
Navigator.pop(context);
},
child: Text("Delete"),
),
],
);
},
);
}




 Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(title: Text("Patient Profile")),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SingleChildScrollView( // سكرول داون واحد للصفحة الرئيسية
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  children: [
                    Text(widget.patientName, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    Text("Phone: ${widget.patientPhone}", style: TextStyle(fontSize: 16)),
                  ],
                ),
                SizedBox(height: 20),
                ElevatedButton(
                  onPressed: showAddMedicineDialog,
                  child: Text("Add Medicine"),
                ),
                SizedBox(height: 20),
                StreamBuilder<QuerySnapshot>(
                  stream: _firestore.collection('ActivePatient').doc(widget.patientId).collection('PatientMedicine').snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
                    var medicines = snapshot.data!.docs;
                    return medicines.isEmpty
                        ? Center(child: Text("No medicines added yet."))
                        : SingleChildScrollView( // سكرول داون أفقي لجدول الأدوية
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowColor: MaterialStateColor.resolveWith((states) => Colors.grey[200]!),
                              dataRowColor: MaterialStateProperty.resolveWith<Color?>((Set<MaterialState> states) {
                                if (states.contains(MaterialState.selected)) return Colors.grey[300];
                                return null;
                              }),
                              dividerThickness: 1,
                              columns: [
                                DataColumn(label: Text("Image")),
                                DataColumn(label: Text("Medicine")),
                                DataColumn(label: Text("Dosage")),
                                DataColumn(label: Text("Instructions")),
                                DataColumn(label: Text("Times")),
                                DataColumn(label: Text("Actions")),
                              ],
                              rows: medicines.map((doc) {
                                var medicine = doc.data() as Map<String, dynamic>;
                                return DataRow(cells: [
                                  DataCell(medicine["MedicineImageUrl"] != null
                                      ? Image.network(medicine["MedicineImageUrl"], width: 50, height: 50)
                                      : SizedBox()),
                                  DataCell(Text(medicine["MedicineName"] ?? "")),
                                  DataCell(Text(medicine["MedicineDosage"] ?? "")),
                                  DataCell(Text(medicine["Medication Instructions"] ?? "")),
                                  DataCell(
                                    Text(
                                      (medicine["MedicineTime"] as List<dynamic>)
                                           .map((utcTimeString) {
                                            final parts = (utcTimeString as String).split(':');
                                            final utcTime = DateTime.utc(DateTime.now().year, DateTime.now().month, DateTime.now().day, int.parse(parts[0]), int.parse(parts[1]));
                                            final localTime = utcTime.toLocal();
                                            return DateFormat('HH:mm').format(localTime);
                                          })
                                              .join(", ") ??
                                          "",
                                    ),
                                  ),
                                  DataCell(
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: Icon(Icons.edit, color: Colors.blue),
                                          onPressed: () => showEditMedicineDialog(doc),
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.delete, color: Colors.red),
                                          onPressed: () => deleteMedicine(doc.id),
                                        ),
                                      ],
                                    ),
                                  ),
                                ]);
                              }).toList(),
                            ),
                          );
                  },
                ),
                // Divider(),
                SizedBox(height: 30,),
          Divider(height: 40, thickness: 2, color: Colors.grey[300]),
                          SizedBox(height: 30,),
Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(12),
    color: Colors.white,
    boxShadow: [
      BoxShadow(
        color: Colors.grey.withOpacity(0.2),
        spreadRadius: 2,
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ],
  ),
  child: StreamBuilder<List<Map<String, dynamic>>>(
    // هنا نستخدم الدالة الجديدة لجلب بيانات الأداء اليومي
    stream: _fetchDailyPerformanceLogs(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      } else if (snapshot.hasError) {
        // طباعة الخطأ للمساعدة في التصحيح
        print("Error in Daily Performance Stream: ${snapshot.error}");
        return Center(child: Text("Error: ${snapshot.error}"));
      } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
        // حالة عدم وجود بيانات أداء يومي: نعرض قيمًا افتراضية
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Adherence Rate",
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[800]),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text(
                  "0.0%", // قيمة افتراضية للنسبة
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 120,
                  height: 12,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: Colors.grey[300],
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: 0.0, // نسبة 0%
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              "Adherence Days: 0", // قيمة افتراضية للأيام
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              "Start Date: N/A", // قيمة افتراضية للتاريخ
              style: TextStyle(fontSize: 16),
            ),
          ],
        );
      } else {
        // إذا كان هناك بيانات، نبدأ الحسابات
        final dailyPerformanceLogs = snapshot.data!;

        // حساب النسبة المئوية الكلية للالتزام
        final overallAdherencePercentage =
            _calculateOverallAdherenceFromDailyPerformance(dailyPerformanceLogs);

        DateTime? startDate;
        int adherenceDays = 0;

        if (dailyPerformanceLogs.isNotEmpty) {
          // جلب تاريخ البدء من أول سجل (لأنه تم ترتيبه في الدالة)
          // وتحويله من String "yyyy-MM-ddTHH:mm:ss.SSS" إلى DateTime
          try {
            startDate = DateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS").parse(dailyPerformanceLogs.first['date']);
            // التأكد من أن startDate هو بداية اليوم فقط (تجاهل الوقت)
            startDate = DateTime(startDate.year, startDate.month, startDate.day);
          } catch (e) {
            print("Error parsing start date from dailyPerformance: $e");
            startDate = null; // في حالة فشل التحويل
          }

          // حساب عدد الأيام الفريدة التي تم تسجيل أداء لها
          final uniqueRecordedDays = <String>{};
          for (var log in dailyPerformanceLogs) {
            if (log.containsKey('date') && log['date'] is String) {
              // إضافة جزء التاريخ فقط (YYYY-MM-DD) لضمان عد الأيام الفريدة
              uniqueRecordedDays.add((log['date'] as String).split('T').first);
            }
          }
          adherenceDays = uniqueRecordedDays.length;
        }

       // عرض النتائج في الواجهة
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Adherence Rate",
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[800]),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                    // عرض النسبة مع تنسيق عشري واحد
                    "${overallAdherencePercentage.toStringAsFixed(1)}%",
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                Container(
                  width: 120,
                  height: 12,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: Colors.grey[300],
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    // النسبة بين 0-100، widthFactor يتوقع قيمة بين 0.0 و 1.0
                    widthFactor: overallAdherencePercentage / 100,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              "Adherence Days: $adherenceDays", // عرض عدد أيام الالتزام
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              startDate != null
                  ? "Start Date: ${DateFormat('yyyy-MM-dd').format(startDate)}" // عرض تاريخ البدء المنسق
                  : "Start Date: N/A",
              style: const TextStyle(fontSize: 16),
            ),
          ],
        );
      }
    },
  ),
),
          SizedBox(height: 20),

                Text("Commitment Tracking",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
                SizedBox(height: 10),
                 SizedBox(height: 10),
          // --- ابدأ بإضافة الزر هنا ---
          ElevatedButton.icon(
            onPressed: _downloadIntakeLogsAsExcel, // هذا هو الاستدعاء لدالتنا
            icon: Icon(Icons.download),
            label: Text("Download Tracking as Excel"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal, // لون جميل للزر
              foregroundColor: Colors.white, // لون النص والأيقونة
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
          ),
          SizedBox(height: 20),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.indigo[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.indigo[200]!),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: Icon(Icons.arrow_back_ios, color: Colors.indigo),
                            onPressed: _previousMonth,
                          ),
                          Text(
                            DateFormat('MMMM y', 'en').format(_selectedMonth),
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.indigo),
                          ),
                          IconButton(
                            icon: Icon(Icons.arrow_forward_ios, color: Colors.indigo),
                            onPressed: _nextMonth,
                          ),
                        ],
                      ),
                      SizedBox(height: 10),
                      
                      StreamBuilder<List<Map<String, dynamic>>>(
                        stream: _fetchMedicineIntakeForMonth(_selectedMonth),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return Center(child: CircularProgressIndicator());
                          }
                          if (snapshot.hasError) {
                            return Center(
                                child: Text("Error loading tracking data: ${snapshot.error}"));
                          }
                          if (!snapshot.hasData || snapshot.data!.isEmpty) {
                            return Center(
                                child: Text("No intake information for this month.",
                                    style: TextStyle(color: Colors.grey[600])));
                          }

                          return ListView.separated(
                            shrinkWrap: true,
                            physics: NeverScrollableScrollPhysics(),
                            itemCount: snapshot.data!.length,
                            separatorBuilder: (context, index) =>
                                Divider(color: Colors.indigo[100]),
                            itemBuilder: (context, index) {
                              final intake = snapshot.data![index];
                              return Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(intake['medicineName'],
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.indigo[800])),
                                          Text(
                                            DateFormat('yyyy-MM-dd HH:mm')
                                                .format(intake['scheduledTime']),
                                            style: TextStyle(
                                                fontSize: 12, color: Colors.grey[600]),
                                          ),
                                          
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Center(
                                        child: _buildIntakeStatusIndicator(intake['taken'], intake['takenAt']),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                     
                    ],
                  ),
                ),
              ]
            ),
      ),
        ),
      ),
    );
  }
}