/// Textos legales de la aplicación TuCanchaFacil.
///
/// Nota: Ajusta el correo de contacto y el nombre del responsable si aplica.
const String kLegalLastUpdated = '2026-03-06';

const String kLegalContactEmail = 'javierpinzon804@gmail.com';
const String kLegalContactLocation = 'Valledupar, Cesar, Colombia';

const String kTermsAndConditionsText = '''
TÉRMINOS Y CONDICIONES – TuCanchaFacil
Última actualización: $kLegalLastUpdated

Estos Términos y Condiciones regulan el uso de la aplicación móvil TuCanchaFacil (en adelante, la “App”). Al instalar, acceder o usar la App, aceptas estos términos. Si no estás de acuerdo, por favor no uses la App.

1. ¿Qué es TuCanchaFacil?
La App permite consultar sedes/lugares, visualizar canchas y horarios disponibles, y gestionar solicitudes y reservas de canchas (según el rol del usuario y las reglas del lugar).

2. Cuenta y acceso
- Puedes necesitar una cuenta para usar ciertas funciones.
- Eres responsable de mantener la confidencialidad de tus credenciales.
- Debes proporcionar información veraz y mantenerla actualizada.
- Podemos suspender o restringir cuentas ante uso indebido, fraude o incumplimiento de estos términos.

3. Reservas, horarios y disponibilidad
- La disponibilidad depende de la configuración del lugar, reglas internas y posibles cambios por mantenimiento, clima o fuerza mayor.
- La App puede mostrar información en tiempo real; sin embargo, pueden existir variaciones temporales (por conectividad o sincronización).
- El lugar puede confirmar, reprogramar o rechazar reservas según sus políticas.

4. Pagos, precios, promociones y reembolsos
- Los precios, promociones y condiciones son definidos por cada lugar y pueden cambiar.
- Las promociones pueden tener cupos, fechas y restricciones.
- Los reembolsos/cancelaciones dependen de la política del lugar. TuCanchaFacil actúa como plataforma de gestión y comunicación, no garantiza reembolsos si el lugar no los aprueba.

5. Notificaciones
La App puede enviarte notificaciones (por ejemplo, sobre reservas, promociones o avisos administrativos). Puedes desactivarlas desde la configuración del sistema operativo, pero podrías perder información importante.

6. Uso permitido
Te comprometes a:
- No usar la App para actividades ilícitas.
- No intentar acceder a datos de otros usuarios sin autorización.
- No interferir con el funcionamiento (por ejemplo, ataques, automatizaciones abusivas, scraping, etc.).
- No suplantar identidades.

7. Contenido y propiedad intelectual
La App, su diseño, marcas y código están protegidos por leyes de propiedad intelectual. No se permite copiar, modificar, distribuir o explotar la App sin autorización.

8. Limitación de responsabilidad
En la medida permitida por la ley:
- La App se ofrece “tal cual” y “según disponibilidad”.
- No garantizamos que el servicio sea ininterrumpido o libre de errores.
- No somos responsables por decisiones del lugar (confirmación, rechazo, cambios de horario, precios, etc.) ni por pérdidas indirectas (lucro cesante, daños incidentales).

9. Cambios
Podemos actualizar estos términos. La fecha de “Última actualización” indicará la versión vigente. El uso continuado de la App implica aceptación de los cambios.

10. Contacto
Si tienes dudas sobre estos términos, contáctanos en: $kLegalContactEmail
Ubicación de operación: $kLegalContactLocation
''';

const String kPrivacyPolicyText = '''
POLÍTICA DE PRIVACIDAD – TuCanchaFacil
Última actualización: $kLegalLastUpdated

Esta Política describe cómo TuCanchaFacil recopila, usa y protege información cuando utilizas la App.

1. Información que podemos recopilar
Dependiendo de tu uso y rol (cliente, encargado, administrador), la App puede recopilar:

1.1. Datos de cuenta
- Correo electrónico y credenciales de autenticación (gestionadas mediante Firebase Authentication).
- Identificadores internos (por ejemplo, ID de usuario) para asociar reservas y permisos.

1.2. Datos de uso y operativos
- Información de dispositivo (por ejemplo, modelo/versión del sistema) para compatibilidad y soporte.
- Registros técnicos (logs) para detectar errores y mejorar estabilidad.

1.3. Notificaciones
- Token de notificaciones (FCM) para enviarte avisos de la App (reservas, promociones, auditoría según rol).

1.4. Ubicación (si otorgas permiso)
- Ubicación aproximada o precisa para funciones de mapas/ubicación de sedes o navegación, cuando corresponda.
La App solo accede a la ubicación si otorgas permisos del sistema.

1.5. Archivos e imágenes (si otorgas permiso)
- Si la App permite subir imágenes (por ejemplo, imágenes de lugares/promociones), se accederá a galería/cámara únicamente con tu autorización.

2. Cómo usamos tu información
Usamos la información para:
- Proveer funcionalidades de reservas, administración y gestión.
- Enviar notificaciones relacionadas con la operación de la App.
- Mejorar seguridad, prevenir abuso y resolver incidencias.
- Cumplir obligaciones legales aplicables.

3. Con quién compartimos información
Podemos compartir información:
- Con proveedores de infraestructura necesarios para operar la App (por ejemplo, Firebase/Google Cloud) bajo sus términos.
- Con el lugar/administración correspondiente, cuando sea necesario para gestionar una reserva o solicitud.
No vendemos tu información personal.

4. Almacenamiento y seguridad
La información se almacena principalmente en servicios de Firebase (Firestore/Storage) y se protege con reglas de seguridad y controles de acceso. Aun así, ningún sistema es 100% seguro.

5. Conservación
Conservamos la información el tiempo necesario para:
- prestar el servicio,
- cumplir obligaciones legales,
- resolver disputas,
- y hacer cumplir acuerdos.

6. Tus derechos y controles
Puedes:
- Solicitar acceso, corrección o eliminación de ciertos datos (según aplique).
- Revocar permisos (ubicación, cámara, notificaciones) desde los ajustes del dispositivo.

7. Privacidad de menores
La App no está destinada a menores de 13 años. Si crees que un menor nos proporcionó datos, contáctanos para eliminarlos.

8. Cambios a esta política
Podemos actualizar esta Política. Publicaremos la versión vigente con la fecha de actualización.

9. Contacto
Si tienes preguntas sobre esta Política, contáctanos en: $kLegalContactEmail
Ubicación de operación: $kLegalContactLocation
''';

