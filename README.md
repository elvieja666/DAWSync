# DAW Sync

App de barra de menú para macOS que sincroniza **play y stop** entre dos Macs (Logic ↔ Live, en cualquier combinación).

## Instalar

1. Bajá `DAWSync-macOS.zip` desde **Releases** y descomprimilo.
2. Mové **DAW Sync.app** a Aplicaciones.
3. La primera vez: clic derecho → **Abrir** → **Abrir** (la app no está firmada por Apple). Si macOS no te deja, andá a Configuración del Sistema → Privacidad y seguridad → **Abrir igualmente**.
4. Aceptá el permiso de **red local**.
5. Repetí en la otra Mac. Aparece un metrónomo en la barra de menú; se pone relleno cuando las dos Macs se conectan.

Las Macs se encuentran solas: por la misma red, por cable Ethernet o por WiFi directo (tipo AirDrop) si no hay red.

## Roles

- **Emisor**: tu DAW da las órdenes.
- **Receptor**: tu DAW obedece.
- **Ambos**: cualquiera de las dos puede dar play o stop.

## Configurar el DAW

La app crea dos puertos MIDI virtuales:
- **DAW → DAW Sync**: el DAW le avisa a la app cuando das play/stop (para emitir).
- **DAW Sync → DAW**: la app le da órdenes al DAW (para recibir).

### Ableton Live
- **Para emitir**: Preferencias → Link, Tempo & MIDI → en *Puertos de salida*, en **DAW → DAW Sync** activá **Sync**.
- **Para recibir**: en *Puertos de entrada*, en **DAW Sync → DAW** activá **Remote**. Entrá en modo MIDI Map (Cmd+M), hacé clic en el botón Play de Live y tocá **Probar ▶** en la app; hacé clic en Stop y tocá **Probar ■**. Salí del modo MIDI Map.

### Logic Pro
- **Para emitir**: Archivo → Ajustes del proyecto → Sincronización → MIDI → activá **Transmitir MMC** con destino **DAW → DAW Sync** (también sirve transmitir MIDI Clock a ese puerto).
- **Para recibir**, una de dos:
  - **CC (recomendado)**: Logic Pro → Superficies de control → Asignaciones de controlador → elegí la orden *Reproducir*, tocá **Aprender** y apretá **Probar ▶** en la app. Repetí con *Detener* y **Probar ■**.
  - **MMC**: en la app elegí **MMC**, y en Logic activá **Escuchar entrada MMC** en los ajustes de sincronización MIDI.

## Compilar

Cada push a `main` compila la app con GitHub Actions y la publica en Releases. Para compilar en tu Mac: `./build.sh`.
