# Monitor Local Notification

Monitor Local Notification is a helper package that shows a persistent local
notification with live stats from the `monitor` package. Tapping the
notification opens the Monitor viewer.

## Installation

```yaml
dependencies:
  monitor_local_notification: ^0.1.0
```

```bash
flutter pub add monitor_local_notification
```

## Usage

Initialize Monitor and register the navigator key:

```dart
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

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: Monitor.navigatorKey,
      home: const Scaffold(body: Center(child: Text('Monitor App'))),
    );
  }
}
```

### Customization

```dart
await MonitorLocalNotification.instance.initialize(
  config: const MonitorNotificationConfig(
    notificationId: 9100,
    channelId: 'monitor_stats',
    channelName: 'Monitor Stats',
    channelDescription: 'Live Monitor stats',
    updateDebounce: Duration(milliseconds: 800),
  ),
);
```

## Notes

- The persistent (ongoing) notification is supported on Android. On iOS, the
  notification is updated but may not be truly persistent due to platform
  limitations.
- The notification tap handler uses `showMonitor()`, so
  `Monitor.navigatorKey` must be set on your `MaterialApp`.
- This package depends on `flutter_local_notifications` ^18.0.1.

## License

Apache-2.0. See `LICENSE` for details.
