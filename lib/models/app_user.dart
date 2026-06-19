class AppUser {
  final int id;
  final String username;
  final String email;
  final String? role;
  final String? phone;
  final bool isVerified;

  AppUser({
    required this.id,
    required this.username,
    required this.email,
    this.role,
    this.phone,
    this.isVerified = false,
  });

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: (j['id'] is int) ? j['id'] : int.tryParse('${j['id']}') ?? 0,
        username: (j['username'] ?? '').toString(),
        email: (j['email'] ?? '').toString(),
        role: j['role']?.toString(),
        phone: j['phone']?.toString(),
        isVerified: j['is_verified'] == true,
      );

  String get roleLabel {
    switch (role) {
      case 'farmer':
        return 'Farmer';
      case 'retailer':
        return 'Retailer / Buyer';
      case 'specialized':
        return 'Professional';
      default:
        return 'Member';
    }
  }

  String get initials {
    final name = username.trim();
    if (name.isEmpty) return '?';
    return name.substring(0, 1).toUpperCase();
  }
}
