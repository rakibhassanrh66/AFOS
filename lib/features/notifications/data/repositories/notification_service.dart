import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  static void initialize() {
    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    OneSignal.initialize('2ae8d7b3-8999-4054-b185-2256b290993c');
    OneSignal.Notifications.requestPermission(true);
  }

  static void listenToMarkPublishing(String studentId) {
    Supabase.instance.client
        .from('marks')
        .stream(primaryKey: ['id'])
        .eq('is_published', true)
        .listen((data) {
          // OneSignal logic to send targeted notification to the student
          // Note: Actual trigger for OneSignal push should be done via Edge Function
        });
  }
}
