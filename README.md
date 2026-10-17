# PetTime

App Flutter para dueños de mascotas: agenda de medicación, visitas al veterinario y ficha de cada mascota.

## Funciones previstas

- **Ficha de la mascota:** nombre, edad, alimento, medicación que toma.
- **Medicación:** dosis cada N horas, con alarmas que nombran a la mascota ("Es hora de darle X a Luna").
- **Veterinaria:** a cuál va, próxima visita y visitas anteriores.
- **Google Calendar:** sincronizar la agenda de medicación y visitas.

## Estructura

```
lib/
  models/     # Pet, Medication, VetVisit
  screens/    # pantallas
  services/   # notificaciones, Google Calendar, almacenamiento
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

Para Google Calendar hace falta crear un proyecto en Google Cloud, habilitar Calendar API y configurar el OAuth client (pendiente).
