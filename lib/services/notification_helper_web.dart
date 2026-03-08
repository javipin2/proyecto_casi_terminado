// Implementación web: usa la API de Notification del navegador.
import 'dart:html' as html;

void showWebNotification(String title, String body, String iconUrl) {
  try {
    if (html.Notification.permission == 'granted') {
      html.Notification(title, body: body, icon: iconUrl);
    }
  } catch (_) {}
}
