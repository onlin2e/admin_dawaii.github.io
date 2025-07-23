import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:med_ad_admin/Screens/PatientProfile.dart';
import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';

class Patientspage extends StatefulWidget {
  const Patientspage({super.key});

  @override
  State<Patientspage> createState() => _PatientspageState();
}

class _PatientspageState extends State<Patientspage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> patients = [];
  int _currentPage = 0;
  final int _itemsPerPage = 10;
  TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredPatients = [];

  @override
  void initState() {
    super.initState();
    fetchPatients();
    _searchController.addListener(_filterPatients);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> fetchPatients() async {
    try {
      // الاستعلام بدون orderBy لتجنب مشكلة عدم وجود حقل timestamp في المستندات القديمة
      QuerySnapshot snapshot = await _firestore.collection('ActivePatient').get();

      setState(() {
        patients = snapshot.docs.map((doc) {
          // جلب الحقول، وتأكد من وجود 'timestamp' إذا كان موجودًا
          return {
            "id": doc["patientId"],
            "name": doc["patientName"],
            "phone": doc["patientPhone"],
            // هذا هو السطر الذي تم تعديله لمعالجة null-safety
            "timestamp": (doc.data() as Map<String, dynamic>?)?.containsKey('timestamp') == true
                         ? doc["timestamp"]
                         : null,
          };
        }).toList();

        // الترتيب يتم الآن في Flutter بعد جلب البيانات
        patients.sort((a, b) {
          // إذا كان كلا العنصرين لديهما 'timestamp'، قم بترتيبهما
          if (a["timestamp"] != null && b["timestamp"] != null) {
            return (a["timestamp"] as Timestamp).compareTo(b["timestamp"] as Timestamp);
          }
          // إذا كان أحدهما لا يحتوي على 'timestamp' (مثل المستندات القديمة)، لا تقم بالترتيب بناءً على الوقت
          // يمكن هنا إضافة منطق ترتيب بديل، مثلاً بالـ ID، أو تركها كما هي (ستعتمد على ترتيب Firestore الافتراضي)
          return 0; // لا تغيير في الترتيب إذا لم يكن هناك timestamp
        });

        _filteredPatients = patients; // تهيئة القائمة المفلترة
      });
    } catch (e) {
      print("Error fetching patients: $e");
    }
  }

  void _filterPatients() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredPatients = patients.where((patient) {
        // تأكد أن الحقول ليست null قبل استخدام toLowerCase
        final String patientId = patient["id"]?.toLowerCase() ?? '';
        final String patientName = patient["name"]?.toLowerCase() ?? '';
        final String patientPhone = patient["phone"]?.toLowerCase() ?? '';

        return patientName.contains(query) ||
               patientId.contains(query) ||
               patientPhone.contains(query);
      }).toList();
      _currentPage = 0; // العودة إلى الصفحة الأولى عند التصفية
    });
  }

  Future<void> _downloadExcel() async {
    var excel = Excel.createExcel();
    Sheet sheet = excel['Sheet1'];

    // Add column headers
    sheet.appendRow(["ID", "Name", "Phone"]);

    // Add patients data
    for (var patient in patients) {
      sheet.appendRow([patient["id"], patient["name"], patient["phone"]]);
    }

    var bytes = excel.save();
    final String fileName = 'patients.xlsx';
    final MimeType mimeType = MimeType.microsoftExcel;

    await FileSaver.instance.saveFile(
      name: fileName,
      bytes: Uint8List.fromList(bytes!),
      mimeType: mimeType,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('File saved as: $fileName')),
    );
  }

  void deletePatient(String patientId) async {
    try {
      await _firestore
          .collection('ActivePatient')
          .where("patientId", isEqualTo: patientId)
          .get()
          .then((snapshot) {
        for (var doc in snapshot.docs) {
          doc.reference.delete();
        }
      });

      setState(() {
        patients.removeWhere((patient) => patient["id"] == patientId);
        _filteredPatients.removeWhere((patient) => patient["id"] == patientId);
        // إعادة حساب الصفحة الحالية إذا لزم الأمر
        if (_currentPage * _itemsPerPage >= _filteredPatients.length && _currentPage > 0) {
          _currentPage--;
        }
      });
    } catch (e) {
      print("Error deleting patient: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;

    final int _totalPages = (_filteredPatients.length / _itemsPerPage).ceil();
    final int _startIndex = _currentPage * _itemsPerPage;
    final int _endIndex = (_startIndex + _itemsPerPage).clamp(0, _filteredPatients.length);
    final List<Map<String, dynamic>> _currentPatients =
        _filteredPatients.sublist(_startIndex, _endIndex);

    return Center(
      child: Container(
        padding: EdgeInsets.all(20),
        width: screenWidth * 0.8,
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: "Search Patients...",
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              SizedBox(height: screenHeight * 0.03),
              SizedBox(height: screenHeight * 0.02),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: screenWidth * 0.08,
                  dataRowColor: MaterialStateProperty.resolveWith<Color?>(
                      (Set<MaterialState> states) {
                    return states.contains(MaterialState.selected)
                        ? Colors.grey[300]
                        : null;
                  }),
                  headingRowColor:
                      MaterialStateProperty.all(Colors.blueGrey[100]),
                  border: TableBorder.all(color: Colors.grey),
                  columns: [
                    DataColumn(
                        label: Text("ID",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: screenWidth * 0.01))),
                    DataColumn(
                        label: Text("Name",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: screenWidth * 0.01))),
                    DataColumn(
                        label: Text("Phone",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: screenWidth * 0.01))),
                    DataColumn(
                        label: Text("View Profile",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: screenWidth * 0.01))),
                    DataColumn(
                        label: Text("Delete",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: screenWidth * 0.01))),
                  ],
                  rows: _currentPatients.map((patient) {
                    return DataRow(
                      color: MaterialStateProperty.all(
                          _currentPatients.indexOf(patient).isEven
                              ? Colors.grey[200]
                              : Colors.white),
                      cells: [
                        DataCell(Text(patient["id"],
                            style: TextStyle(fontSize: screenWidth * 0.01))),
                        DataCell(Text(patient["name"],
                            style: TextStyle(fontSize: screenWidth * 0.01))),
                        DataCell(Text(patient["phone"],
                            style: TextStyle(fontSize: screenWidth * 0.01))),
                        DataCell(ElevatedButton(
                            onPressed: () async {
                              // البحث عن المستند باستخدام patientId مباشرة (إذا كان هو معرّف المستند)
                              // أو باستخدام .where إذا كان patientId حقل داخل المستند
                              DocumentSnapshot patientDoc;
                              try {
                                patientDoc = await _firestore
                                    .collection('ActivePatient')
                                    .doc(patient["id"]) // افتراض أن patient["id"] هو معرف المستند
                                    .get();
                              } catch (e) {
                                // إذا لم يكن patient["id"] هو معرف المستند، حاول البحث بالحقل
                                QuerySnapshot querySnapshot = await _firestore
                                    .collection('ActivePatient')
                                    .where('patientId', isEqualTo: patient["id"])
                                    .limit(1) // نحتاج إلى مستند واحد فقط
                                    .get();
                                if (querySnapshot.docs.isNotEmpty) {
                                  patientDoc = querySnapshot.docs.first;
                                } else {
                                  // لا يوجد مستند مطابق
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Patient not found.')),
                                  );
                                  return;
                                }
                              }


                              if (patientDoc.exists) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => PatientProfile(
                                      patientId: patientDoc["patientId"],
                                      patientName: patientDoc["patientName"],
                                      patientPhone: patientDoc["patientPhone"],
                                      // إضافة البيانات الأخرى هنا إذا لزم الأمر
                                    ),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Patient data not found for profile view.')),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(
                                  horizontal: screenHeight * 0.03,
                                  vertical: screenHeight * 0.01),
                            ),
                            child: Text("View",
                                style: TextStyle(
                                    fontSize: screenWidth * 0.01)))),
                        DataCell(IconButton(
                          icon: Icon(
                            Icons.delete,
                            color: Colors.red,
                            size: screenWidth * 0.02,
                          ),
                          onPressed: () => deletePatient(patient["id"]),
                        )),
                      ],
                    );
                  }).toList(),
                ),
              ),
              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back),
                    onPressed: _currentPage > 0
                        ? () {
                            setState(() {
                              _currentPage--;
                            });
                          }
                        : null,
                  ),
                  Text('Page ${_currentPage + 1} of $_totalPages'),
                  IconButton(
                    icon: Icon(Icons.arrow_forward),
                    onPressed: _currentPage < _totalPages - 1
                        ? () {
                            setState(() {
                              _currentPage++;
                            });
                          }
                        : null,
                  ),
                ],
              ),
              SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _downloadExcel,
                icon: Icon(Icons.download),
                label: Text("Download as Excel"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}