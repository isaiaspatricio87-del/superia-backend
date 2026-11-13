# SuperIA en Flutter

Prototipo Flutter (Dart) con interfaz inspirada en la referencia y adaptada para Android, iOS, web y escritorio. Incluye la imagen de Goku que enviaste.

## Funciones
- Chat con historial guardado en el dispositivo.
- Comandos `/hora`, `/recordar [nota]`, `/memoria`, `/limpiar` y `/ayuda`.
- Pantalla de memoria para añadir y eliminar notas.
- Ajustes para nombre, voz y endpoint del backend.
- Dictado de voz, lectura de respuestas y selección de imagen mediante plugins multiplataforma.
- Modo de demostración cuando no se ha configurado un backend.

## Ejecutar
Instala Flutter (canal estable), abre una terminal en esta carpeta y ejecuta:

```sh
flutter pub get
flutter run
```

Para navegador: `flutter run -d chrome`. Para compilar Android: `flutter build apk`. Para iOS necesitas macOS con Xcode: `flutter build ipa`.

## Backend
En Ajustes configura la URL completa del endpoint HTTP `POST /api/chat`. La app envía JSON como `{"message":"...", "memories":[...]}` y espera una respuesta JSON `{"reply":"..."}`. El backend puede estar en **Python (por ejemplo FastAPI)** o Node.js; la app Flutter está escrita en Dart. Guarda la clave privada del proveedor de IA solo en el servidor. En producción usa HTTPS y restringe el acceso.

Para el endpoint local del prototipo anterior, asegúrate de que el móvil y el servidor estén en la misma red y usa la IP local del computador, por ejemplo `http://192.168.1.20:3000/api/chat` (la dirección real depende de tu red). En Android/iOS las políticas de tráfico HTTP pueden requerir configuración para desarrollo; producción debe ser HTTPS.

## Permisos de voz e imagen
`image_picker` y `speech_to_text` usan permisos nativos. Si Flutter no los incorpora automáticamente en la plataforma creada, agrega:
- Android: permiso de micrófono `RECORD_AUDIO` en `android/app/src/main/AndroidManifest.xml`.
- iOS: `NSMicrophoneUsageDescription` y `NSSpeechRecognitionUsageDescription` en `ios/Runner/Info.plist`; añade `NSPhotoLibraryUsageDescription` para seleccionar fotos.

Para crear las carpetas de plataforma si aún no existen, ejecuta `flutter create .` desde esta carpeta antes de correr.
