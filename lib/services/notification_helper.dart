// Exporta la implementación correcta según la plataforma.
import 'notification_helper_stub.dart'
    if (dart.library.html) 'notification_helper_web.dart' as impl;

void showWebNotification(String title, String body, String iconUrl) {
  impl.showWebNotification(title, body, iconUrl);
}
