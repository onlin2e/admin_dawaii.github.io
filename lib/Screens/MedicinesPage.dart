import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'package:file_picker/file_picker.dart';

class MedicinesPage extends StatefulWidget {
  const MedicinesPage({super.key});

  @override
  State<MedicinesPage> createState() => _MedicinesPageState();
}

class _MedicinesPageState extends State<MedicinesPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final firebase_storage.FirebaseStorage _storage = firebase_storage.FirebaseStorage.instance;
  TextEditingController searchController = TextEditingController();
  TextEditingController nameController = TextEditingController();
  File? _image;
  String? _imageUrlPreview;
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  // تعريف رابط الصورة الافتراضية الثابتة.
  // **مهم:** استبدل هذا بالرابط الفعلي لصورة 'appstore.png' بعد رفعها إلى Firebase Storage.
  static const String DEFAULT_APPSTORE_IMAGE_URL = 'https://firebasestorage.googleapis.com/v0/b/med-ad.firebasestorage.app/o/medIMG%2F1.png?alt=media&token=05b69642-1304-4352-bb92-4123c6e90122'; // <--- هنا التعديل الأول

  Future<void> _getImage() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
    );

    if (result != null) {
      setState(() {
        _image = File(result.files.single.path!);
      });
    }
  }

  Future<String?> _uploadImage() async {
    if (_image == null) return null;

    String fileName = DateTime.now().millisecondsSinceEpoch.toString();
    firebase_storage.Reference ref = _storage.ref().child('images/$fileName');

    try {
      await ref.putFile(_image!);
      return await ref.getDownloadURL();
    } catch (e) {
      print('Error uploading image: $e');
      return null;
    } finally {
      setState(() {
        // بعد الرفع، قم بمسح الصورة المحلية المنتقاة
        // هذا السطر يمكن أن يسبب مشكلة إذا كنت تريد استخدام الصورة بعد الرفع مباشرة لعرضها
        // ولكن بما أننا نستخدم imageUrl من Firestore، فهو لا يمثل مشكلة
        _image = null; 
      });
    }
  }

  Future<void> addMedicine(BuildContext context) async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      String? imageUrl;
      if (_image != null) { // إذا اختار المستخدم صورة، قم برفعها
        imageUrl = await _uploadImage();
      } else { // إذا لم يختار المستخدم صورة، استخدم الصورة الافتراضية
        imageUrl = DEFAULT_APPSTORE_IMAGE_URL; // <--- هنا التعديل الثاني
      }

      await _firestore.collection('medicines').add({
        'name': nameController.text,
        'imageUrl': imageUrl ?? '', // تأكد من وجود رابط، وإلا اجعله فارغًا (مع أن الافتراضي سيضمن وجوده)
      });

      nameController.clear();
      setState(() {
        _imageUrlPreview = null;
        _isLoading = false;
        _image = null; // تأكد من مسح الصورة بعد الإضافة
      });
      Navigator.of(context).pop();
    }
  }

  Future<void> deleteMedicine(String id, BuildContext context) async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Delete'),
          content: const Text('Are you sure you want to delete this medicine?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                await _firestore.collection('medicines').doc(id).delete();
                Navigator.of(context).pop();
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  Future<void> editMedicine(String id) async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      String? imageUrl;
      if (_image != null) { // إذا اختار المستخدم صورة جديدة للتحرير، قم برفعها
        imageUrl = await _uploadImage();
      } else { // إذا لم يختار المستخدم صورة جديدة، استخدم الرابط الحالي أو الافتراضي
        // هنا يجب أن نحافظ على الصورة الموجودة مسبقًا إذا لم يتم اختيار صورة جديدة
        // أو نستخدم الافتراضية إذا لم تكن هناك صورة أصلية
        // سنفترض أنك تريد حفظ الصورة الموجودة مسبقًا إذا لم يتم تحميل صورة جديدة، 
        // أو تعيين الافتراضية إذا كانت فارغة في الأصل
        
        // لجلب الصورة الحالية من Firestore (للتأكد فقط):
        final currentMedicineDoc = await _firestore.collection('medicines').doc(id).get();
        final currentImageUrl = currentMedicineDoc.data()?['imageUrl'] as String?;

        imageUrl = currentImageUrl; // حافظ على الصورة الموجودة
        if (imageUrl == null || imageUrl.isEmpty) { // إذا لم تكن هناك صورة حالية، استخدم الافتراضية
          imageUrl = DEFAULT_APPSTORE_IMAGE_URL; // <--- هنا التعديل الثالث
        }
      }

      await _firestore.collection('medicines').doc(id).update({
        'name': nameController.text,
        'imageUrl': imageUrl ?? '',
      });
      
      nameController.clear();
      setState(() {
        _imageUrlPreview = null;
        _isLoading = false;
        _image = null; // تأكد من مسح الصورة بعد التعديل
      });
      Navigator.of(context).pop(); // إغلاق نافذة التعديل بعد الحفظ
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Manage Medicines"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      hintText: "Search...",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) {
                      setState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: () {
                    // قم بمسح الصورة والاسم عند فتح إضافة دواء جديد
                    nameController.clear();
                    _image = null;
                    showDialog(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          title: const Text('Add New Medicine'),
                          content: StatefulBuilder(
                            builder: (BuildContext context, StateSetter setDialogState) {
                              return SingleChildScrollView(
                                child: Form(
                                  key: _formKey,
                                  child: Column(
                                    children: [
                                      TextFormField(
                                        controller: nameController,
                                        decoration: const InputDecoration(labelText: 'Name'),
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'Please enter medicine name';
                                          }
                                          return null;
                                        },
                                        onChanged: (value) {
                                          setDialogState(() {});
                                        },
                                      ),
                                      const SizedBox(height: 10), // مسافة بسيطة
                                      ElevatedButton(
                                        onPressed: () async {
                                          await _getImage();
                                          setDialogState(() {});
                                        },
                                        child: const Text('Pick Image'),
                                      ),
                                      if (_image != null)
                                        Column(
                                          children: [
                                            Image.file(_image!, height: 100),
                                            TextButton(
                                              onPressed: () {
                                                showDialog(
                                                  context: context,
                                                  builder: (BuildContext context) {
                                                    return AlertDialog(
                                                      title: const Text('Confirm'),
                                                      content: const Text('Are you sure you want to remove this image?'),
                                                      actions: <Widget>[
                                                        TextButton(
                                                          onPressed: () {
                                                            Navigator.of(context).pop();
                                                          },
                                                          child: const Text('Cancel'),
                                                        ),
                                                        TextButton(
                                                          onPressed: () {
                                                            setDialogState(() {
                                                              _image = null;
                                                            });
                                                            Navigator.of(context).pop();
                                                          },
                                                          child: const Text('Remove'),
                                                        ),
                                                      ],
                                                    );
                                                  },
                                                );
                                              },
                                              child: const Text('Remove Image'),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                          actions: <Widget>[
                            StatefulBuilder(
                              builder: (BuildContext context, StateSetter setButtonState) {
                                return TextButton(
                                  onPressed: _isLoading
                                      ? null
                                      : () async {
                                            setButtonState(() {
                                              _isLoading = true;
                                            });
                                            await addMedicine(context);
                                            setButtonState(() {
                                              _isLoading = false;
                                            });
                                          },
                                  child: _isLoading
                                      ? const CircularProgressIndicator()
                                      : const Text('Add'),
                                );
                              },
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              child: const Text('Cancel'),
                            ),
                          ],
                        );
                      },
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add Medicine'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    textStyle: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore.collection('medicines').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final medicines = snapshot.data!.docs.where((doc) {
                    var data = doc.data() as Map<String, dynamic>;
                    return data['name'].toLowerCase().contains(searchController.text.toLowerCase());
                  }).toList();
                  return ListView.builder(
                    itemCount: medicines.length,
                    itemBuilder: (context, index) {
                      var medicine = medicines[index];
                      var medicineData = medicine.data() as Map<String, dynamic>;
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          children: [
                            // عرض الصورة الافتراضية إذا كان imageUrl فارغًا
                            medicineData['imageUrl'] != null && medicineData['imageUrl'].isNotEmpty
                                ? Image.network(medicineData['imageUrl'], width: double.infinity, height: 200, fit: BoxFit.contain)
                                : Image.asset('assets/1.png', width: double.infinity, height: 200, fit: BoxFit.contain), // <--- هنا التعديل الرابع في العرض
                            ListTile(
                              title: Text(medicineData['name'], textAlign: TextAlign.center),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                    onPressed: () {
                                      nameController.text = medicineData['name'];
                                      // إذا كانت هناك صورة محفوظة، قم بعرضها في المعاينة
                                      _imageUrlPreview = medicineData['imageUrl']; 
                                      _image = null; // تأكد من مسح أي صورة مختارة سابقًا قبل التحرير
                                      showDialog(
                                        context: context,
                                        builder: (context) {
                                          return AlertDialog(
                                            title: const Text('Edit Medicine'),
                                            content: StatefulBuilder(
                                              builder: (BuildContext context, StateSetter setDialogState) {
                                                return SingleChildScrollView(
                                                  child: Form(
                                                    key: _formKey,
                                                    child: Column(
                                                      children: [
                                                        TextFormField(
                                                          controller: nameController,
                                                          decoration: const InputDecoration(labelText: 'Name'),
                                                          validator: (value) {
                                                            if (value == null || value.isEmpty) {
                                                              return 'Please enter medicine name';
                                                            }
                                                            return null;
                                                          },
                                                          onChanged: (value) {
                                                            setDialogState(() {});
                                                          },
                                                        ),
                                                        const SizedBox(height: 10),
                                                        ElevatedButton(
                                                          onPressed: () async {
                                                            await _getImage();
                                                            setDialogState(() {
                                                              _imageUrlPreview = null; // مسح معاينة الرابط عند اختيار صورة جديدة
                                                            });
                                                          },
                                                          child: const Text('Pick New Image'),
                                                        ),
                                                        // عرض الصورة المختارة الجديدة أو الصورة القديمة
                                                        if (_image != null)
                                                          Column(
                                                            children: [
                                                              Image.file(_image!, height: 100),
                                                              TextButton(
                                                                onPressed: () {
                                                                  showDialog(
                                                                    context: context,
                                                                    builder: (BuildContext context) {
                                                                      return AlertDialog(
                                                                        title: const Text('Confirm'),
                                                                        content: const Text('Are you sure you want to remove this image?'),
                                                                        actions: <Widget>[
                                                                          TextButton(
                                                                            onPressed: () {
                                                                              Navigator.of(context).pop();
                                                                            },
                                                                            child: const Text('Cancel'),
                                                                          ),
                                                                          TextButton(
                                                                            onPressed: () {
                                                                              setDialogState(() {
                                                                                _image = null;
                                                                                _imageUrlPreview = null; // مسح الرابط والمعاينة
                                                                              });
                                                                              Navigator.of(context).pop();
                                                                            },
                                                                            child: const Text('Remove'),
                                                                          ),
                                                                        ],
                                                                      );
                                                                    },
                                                                  );
                                                                },
                                                                child: const Text('Remove Image'),
                                                              ),
                                                            ],
                                                          )
                                                        else if (_imageUrlPreview != null && _imageUrlPreview!.isNotEmpty)
                                                          Column(
                                                            children: [
                                                              Image.network(_imageUrlPreview!, height: 100),
                                                              TextButton(
                                                                onPressed: () {
                                                                  showDialog(
                                                                    context: context,
                                                                    builder: (BuildContext context) {
                                                                      return AlertDialog(
                                                                        title: const Text('Confirm'),
                                                                        content: const Text('Are you sure you want to remove this image?'),
                                                                        actions: <Widget>[
                                                                          TextButton(
                                                                            onPressed: () {
                                                                              Navigator.of(context).pop();
                                                                            },
                                                                            child: const Text('Cancel'),
                                                                          ),
                                                                          TextButton(
                                                                            onPressed: () {
                                                                              setDialogState(() {
                                                                                _imageUrlPreview = null; // مسح الرابط والمعاينة
                                                                              });
                                                                              Navigator.of(context).pop();
                                                                            },
                                                                            child: const Text('Remove'),
                                                                          ),
                                                                        ],
                                                                      );
                                                                    },
                                                                  );
                                                                },
                                                                child: const Text('Remove Image'),
                                                              ),
                                                            ],
                                                          )
                                                        else // إذا لم تكن هناك صورة جديدة ولا معاينة رابط، اعرض الصورة الافتراضية
                                                          Image.asset('assets/1.png', height: 100), // <--- التعديل الخامس (في نافذة التعديل)
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                            actions: <Widget>[
                                              StatefulBuilder(
                                                builder: (BuildContext context, StateSetter setButtonState) {
                                                  return TextButton(
                                                    onPressed: _isLoading
                                                        ? null
                                                        : () async {
                                                              setButtonState(() {
                                                                _isLoading = true;
                                                              });
                                                              await editMedicine(medicine.id);
                                                              setButtonState(() {
                                                                _isLoading = false;
                                                              });
                                                              Navigator.of(context).pop(); // إغلاق نافذة التعديل
                                                            },
                                                    child: _isLoading
                                                        ? const CircularProgressIndicator()
                                                        : const Text('Save'),
                                                  );
                                                },
                                              ),
                                              TextButton(
                                                onPressed: () {
                                                  Navigator.of(context).pop();
                                                },
                                                child: const Text('Cancel'),
                                              ),
                                            ],
                                          );
                                        },
                                      );
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => deleteMedicine(medicine.id, context),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}