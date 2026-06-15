class UserProfile {
  String name;
  String role;
  String email;
  String phone;
  int age;
  String bloodGroup;
  List<String> healthTags;
  List<LinkedUser> linkedAccounts;
  String profileImage;

  UserProfile({
    required this.name,
    required this.role,
    required this.email,
    required this.phone,
    required this.age,
    required this.bloodGroup,
    required this.healthTags,
    required this.linkedAccounts,
    required this.profileImage,
  });
}

class LinkedUser {
  String name;
  String imagePath;

  LinkedUser({required this.name, required this.imagePath});
}
