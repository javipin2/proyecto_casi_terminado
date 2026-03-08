import 'dart:html' as html;

void imprimirHTML(String htmlContent) {
  final blob = html.Blob([htmlContent], 'text/html; charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  
  final windowFeatures = [
    'width=600',
    'height=800',
    'left=100',
    'top=50',
    'scrollbars=yes',
    'resizable=yes',
    'menubar=no',
    'toolbar=no',
    'location=no',
    'status=no',
    'directories=no',
  ].join(',');
  
  html.window.open(url, '_blank', windowFeatures);
  
  // Limpiar después de 8 segundos
  Future.delayed(Duration(seconds: 8), () {
    try {
      html.Url.revokeObjectUrl(url);
    } catch (e) {
      // Ignorar errores de limpieza
    }
  });
}