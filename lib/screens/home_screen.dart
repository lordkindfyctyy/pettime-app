import 'package:flutter/material.dart';

import 'lost_pets_screen.dart';
import 'pets_screen.dart';
import 'shop_screen.dart';
import 'today_screen.dart';

/// The app opens on "Hoy"; "Mascotas" has the list and the profiles;
/// "Perdidas" and "Tienda" come from sixsevenweb.com.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  /// The online tabs load when first opened, not when the app starts.
  final _opened = <int>{0};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          const TodayScreen(),
          const PetsScreen(),
          _opened.contains(2) ? const LostPetsScreen() : const SizedBox.shrink(),
          _opened.contains(3) ? const ShopScreen() : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() {
          _tab = i;
          _opened.add(i);
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Hoy',
          ),
          NavigationDestination(
            icon: Icon(Icons.pets_outlined),
            selectedIcon: Icon(Icons.pets),
            label: 'Mascotas',
          ),
          NavigationDestination(
            icon: Icon(Icons.campaign_outlined),
            selectedIcon: Icon(Icons.campaign),
            label: 'Perdidas',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Tienda',
          ),
        ],
      ),
    );
  }
}
