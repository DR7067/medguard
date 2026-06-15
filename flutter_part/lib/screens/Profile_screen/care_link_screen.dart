import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_part/services/care_context_service.dart';
import 'package:flutter_part/services/care_link_service.dart';

class CareLinkScreen extends StatefulWidget {
  const CareLinkScreen({super.key});

  @override
  State<CareLinkScreen> createState() => _CareLinkScreenState();
}

class _CareLinkScreenState extends State<CareLinkScreen> {
  static const String _databaseId = 'medguard-data';
  final FirebaseFirestore _db = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: _databaseId,
  );

  final _codeController = TextEditingController();
  final CareLinkService _linkService = CareLinkService();
  final CareContextService _contextService = CareContextService();

  String? _role;
  String? _generatedCode;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data();
    if (!mounted) return;
    setState(() {
      _role = (data?['role'] ?? '').toString();
    });
  }

  Future<void> _generateCode() async {
    setState(() => _loading = true);
    try {
      final code = await _linkService.createInviteCode();
      if (!mounted) return;
      setState(() => _generatedCode = code);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate code: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _acceptCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() => _loading = true);
    try {
      final error = await _linkService.acceptInviteCode(code);
      if (!mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
        return;
      }

      final invite = await _db.collection('invites').doc(code).get();
      final caretakerUid = invite.data()?['caretakerUid']?.toString();
      if (caretakerUid == null || caretakerUid.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid caretaker')),
        );
        return;
      }
      await _contextService.setActiveRecipientUid(caretakerUid);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Caretaker linked')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to link: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = _role?.toLowerCase();
    final isCaretaker = role == 'caretaker' || role == 'elder';
    final isCaregiver = role == 'caregiver';
    final roleLabel = isCaregiver
        ? 'guardian'
        : (isCaretaker ? 'patient' : (_role ?? 'Unknown'));

    return Scaffold(
      appBar: AppBar(title: const Text('Care Links')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Role: $roleLabel',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            const Text('Generate Code (Patient)'),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _loading || !isCaretaker ? null : _generateCode,
              child: const Text('Generate Code'),
            ),
            if (_generatedCode != null) ...[
              const SizedBox(height: 12),
              SelectableText(
                _generatedCode!,
                style: const TextStyle(fontSize: 22),
              ),
            ],
            const SizedBox(height: 30),
            const Divider(),
            const SizedBox(height: 20),
            const Text('Enter Code (Guardian)'),
            const SizedBox(height: 10),
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'ABC123',
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading || !isCaregiver ? null : _acceptCode,
              child: const Text('Link Patient'),
            ),
            if (!isCaretaker && !isCaregiver) ...[
              const SizedBox(height: 16),
              const Text(
                'Role not set. You can still use either option.',
              ),
            ],
            if (isCaretaker) ...[
              const SizedBox(height: 12),
              const Text(
                'Patients generate a code and share it with the guardian.',
                style: TextStyle(color: Colors.grey),
              ),
            ],
            if (isCaregiver) ...[
              const SizedBox(height: 12),
              const Text(
                'Guardians enter the code received from the patient.',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
