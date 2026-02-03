import 'package:flutter/material.dart';

import 'package:monitor/monitor.dart';
import 'package:monitor_local_notification/monitor_local_notification.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Monitor.navigatorKey = GlobalKey<NavigatorState>();
  Monitor.init();

  await MonitorLocalNotification.instance.initialize();
  await MonitorLocalNotification.instance.requestPermissions();
  await MonitorLocalNotification.instance.start();

  runApp(const _ExampleApp());
}

class _ExampleApp extends StatelessWidget {
  const _ExampleApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: Monitor.navigatorKey,
      home: const _HomePage(),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitor Local Notification'),
        actions: const [
          IconButton(
            icon: Icon(Icons.bug_report_outlined),
            onPressed: showMonitor,
          ),
        ],
      ),
      body: Center(
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ElevatedButton(
              onPressed: () => Monitor.info('Sample info log'),
              child: const Text('Log Info'),
            ),
            ElevatedButton(
              onPressed: () => Monitor.warning('Sample warning log'),
              child: const Text('Log Warning'),
            ),
            ElevatedButton(
              onPressed: () => Monitor.error('Sample error log'),
              child: const Text('Log Error'),
            ),
          ],
        ),
      ),
    );
  }
}
