import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:monitor/monitor.dart';
import 'package:monitor/src/models/api_log_entry.dart';

typedef MonitorNotificationTapHandler = void Function();

class MonitorLocalNotification {
  MonitorLocalNotification._();
  static final MonitorLocalNotification instance = MonitorLocalNotification._();

  static const String _defaultPayload = 'monitor_open';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<List<LogEntry>>? _subscription;
  Timer? _debounceTimer;
  List<LogEntry>? _pendingLogs;
  MonitorNotificationConfig _config = const MonitorNotificationConfig();
  MonitorNotificationSnapshot? _lastSnapshot;
  MonitorNotificationTapHandler? _onTap;
  bool _initialized = false;
  bool _running = false;

  bool get isInitialized => _initialized;
  bool get isRunning => _running;

  Future<void> initialize({
    MonitorNotificationConfig config = const MonitorNotificationConfig(),
    AndroidInitializationSettings? androidInitializationSettings,
    DarwinInitializationSettings? darwinInitializationSettings,
    MonitorNotificationTapHandler? onTap,
  }) async {
    _config = config;
    _onTap = onTap;

    if (!_initialized) {
      final androidSettings =
          androidInitializationSettings ??
          const AndroidInitializationSettings('@mipmap/ic_launcher');
      final darwinSettings =
          darwinInitializationSettings ??
          const DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          );

      final settings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      );

      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: _handleNotificationResponse,
      );

      _initialized = true;
    }

    await _createNotificationChannel();
  }

  Future<bool> requestPermissions({
    bool alert = true,
    bool badge = false,
    bool sound = false,
  }) async {
    _ensureInitialized();

    final iosPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final macosPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    final iosGranted =
        await iosPlugin?.requestPermissions(
          alert: alert,
          badge: badge,
          sound: sound,
        ) ??
        true;
    final macosGranted =
        await macosPlugin?.requestPermissions(
          alert: alert,
          badge: badge,
          sound: sound,
        ) ??
        true;
    final androidGranted =
        await androidPlugin?.requestNotificationsPermission() ?? true;

    return iosGranted && macosGranted && androidGranted;
  }

  Future<void> start() async {
    _ensureInitialized();
    _ensureMonitorInitialized();

    if (_running) return;
    _running = true;

    _subscription = Monitor.instance.logStream.listen(
      _scheduleUpdate,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('MonitorLocalNotification stream error: $error');
      },
    );

    _scheduleUpdate(Monitor.instance.logs);
  }

  Future<void> stop({bool clearNotification = true}) async {
    if (!_running) return;
    _running = false;

    await _subscription?.cancel();
    _subscription = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingLogs = null;

    if (clearNotification) {
      await _plugin.cancel(_config.notificationId);
    }
  }

  Future<void> dispose() async {
    await stop();
    _initialized = false;
    _lastSnapshot = null;
  }

  void updateConfig(MonitorNotificationConfig config) {
    _config = config;
    if (_running && _pendingLogs != null) {
      _scheduleUpdate(_pendingLogs!);
    }
  }

  void _scheduleUpdate(List<LogEntry> logs) {
    if (!_running) return;
    _pendingLogs = logs;

    if (_config.updateDebounce == Duration.zero) {
      _flushUpdate();
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(_config.updateDebounce, _flushUpdate);
  }

  Future<void> _flushUpdate() async {
    final logs = _pendingLogs;
    if (!_running || logs == null) return;

    final snapshot = _buildSnapshot(logs);
    if (!_shouldUpdate(snapshot)) return;

    _lastSnapshot = snapshot;
    await _showNotification(snapshot);
  }

  MonitorNotificationSnapshot _buildSnapshot(List<LogEntry> logs) {
    final stats = MonitorNotificationStats.fromLogs(logs);
    final lastEntry = logs.isNotEmpty ? logs.first : null;
    final lastSummary = _formatLastEntry(lastEntry);

    return MonitorNotificationSnapshot(
      stats: stats,
      lastEntryId: lastEntry?.id,
      lastEntrySummary: lastSummary,
      updatedAt: DateTime.now(),
    );
  }

  bool _shouldUpdate(MonitorNotificationSnapshot snapshot) {
    final last = _lastSnapshot;
    if (last == null) return true;
    if (last.stats != snapshot.stats) return true;
    if (last.lastEntryId != snapshot.lastEntryId) return true;
    return false;
  }

  Future<void> _showNotification(MonitorNotificationSnapshot snapshot) async {
    final details = _buildNotificationDetails(snapshot);
    final title = _buildTitle(snapshot.stats);
    final body = _buildBody(snapshot.stats);

    await _plugin.show(
      _config.notificationId,
      title,
      body,
      details,
      payload: _config.payload ?? _defaultPayload,
    );
  }

  NotificationDetails _buildNotificationDetails(
    MonitorNotificationSnapshot snapshot,
  ) {
    final title = _buildTitle(snapshot.stats);
    final body = _buildBody(snapshot.stats);
    final bigText = _buildBigText(snapshot);
    final updatedAt = _formatUpdatedAt(snapshot.updatedAt);

    final androidDetails = AndroidNotificationDetails(
      _config.channelId,
      _config.channelName,
      channelDescription: _config.channelDescription,
      importance: _config.importance,
      priority: _config.priority,
      ongoing: _config.ongoing,
      onlyAlertOnce: true,
      playSound: _config.playSound,
      enableVibration: _config.enableVibration,
      enableLights: _config.enableLights,
      showWhen: _config.showWhen,
      color: _config.color,
      ticker: _config.ticker,
      subText: _config.showUpdatedAt ? updatedAt : null,
      styleInformation: BigTextStyleInformation(
        bigText,
        contentTitle: title,
        summaryText: body,
      ),
    );

    final darwinDetails = DarwinNotificationDetails(
      subtitle: _config.subtitle,
      presentAlert: false,
      presentBadge: false,
      presentSound: false,
      threadIdentifier: _config.threadIdentifier,
    );

    return NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );
  }

  String _buildTitle(MonitorNotificationStats stats) {
    if (stats.total == 0) return _config.title;
    return '${_config.title} (${stats.total})';
  }

  String _buildBody(MonitorNotificationStats stats) {
    if (stats.total == 0) return 'No activity yet';

    return 'HTTP ${stats.httpTotal} | MSG ${stats.messageTotal}';
  }

  String _buildBigText(MonitorNotificationSnapshot snapshot) {
    final stats = snapshot.stats;
    final width = _maxDigits([
      stats.httpTotal,
      stats.httpSuccess,
      stats.httpError,
      stats.httpTimeout,
      stats.httpPending,
      stats.messageTotal,
      stats.messageInfo,
      stats.messageWarning,
      stats.messageError,
    ]);

    final httpLine =
        'HTTP ${_pad(stats.httpTotal, width)} | OK ${_pad(stats.httpSuccess, width)} '
        '| ERR ${_pad(stats.httpError, width)} | T/O ${_pad(stats.httpTimeout, width)} '
        '| PEND ${_pad(stats.httpPending, width)}';
    final msgLine =
        'MSG  ${_pad(stats.messageTotal, width)} | INFO ${_pad(stats.messageInfo, width)} '
        '| WARN ${_pad(stats.messageWarning, width)} | ERR ${_pad(stats.messageError, width)}';

    if (!_config.showLastEntry) {
      return '$httpLine\n$msgLine';
    }

    final lastLine = 'LAST ${snapshot.lastEntrySummary}';
    return '$httpLine\n$msgLine\n$lastLine';
  }

  String _formatLastEntry(LogEntry? entry) {
    if (entry == null) return 'No activity yet';

    final time = entry.timeText;

    if (entry is HttpLogEntry) {
      final status = entry.statusCode?.toString() ?? entry.state.label;
      final summary = '$time ${entry.method} ${entry.shortUrl} $status';
      return _truncate(summary, _config.maxLastEntryLength);
    }

    if (entry is MessageLogEntry) {
      final sanitized = entry.message.replaceAll(RegExp(r'\\s+'), ' ');
      final summary = '$time ${entry.level.label} $sanitized';
      return _truncate(summary, _config.maxLastEntryLength);
    }

    return _truncate('$time ${entry.runtimeType}', _config.maxLastEntryLength);
  }

  String _formatUpdatedAt(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  String _truncate(String input, int max) {
    if (input.length <= max) return input;
    if (max <= 3) return input.substring(0, max);
    return '${input.substring(0, max - 3)}...';
  }

  int _maxDigits(List<int> values) {
    var maxDigits = 2;
    for (final value in values) {
      final digits = value.abs().toString().length;
      if (digits > maxDigits) maxDigits = digits;
    }
    return maxDigits;
  }

  String _pad(int value, int width) {
    return value.toString().padLeft(width);
  }

  Future<void> _createNotificationChannel() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin == null) return;

    final channel = AndroidNotificationChannel(
      _config.channelId,
      _config.channelName,
      description: _config.channelDescription,
      importance: _config.importance,
    );

    await androidPlugin.createNotificationChannel(channel);
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    final expectedPayload = _config.payload ?? _defaultPayload;
    if (payload != null && payload != expectedPayload) return;
    if (_onTap != null) {
      _onTap?.call();
      return;
    }
    showMonitor();
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'MonitorLocalNotification is not initialized. '
        'Call initialize() first.',
      );
    }
  }

  void _ensureMonitorInitialized() {
    Monitor.instance;
  }
}

class MonitorNotificationConfig {
  const MonitorNotificationConfig({
    this.notificationId = 9001,
    this.title = 'Monitor Stats',
    this.subtitle = 'Live Monitor stats',
    this.channelId = 'monitor_stats',
    this.channelName = 'Monitor Stats',
    this.channelDescription = 'Live Monitor stats',
    this.payload,
    this.threadIdentifier = 'monitor_stats',
    this.updateDebounce = const Duration(milliseconds: 750),
    this.ongoing = true,
    this.showWhen = false,
    this.showUpdatedAt = true,
    this.showLastEntry = true,
    this.maxLastEntryLength = 90,
    this.playSound = false,
    this.enableVibration = false,
    this.enableLights = false,
    this.importance = Importance.low,
    this.priority = Priority.low,
    this.color = const Color(0xFF2BC3B7),
    this.ticker = 'Monitor stats',
  });

  final int notificationId;
  final String title;
  final String subtitle;
  final String channelId;
  final String channelName;
  final String channelDescription;
  final String? payload;
  final String threadIdentifier;
  final Duration updateDebounce;
  final bool ongoing;
  final bool showWhen;
  final bool showUpdatedAt;
  final bool showLastEntry;
  final int maxLastEntryLength;
  final bool playSound;
  final bool enableVibration;
  final bool enableLights;
  final Importance importance;
  final Priority priority;
  final Color color;
  final String ticker;
}

@immutable
class MonitorNotificationStats {
  const MonitorNotificationStats({
    required this.total,
    required this.httpTotal,
    required this.httpSuccess,
    required this.httpError,
    required this.httpTimeout,
    required this.httpPending,
    required this.messageTotal,
    required this.messageInfo,
    required this.messageWarning,
    required this.messageError,
  });

  factory MonitorNotificationStats.fromLogs(List<LogEntry> logs) {
    var httpTotal = 0;
    var httpSuccess = 0;
    var httpError = 0;
    var httpTimeout = 0;
    var httpPending = 0;
    var messageTotal = 0;
    var messageInfo = 0;
    var messageWarning = 0;
    var messageError = 0;

    for (final entry in logs) {
      if (entry is HttpLogEntry) {
        httpTotal += 1;
        switch (entry.state) {
          case HttpLogState.success:
            httpSuccess += 1;
          case HttpLogState.error:
            httpError += 1;
          case HttpLogState.timeout:
            httpTimeout += 1;
          case HttpLogState.pending:
            httpPending += 1;
        }
      } else if (entry is MessageLogEntry) {
        messageTotal += 1;
        switch (entry.level) {
          case MessageLevel.info:
            messageInfo += 1;
          case MessageLevel.warning:
            messageWarning += 1;
          case MessageLevel.error:
            messageError += 1;
        }
      }
    }

    return MonitorNotificationStats(
      total: logs.length,
      httpTotal: httpTotal,
      httpSuccess: httpSuccess,
      httpError: httpError,
      httpTimeout: httpTimeout,
      httpPending: httpPending,
      messageTotal: messageTotal,
      messageInfo: messageInfo,
      messageWarning: messageWarning,
      messageError: messageError,
    );
  }

  final int total;
  final int httpTotal;
  final int httpSuccess;
  final int httpError;
  final int httpTimeout;
  final int httpPending;
  final int messageTotal;
  final int messageInfo;
  final int messageWarning;
  final int messageError;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MonitorNotificationStats &&
            total == other.total &&
            httpTotal == other.httpTotal &&
            httpSuccess == other.httpSuccess &&
            httpError == other.httpError &&
            httpTimeout == other.httpTimeout &&
            httpPending == other.httpPending &&
            messageTotal == other.messageTotal &&
            messageInfo == other.messageInfo &&
            messageWarning == other.messageWarning &&
            messageError == other.messageError;
  }

  @override
  int get hashCode => Object.hash(
    total,
    httpTotal,
    httpSuccess,
    httpError,
    httpTimeout,
    httpPending,
    messageTotal,
    messageInfo,
    messageWarning,
    messageError,
  );
}

class MonitorNotificationSnapshot {
  const MonitorNotificationSnapshot({
    required this.stats,
    required this.lastEntryId,
    required this.lastEntrySummary,
    required this.updatedAt,
  });

  final MonitorNotificationStats stats;
  final String? lastEntryId;
  final String lastEntrySummary;
  final DateTime updatedAt;
}
