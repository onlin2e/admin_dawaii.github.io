import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // Make sure this is imported for DateFormat

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage>
    with SingleTickerProviderStateMixin { // Add SingleTickerProviderStateMixin

  List<Map<String, dynamic>> patients = [];
  bool _isLoading = true;
  String? _errorMessage;

  // TabController for the main two sections
  late TabController _tabController;

  // Selected patients for each category
  List<String> selectedPatientsOther = []; // Renamed from education
  List<String> selectedPatientsExcellent = [];
  List<String> selectedPatientsModerate = [];
  List<String> selectedPatientsPoor = [];

  // Select All flags for each category
  bool selectAllOther = false; // Renamed from education
  bool selectAllExcellent = false;
  bool selectAllModerate = false;
  bool selectAllPoor = false;

  // Controllers for notification content
  TextEditingController otherNotificationController = TextEditingController(); // Renamed
  TextEditingController excellentNotificationController = TextEditingController();
  TextEditingController moderateNotificationController = TextEditingController();
  TextEditingController poorNotificationController = TextEditingController();

  // Map to hold weekly performance data for each patient.
  Map<String, double> _weeklyPerformance = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this); // 2 tabs: General, Performance
    _fetchActivePatients();
  }

  @override
  void dispose() {
    _tabController.dispose();
    otherNotificationController.dispose();
    excellentNotificationController.dispose();
    moderateNotificationController.dispose();
    poorNotificationController.dispose();
    super.dispose();
  }

  Future<void> _fetchActivePatients() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      QuerySnapshot<Map<String, dynamic>> snapshot =
          await FirebaseFirestore.instance.collection('ActivePatient').get();
      patients = snapshot.docs.map((doc) => doc.data()..['id'] = doc.id).toList();

      // Calculate weekly performance for all patients. This is key to performance
      _weeklyPerformance = await calculateWeeklyPerformance(); // Fetch performance data

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load patients: $e';
      });
    }
  }


Future<Map<String, double>> calculateWeeklyPerformance() async {
  Map<String, double> patientPerformance = {};
  DateTime today = DateTime.now();
  // Calculate start of week correctly (7 days ago, excluding today)
  DateTime startOfWeek = today.subtract(const Duration(days: 7));

  try {
    for (var patient in patients) {
      String patientId = patient['id'];
      double totalDays = 0;
      double totalPercentage = 0;
      bool hasPerformanceData = false;

      // Fetch daily performances for the specific patient.
      final dailyPerformancesSnapshot = await FirebaseFirestore.instance
          .collection('ActivePatient')
          .doc(patientId)
          .collection('DailyPerformances')
          .where('date', isGreaterThanOrEqualTo: startOfWeek)
          .where('date', isLessThan: today)
          .get();

      for (var doc in dailyPerformancesSnapshot.docs) {
        hasPerformanceData = true;
        totalDays++;
        // تم إلغاء التحويل إلى نسبة مئوية هنا، لأنها تُحفظ بالفعل كنسبة مئوية صحيحة.
        double dailyPercentage = (doc['dailyPercentage'] ?? 0.0).toDouble(); // <--- التعديل هنا!
        totalPercentage += dailyPercentage;
      }

      double weeklyPercentage =
          totalDays > 0 ? totalPercentage / totalDays : 0.0;
      if (hasPerformanceData) {
        patientPerformance[patientId] = weeklyPercentage;
      }
    }
    return patientPerformance;
  } catch (e) {
    setState(() {
      _errorMessage = 'Error fetching performance data: $e';
      _isLoading = false;
    });
    return {};
  }
}

  // دالة لتقسيم المرضى بناءً على الأداء
  Future<void> categorizePatients() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      Map<String, double> performance = await calculateWeeklyPerformance();
      if (_errorMessage != null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      _weeklyPerformance = performance;
      selectedPatientsExcellent.clear();
      selectedPatientsModerate.clear();
      selectedPatientsPoor.clear();

      // Clear "Select All" flags when categorizing
      selectAllExcellent = false;
      selectAllModerate = false;
      selectAllPoor = false;

      print("Patient Weekly Performance:");
      if (performance.isEmpty) {
        print("No patients with performance data in the last 7 days.");
      } else {
        performance.forEach((patientId, percentage) {
          final patient = patients.firstWhere((p) => p['id'] == patientId);
          print(
              "${patient['patientName']} (ID: $patientId): ${percentage.toStringAsFixed(2)}%");
        });
      }

      for (var patient in patients) {
        String patientId = patient['id'];
        double? patientPerformancePercentage = performance[patientId];
        if (patientPerformancePercentage != null) {
          if (patientPerformancePercentage >= 80) {
            selectedPatientsExcellent.add(patientId);
          } else if (patientPerformancePercentage >= 60) {
            selectedPatientsModerate.add(patientId);
          } else {
            selectedPatientsPoor.add(patientId);
          }
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to categorize patients: $e';
        _isLoading = false;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _sendNotifications(
      String category, String message, List<String> selectedIds) async {
    if (message.isEmpty || selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Please write a message and select at least one patient.')),
      );
      return;
    }

    DateTime nowUtc = DateTime.now().toUtc();

    for (String patientId in selectedIds) {
      try {
        await FirebaseFirestore.instance.collection('SentNotifications').add({
          'patientId': patientId,
          'category': category,
          'message': message,
          'sentAt': nowUtc,
        });
        print('Notification request saved for patient $patientId');
      } catch (e) {
        print('Error saving notification request for patient $patientId: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Failed to save notification request for patient $patientId: $e')),
        );
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text(
              'Notification requests saved successfully. Sending in progress.')),
    );

    // Clear selections and message after saving
    setState(() {
      if (category == 'other') { // Changed from 'education' to 'other'
        selectedPatientsOther.clear();
        selectAllOther = false;
        otherNotificationController.clear();
      } else if (category == 'excellent') {
        selectedPatientsExcellent.clear();
        selectAllExcellent = false;
        excellentNotificationController.clear();
      } else if (category == 'moderate') {
        selectedPatientsModerate.clear();
        selectAllModerate = false;
        moderateNotificationController.clear();
      } else if (category == 'poor') {
        selectedPatientsPoor.clear();
        selectAllPoor = false;
        poorNotificationController.clear();
      }
    });
  }

  void toggleSelectAll(String category) {
    setState(() {
      if (category == "other") { // Changed from 'education' to 'other'
        selectAllOther = !selectAllOther;
        selectedPatientsOther = selectAllOther
            ? patients.map((p) => p['id'] as String).toList()
            : [];
      } else if (category == "excellent") {
        selectAllExcellent = !selectAllExcellent;
        selectedPatientsExcellent = selectAllExcellent
            ? patients
                .where((p) =>
                    _weeklyPerformance[p['id']] != null &&
                    _weeklyPerformance[p['id']]! >= 75)
                .map((e) => e['id'] as String)
                .toList()
            : [];
      } else if (category == "moderate") {
        selectAllModerate = !selectAllModerate;
        selectedPatientsModerate = selectAllModerate
            ? patients
                .where((p) =>
                    _weeklyPerformance[p['id']] != null &&
                    _weeklyPerformance[p['id']]! >= 40 &&
                    _weeklyPerformance[p['id']]! < 75)
                .map((e) => e['id'] as String)
                .toList()
            : [];
      } else if (category == "poor") {
        selectAllPoor = !selectAllPoor;
        selectedPatientsPoor = selectAllPoor
            ? patients
                .where((p) =>
                    _weeklyPerformance[p['id']] != null &&
                    _weeklyPerformance[p['id']]! < 40)
                .map((e) => e['id'] as String)
                .toList()
            : [];
      }
    });
  }

  void togglePatientSelection(String patientId, String category) {
    setState(() {
      if (category == "other") { // Changed from 'education' to 'other'
        if (selectedPatientsOther.contains(patientId)) {
          selectedPatientsOther.remove(patientId);
        } else {
          selectedPatientsOther.add(patientId);
        }
      } else if (category == "excellent") {
        if (selectedPatientsExcellent.contains(patientId)) {
          selectedPatientsExcellent.remove(patientId);
        } else {
          selectedPatientsExcellent.add(patientId);
        }
      } else if (category == "moderate") {
        if (selectedPatientsModerate.contains(patientId)) {
          selectedPatientsModerate.remove(patientId);
        } else {
          selectedPatientsModerate.add(patientId);
        }
      } else if (category == "poor") {
        if (selectedPatientsPoor.contains(patientId)) {
          selectedPatientsPoor.remove(patientId);
        } else {
          selectedPatientsPoor.add(patientId);
        }
      }
    });
  }

  // This widget now serves as a reusable template for each notification section
  Widget _buildNotificationSection({
    required String title,
    required String category,
    required List<String> selectedPatients,
    required bool selectAll,
    required TextEditingController notificationController,
    required List<Map<String, dynamic>> patientListToShow, // New parameter to control which patients are displayed
  }) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: notificationController,
            decoration: const InputDecoration(
              labelText: "Write Notification Message",
              border: OutlineInputBorder(),
              alignLabelWithHint: true, // Aligns hint text to the top for multiline
            ),
            maxLines: 5,
            minLines: 3,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Select Patients:"),
              ElevatedButton(
                onPressed: () => toggleSelectAll(category),
                child: Text(selectAll ? "Deselect All" : "Select All"),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? Center(child: Text(_errorMessage!))
                  : patientListToShow.isEmpty
                      ? const Center(child: Text('No patients in this category.'))
                      : SizedBox(
                          height: 250, // Fixed height for patient list
                          child: ListView.builder(
                            itemCount: patientListToShow.length,
                            itemBuilder: (context, index) {
                              final patient = patientListToShow[index];
                              double? weeklyPercentage = _weeklyPerformance[patient['id']];
                              return CheckboxListTile(
                                title: Text(patient['patientName'] ?? 'No Name'),
                                subtitle: Text(
                                  'ID: ${patient['id']}' +
                                      (weeklyPercentage != null
                                          ? " (${weeklyPercentage.toStringAsFixed(2)}%)"
                                          : ''),
                                ),
                                value: selectedPatients.contains(patient['id']), // Check if patient is selected
                                onChanged: (bool? value) {
                                  togglePatientSelection(patient['id'], category);
                                },
                              );
                            },
                          ),
                        ),
          const SizedBox(height: 20),
          Center( // Center the send button
            child: ElevatedButton.icon(
              onPressed: () => _sendNotifications(
                category,
                notificationController.text,
                selectedPatients,
              ),
              icon: const Icon(Icons.send),
              label: const Text("Send Notification"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Send Notifications"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "General Notifications", icon: Icon(Icons.announcement)),
            Tab(text: "Weekly Performance", icon: Icon(Icons.insights)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // --- Tab 1: General Notifications (formerly "education") ---
          SingleChildScrollView(
            child: _buildNotificationSection(
              title: "Send General Notifications",
              category: "other", // Changed to "other"
              selectedPatients: selectedPatientsOther,
              selectAll: selectAllOther,
              notificationController: otherNotificationController,
              patientListToShow: patients, // Show all patients for general notifications
            ),
          ),

          // --- Tab 2: Weekly Performance Notifications ---
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await categorizePatients();
                        setState(() {}); // Force a rebuild after categorization
                      },
                      icon: _isLoading ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.category),
                      label: _isLoading
                          ? const Text("Categorizing...")
                          : const Text("Categorize Patients by Performance"),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        textStyle: const TextStyle(fontSize: 15),
                      ),
                    ),
                  ),
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 20.0),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  const SizedBox(height: 30),
                  // Nested ExpansionTiles for performance categories
                  ExpansionTile(
                    title: const Text("Excellent Performance"),
                    children: [
                      _buildNotificationSection(
                        title: "", // Title handled by ExpansionTile
                        category: "excellent",
                        selectedPatients: selectedPatientsExcellent,
                        selectAll: selectAllExcellent,
                        notificationController: excellentNotificationController,
                        patientListToShow: patients.where((p) =>
                                _weeklyPerformance[p['id']] != null &&
                                _weeklyPerformance[p['id']]! >= 75)
                            .toList(), // Filter for Excellent
                      ),
                    ],
                  ),
                  ExpansionTile(
                    title: const Text("Moderate Performance"),
                    children: [
                      _buildNotificationSection(
                        title: "",
                        category: "moderate",
                        selectedPatients: selectedPatientsModerate,
                        selectAll: selectAllModerate,
                        notificationController: moderateNotificationController,
                        patientListToShow: patients.where((p) =>
                                _weeklyPerformance[p['id']] != null &&
                                _weeklyPerformance[p['id']]! >= 40 &&
                                _weeklyPerformance[p['id']]! < 75)
                            .toList(), // Filter for Moderate
                      ),
                    ],
                  ),
                  ExpansionTile(
                    title: const Text("Poor Performance "),
                    children: [
                      _buildNotificationSection(
                        title: "",
                        category: "poor",
                        selectedPatients: selectedPatientsPoor,
                        selectAll: selectAllPoor,
                        notificationController: poorNotificationController,
                        patientListToShow: patients.where((p) =>
                                _weeklyPerformance[p['id']] != null &&
                                _weeklyPerformance[p['id']]! < 40)
                            .toList(), // Filter for Poor
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}