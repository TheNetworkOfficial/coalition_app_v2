import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  LocalNotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized) {
      return;
    }
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestSoundPermission: true,
        requestBadgePermission: false,
      ),
    );
    await _plugin.initialize(initializationSettings);
    _initialized = true;
  }

  static Future<void> showUploadReminder({
    required String title,
    required String body,
  }) async {
    await ensureInitialized();
    const android = AndroidNotificationDetails(
      'in_app_uploads',
      'In-app uploads',
      channelDescription: 'Foreground reminders for ongoing uploads.',
      importance: Importance.low,
      priority: Priority.low,
      showProgress: false,
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: false,
    );
    await _plugin.show(
      1001,
      title,
      body,
      const NotificationDetails(android: android, iOS: ios),
    );
  }
}
