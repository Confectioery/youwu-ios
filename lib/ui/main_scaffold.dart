import 'package:flutter/material.dart';
import 'schedule/schedule_screen.dart';
import 'water/water_screen.dart';
import 'shower/shower_screen.dart';
import 'profile/profile_screen.dart';

/// 主框架：底部导航 + 页面切换
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;

  final _pages = const [
    ScheduleScreen(),
    WaterScreen(),
    ShowerScreen(),
    ProfileScreen(),
  ];

  final _items = const [
    BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: '课表'),
    BottomNavigationBarItem(icon: Icon(Icons.local_drink), label: '喝水'),
    BottomNavigationBarItem(icon: Icon(Icons.shower), label: '洗澡'),
    BottomNavigationBarItem(icon: Icon(Icons.person), label: '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calendar_today), label: '课表'),
          NavigationDestination(icon: Icon(Icons.local_drink), label: '喝水'),
          NavigationDestination(icon: Icon(Icons.shower), label: '洗澡'),
          NavigationDestination(icon: Icon(Icons.person), label: '我的'),
        ],
      ),
    );
  }
}
