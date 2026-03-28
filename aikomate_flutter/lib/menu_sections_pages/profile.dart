import 'package:flutter/material.dart';
import 'package:aikomate_flutter/core/api/delete_api.dart';
import 'package:aikomate_flutter/core/api/auth_api.dart';

class ProfileView extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onLogout;

  const ProfileView({
    super.key,
    required this.onBack,
    required this.onLogout,
  });

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  Map<String, dynamic>? user;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    loadUser();
  }

  Future<void> loadUser() async {
    final res = await auth();

    if (!mounted) return;

    if (!res.success) {
      setState(() {
        error = res.error ?? "Failed to load user";
        loading = false;
      });
      return;
    }

    setState(() {
      user = res.result;
      loading = false;
    });
  }

  Future<void> handleDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete account?"),
        content: const Text("This action cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final res = await deleteAccount();

    if (!mounted) return;

    if (!res.success) {
      setState(() => error = res.error);
      return;
    }

    widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const CircularProgressIndicator();
    }

    if (error != null) {
      return Text(error!, style: const TextStyle(color: Colors.red));
    }

    if (user == null) {
      return const Text(
        "Failed to load user",
        style: TextStyle(color: Colors.white),
      );
    }

    return Container(
      width: 320,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: widget.onBack,
              ),
              const Text("Profile", style: TextStyle(color: Colors.white)),
              const SizedBox(width: 40),
            ],
          ),

          const SizedBox(height: 16),

          Text("Name: ${user!["name"]}", style: const TextStyle(color: Colors.white)),
          Text("Email: ${user!["email"]}", style: const TextStyle(color: Colors.white)),
          Text("Credits: ${user!["credits"]}", style: const TextStyle(color: Colors.white)),

          const SizedBox(height: 20),

          ElevatedButton(
            onPressed: widget.onLogout,
            child: const Text("Logout"),
          ),

          const SizedBox(height: 10),

          ElevatedButton(
            onPressed: handleDelete,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete Account"),
          ),
        ],
      ),
    );
  }
}