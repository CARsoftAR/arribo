# Arribo Transit 🚌✨

**Arribo** es una aplicación de transporte público de próxima generación diseñada específicamente para el área metropolitana de Buenos Aires. Combina una estética visual **Premium** con un sistema de ruteo de alta precisión y seguimiento en tiempo real.

## 🌟 Identidad Visual: "Granito de Arroz"

La aplicación utiliza un lenguaje de diseño moderno y sofisticado:
- **Marcadores Micro**: Iconos de colectivos de perfil ultra-pequeños (20px) que no saturan el mapa.
- **Neon Glow**: Cada unidad emite un halo de neón sutil del color de su línea (159: Azul, 60: Amarillo, 129: Rojo, 148: Verde).
- **Glassmorphism**: Paneles de información con desenfoque de fondo (BackdropFilter) y transparencias elegantes.
- **Pulsing Terminals**: Marcadores de destino A y B que titilan rítmicamente con luz de neón roja.

## 🚀 Características Principales

- **📍 Geolocalización en Tiempo Real**: Centrado automático en la posición del usuario y generación dinámica de buses cercanos.
- **🛣️ Ruteo Milimétrico**: Polilíneas de neón que siguen estrictamente el trazado vial (Avenidas 14, Mitre, etc.) sin atravesar manzanas.
- **🎯 Seguimiento de Unidad**: Modo "Follow" que centra la cámara en el bus seleccionado y emite alertas de proximidad mediante vibración háptica.
- **💎 Suscripción PRO**: Gestión de favoritos con límites de uso gratuito y diálogos de Upsell integrados con Glassmorphism.
- **📊 Gestión de Datos**: Caché de marcadores optimizada para mantener 60 FPS y persistencia local con SQLite.

## 🛠️ Stack Tecnológico

- **Framework**: [Flutter](https://flutter.dev) (v3.x)
- **Mapas**: [Google Maps Flutter](https://pub.dev/packages/google_maps_flutter)
- **Ubicación**: [Geolocator](https://pub.dev/packages/geolocator)
- **Persistencia**: [sqflite](https://pub.dev/packages/sqflite)
- **UI/UX**: Custom Canvas para marcadores, Glassmorphism y Neumorfismo.

## 📦 Instalación y Configuración

1. **Clonar el repositorio**:
   ```bash
   git clone https://github.com/CARsoftAR/arribo.git
   cd arribo
   ```

2. **Configurar variables de entorno**:
   Crea un archivo `.env` en la raíz del proyecto con tus credenciales:
   ```env
   MAPS_API_KEY=tu_google_maps_key
   TRANSIT_CLIENT_ID=tu_id
   TRANSIT_SECRET=tu_secreto
   ```

3. **Configurar API Config**:
   Asegúrate de que `lib/core/config/api_config.dart` esté actualizado con las llaves correspondientes.

4. **Ejecutar el proyecto**:
   ```bash
   flutter pub get
   flutter run --release
   ```

## 📁 Estructura del Proyecto

- `lib/core`: Configuración global, temas (Dark Mode) y constantes de estilo de mapa.
- `lib/features/transit`: 
    - `data`: Servicios de transporte (Real y Mock) y persistencia de base de datos.
    - `domain`: Modelos de datos (`TransitVehicle`, `FavoriteStop`).
    - `presentation`: Pantalla principal del mapa, BottomSheets y lógica de ruteo.
- `lib/features/ui_components`: Widgets reutilizables con estética Glass y Neo.

---
Desarrollado con ❤️ por **Antigravity AI** para **CARsoftAR**.
