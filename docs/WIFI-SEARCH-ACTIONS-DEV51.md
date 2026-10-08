# Acciones Wi-Fi desde Equipos y logo Samsung · dev51/app31

Al tocar un resultado del buscador Wi-Fi se abre un menú con Bloquear/Desbloquear equipo, Cambiar nombre del equipo, Eliminar nombre personalizado y Copiar dirección IP. Cambiar nombre establece el alias local de la app; quitarlo restaura el nombre detectado. La búsqueda por IP, MAC, fabricante o nombre conserva su texto, filtros y posición. El teclado se retira al abrir las acciones. El menú queda anclado a la fila también para popover en iPad.

El puente resuelve la copia de presentación contra el MMDevice actual por IP, MAC, generación e identidad de la red. Vuelve a comprobar estos datos al ejecutar la acción. El bloqueo no se inicia durante otro cambio o escaneo, en el equipo local, sin MAC válida o si el registro nativo de 64 procesos está lleno. Las acciones utilizan MCCommands.blockGivenIPWithIp:targetMac:/unblockIPWithIp: y el setter MMDevice.setNickName: del binario base. No se sustituye la lista SwiftUI ni se introduce otro almacén de nombres.

Las firmas se contrastaron leyendo los metadatos Objective-C del paquete base fijado; tests/test_native_abi.py pasó localmente. El setter opcional de nombre admite nil para quitarlo, contrastado en el thunk arm64 del binario. Las llamadas comprueban las firmas en runtime antes de mutar. La comprobación posterior de bloqueo usa el registro de procesos existente, con espera acotada; representa el estado nativo de la app, no una prueba de pérdida de conectividad del receptor.

El logo Samsung conserva sus trazados, recorta el margen vacío del PDF y se renderiza a 64×24 pt, frente a 24×24 anteriormente; en cabeceras, 48×18 pt. No se deforma su relación de aspecto. Mantiene los colores dinámicos y el resto de la interfaz Bluetooth ya aceptada por el usuario en dev50. App31 no cambia.

## Validación

Fuentes `03d1a2fd58b4287a0bb55a7c92a6a269ca95f93a`: [Development build](https://github.com/Gokuencinar/NukeWireless/actions/runs/37818721769) aprobado, arm64/iOS16.3. Regresión de simulador: 33 comprobaciones por idioma, cuatro ciclos reales de segundo plano por idioma. Incluye búsquedas IP/MAC/fabricante, estados del menú, alias/retirada, argumentos del equipo seleccionado para bloquear/desbloquear, rechazo de generación/MAC/red cambiadas y de equipo local. El menú se presenta realmente con UISearchController activo, conserva el filtro, permite pasar al diálogo de cambio de nombre y se captura en ambos idiomas. El backend de bloqueo de estas pruebas es una fixture sin I/O de red, incluida solo en el simulador.

Siete checks de paquete aprobados; manifiesto igual a fuentes actuales, procedencia y archivos de app31 conservados. SHA-256 de app `3506f6408afb1fbb2d703d83707625cf0d6e08898e82d549587eb7be286ea850`. Instalado por SSH .22 en iPhone XS/iOS16.3.1 con clave conocida. Verificados dpkg dev51/app31, CFBundleVersion25.5.51, cinco logos por bytes, CodeDirectory me.midnightchips.harpy-reloaded, ausencia de nuevos crashes relevantes en la comparación posterior, trabajador inactivo y bluetoothd running.

Aceptación manual de las acciones Wi-Fi y del tamaño del logo pendiente. No se presenta la fixture como una prueba de bloqueo real ni de persistencia tras reiniciar la app. Dev50 sí fue confirmado por el usuario el 8 de octubre.

Recuperación: cerrar NukeWireless e instalar /var/mobile/Documents/NukeWireless-dev50-backup.deb desde el mismo entorno del jailbreak. App31 permanece instalado. Sin respring ni reinicio general.
