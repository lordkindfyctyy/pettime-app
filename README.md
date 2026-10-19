# PetTime

App Flutter para dueños de mascotas: agenda de medicación, visitas al veterinario y ficha de cada mascota.

## Funciones previstas

- **Ficha de la mascota:** nombre, edad, alimento, medicación que toma.
- **Medicación:** dosis cada N horas, con alarmas que nombran a la mascota ("Es hora de darle X a Luna").
- **Veterinaria:** a cuál va, próxima visita y visitas anteriores.
- **Copia de seguridad:** en Descargas o en Google Drive.
- **Paseos:** cuánto salió cada día, racha y aviso si hoy no salió.
- **Diario de salud:** síntomas, notas y fotos; va en la ficha para el veterinario.
- **Cuidador temporal:** un código para quien la cuida unos días; al terminar, la mascota sale sola de su celular.

## Estructura

```
lib/
  models/     # Pet, Medication, VetVisit
  screens/    # pantallas
  services/   # notificaciones, copia en Drive, almacenamiento
  state/      # estado (provider)
  widgets/    # componentes reutilizables
```

## Entorno de desarrollo

```
flutter pub get
flutter analyze
flutter test
flutter run            # Android / Chrome (-d chrome)
```

Paquetes: `provider`, `shared_preferences`, `flutter_local_notifications`, `timezone`,
`flutter_timezone`, `intl`, `uuid`, `google_sign_in`, `googleapis`.

La copia en Google Drive usa el proyecto de Google Cloud `pettime-511919` (Drive API, permiso drive.file).
