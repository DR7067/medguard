import 'package:flutter/material.dart';
import 'medicine.dart';
import 'package:flutter_part/services/notification_service.dart';

const Color kPrimaryColor = Color(0xFF2F6FED);
const Color kPrimaryLightColor = Color(0xFF4B7BFF);
const Color kBackgroundColor = Color(0xFFF1F6FF);

class AddMedicine extends StatefulWidget {
  final Medicine? existingMedicine;

  const AddMedicine({super.key, this.existingMedicine});

  @override
  State<AddMedicine> createState() => _AddMedicineState();
}

class _AddMedicineState extends State<AddMedicine> {
  final _formKey = GlobalKey<FormState>();
  static const List<String> _medicineTypes = ['Tablet', 'Syrup'];

  late TextEditingController _nameController;
  late TextEditingController _tagController;
  late String _selectedTypeString;
  DateTime? _expiryDate;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.existingMedicine?.name ?? '',
    );
    _tagController = TextEditingController(
      text: widget.existingMedicine?.tags ?? '',
    );

    final rawType = widget.existingMedicine?.type.toString().split('.').last;
    final normalizedType = rawType == null
        ? 'Tablet'
        : rawType.isEmpty
        ? 'Tablet'
        : '${rawType[0].toUpperCase()}${rawType.substring(1).toLowerCase()}';
    _selectedTypeString = _medicineTypes.contains(normalizedType)
        ? normalizedType
        : 'Tablet';

    _expiryDate = widget.existingMedicine?.expiryDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  MedicineType _stringToEnum(String type) {
    switch (type) {
      case 'Syrup':
        return MedicineType.syrup;
      default:
        return MedicineType.tablet;
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final fontSize = width * 0.045;

    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.existingMedicine == null ? 'Add Medicine' : 'Edit Medicine',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: kPrimaryColor,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [kPrimaryColor, kPrimaryLightColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: width * 0.04, vertical: 12),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _fieldCard(
                child: TextFormField(
                  controller: _nameController,
                  style: TextStyle(fontSize: fontSize),
                  decoration: InputDecoration(
                    labelText: 'Medicine Name',
                    labelStyle: TextStyle(fontSize: fontSize * 0.9),
                    prefixIcon: Icon(
                      Icons.medical_services_outlined,
                      size: fontSize * 1.2,
                    ),
                    border: InputBorder.none,
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Enter medicine name'
                      : null,
                ),
              ),
              const SizedBox(height: 12),

              _fieldCard(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedTypeString,
                  items: _medicineTypes
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(
                            type,
                            style: TextStyle(fontSize: fontSize),
                          ),
                        ),
                      )
                      .toList(),
                  decoration: InputDecoration(
                    labelText: 'Medicine Type',
                    labelStyle: TextStyle(fontSize: fontSize * 0.9),
                    prefixIcon: Icon(
                      Icons.category_outlined,
                      size: fontSize * 1.2,
                    ),
                    border: InputBorder.none,
                  ),
                  onChanged: (val) =>
                      setState(() => _selectedTypeString = val!),
                ),
              ),
              const SizedBox(height: 12),

              _fieldCard(
                child: TextFormField(
                  readOnly: true,
                  style: TextStyle(fontSize: fontSize),
                  controller: TextEditingController(
                    text: _expiryDate != null
                        ? "${_expiryDate!.day.toString().padLeft(2, '0')}-${_expiryDate!.month.toString().padLeft(2, '0')}-${_expiryDate!.year}"
                        : '',
                  ),
                  decoration: InputDecoration(
                    labelText: 'Expiry Date',
                    labelStyle: TextStyle(fontSize: fontSize * 0.9),
                    prefixIcon: Icon(
                      Icons.calendar_today_outlined,
                      size: fontSize * 1.2,
                    ),
                    border: InputBorder.none,
                  ),
                  onTap: _pickExpiryDate,
                  validator: (value) =>
                      _expiryDate == null ? 'Select expiry date' : null,
                ),
              ),
              const SizedBox(height: 12),

              _fieldCard(
                child: TextFormField(
                  controller: _tagController,
                  style: TextStyle(fontSize: fontSize),
                  decoration: InputDecoration(
                    labelText: 'Tag / Usage',
                    hintText: 'e.g., Painkiller',
                    labelStyle: TextStyle(fontSize: fontSize * 0.9),
                    prefixIcon: Icon(Icons.label_outline, size: fontSize * 1.2),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 3,
                  ),
                  onPressed: _saveMedicine,
                  child: Text(
                    widget.existingMedicine == null
                        ? 'Add Medicine'
                        : 'Update Medicine',
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: child,
    );
  }

  Future<void> _pickExpiryDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _expiryDate = picked);
  }

  Future<void> _saveMedicine() async {
    if (_formKey.currentState!.validate()) {
      final newMedicine = Medicine(
        name: _nameController.text,
        type: _stringToEnum(_selectedTypeString),
        expiryDate: _expiryDate!,
        tags: _tagController.text,
      );

      final existing = widget.existingMedicine;
      if (existing != null) {
        await NotificationService.cancelMedicineExpiryNotifications(
          medicineName: existing.name,
          expiryDate: existing.expiryDate,
        );
      }

      await NotificationService.scheduleMedicineExpiryNotifications(
        medicineName: newMedicine.name,
        expiryDate: newMedicine.expiryDate,
      );

      if (!mounted) return;
      Navigator.pop(context, newMedicine);
    }
  }
}
