import 'package:flutter/material.dart';
import 'user_models.dart';

// Colors
const Color kPrimaryColor = Color(0xFF2BB0A8);
const Color kPrimaryLightColor = Color(0xFF4ACCC9);
const Color kBackgroundColor = Color(0xFFF9FAFB);
const Color kTextColor = Color(0xFF333333);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile user = UserProfile(
    name: "Amma Sharma",
    role: "Self",
    email: "example@email.com",
    phone: "+91 9876543210",
    age: 65,
    bloodGroup: "B+",
    healthTags: [
      "Diabetes",
      "Hypertension",
      "Allergy: Pollen",
      "Vitamin D Deficiency",
    ],
    linkedAccounts: [
      LinkedUser(name: "Daughter", imagePath: "assets/images/user.png"),
      LinkedUser(name: "Son", imagePath: "assets/images/user.png"),
      LinkedUser(name: "Grandchild", imagePath: "assets/images/user.png"),
    ],
    profileImage: "assets/images/user.png",
  );

  final TextEditingController _newTagController = TextEditingController();
  final TextEditingController _newLinkedController = TextEditingController();

  @override
  void dispose() {
    _newTagController.dispose();
    _newLinkedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        elevation: 4,
        title: const Text(
          "Profile",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [kPrimaryColor, kPrimaryLightColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Profile Header
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundImage: AssetImage(user.profileImage),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: InkWell(
                        onTap: () {
                          // TODO: add profile picture picker
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.edit,
                            size: 18,
                            color: kPrimaryColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  user.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: kTextColor,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  user.role,
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 20),

              // Contact Info
              _infoCard(Icons.email, "Email", user.email),
              _infoCard(Icons.phone, "Phone", user.phone),
              _infoCard(Icons.cake, "Age", user.age.toString()),
              _infoCard(
                Icons.health_and_safety,
                "Blood Group",
                user.bloodGroup,
              ),
              const SizedBox(height: 20),

              // Health Tags
              const Text(
                "Health Information",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  ...user.healthTags.map(
                    (tag) => Chip(
                      label: Text(tag),
                      deleteIcon: const Icon(Icons.close),
                      onDeleted: () {
                        setState(() => user.healthTags.remove(tag));
                      },
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newTagController,
                      decoration: const InputDecoration(
                        hintText: "Add health tag",
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, color: kPrimaryColor),
                    onPressed: () {
                      if (_newTagController.text.trim().isNotEmpty) {
                        setState(() {
                          user.healthTags.add(_newTagController.text.trim());
                          _newTagController.clear();
                        });
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Linked Accounts
              const Text(
                "Linked Accounts",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  ...user.linkedAccounts.map(
                    (link) => Chip(
                      label: Text(link.name),
                      deleteIcon: const Icon(Icons.close),
                      onDeleted: () {
                        setState(() => user.linkedAccounts.remove(link));
                      },
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newLinkedController,
                      decoration: const InputDecoration(
                        hintText: "Add linked account",
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, color: kPrimaryColor),
                    onPressed: () {
                      if (_newLinkedController.text.trim().isNotEmpty) {
                        setState(() {
                          user.linkedAccounts.add(
                            LinkedUser(
                              name: _newLinkedController.text.trim(),
                              imagePath: "assets/images/user.png",
                            ),
                          );
                          _newLinkedController.clear();
                        });
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Action Buttons
              _actionButton("Change Password", Icons.lock, () {}),
              const SizedBox(height: 10),
              _actionButton("Medical History", Icons.description, () {}),
              const SizedBox(height: 10),
              _actionButton("Logout", Icons.logout, () {}),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoCard(IconData icon, String label, String value) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: Icon(icon, color: kPrimaryColor),
        title: Text(label),
        subtitle: Text(value),
        trailing: const Icon(Icons.edit, size: 20),
      ),
    );
  }

  Widget _actionButton(String label, IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label, style: const TextStyle(fontSize: 14)),
        style: ElevatedButton.styleFrom(
          backgroundColor: kPrimaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
        ),
      ),
    );
  }
}
