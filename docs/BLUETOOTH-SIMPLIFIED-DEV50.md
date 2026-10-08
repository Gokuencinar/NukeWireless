# Bluetooth simplificado y logos · dev50/app31

Bluetooth concentra las emisiones en **Dispositivos aleatorios**. Se retiran del menú los seis botones repetidos de emisión individual/triple y la consulta manual de capacidades. El escáner BLE sigue como acción independiente; el estado del trabajador se consulta internamente. El historial guardado no se borra por esta reorganización.

El catálogo muestra un selector de cuatro marcas en dos columnas con logos Apple, Google, Microsoft y Samsung; con tamaños de texto de accesibilidad pasa a una columna. Google lleva la indicación Android · Fast Pair y el logo Android en la cabecera de la selección. Los gráficos vectoriales se renderizan como plantillas, con colores dinámicos y nombres accesibles. Véase la procedencia fijada en resources/brands/README.md.

Se generan seis modelos disponibles. ▶ en una tarjeta emite solo ese modelo; **Emitir todos (6)** utiliza la selección completa. Se ocultan los IDs de protocolo de las tarjetas. Durante la operación el catálogo permanece abierto, los cambios de marca/generación se bloquean y Detener sigue accesible. Los éxitos quedan silenciosos y los errores/restauraciones incompletas siguen visibles. No cambia ningún payload, modelo, duración, permiso, firma ni código del trabajador app31.

## Android

Google/Fast Pair incluye accesorios de varias marcas y funciona en Android compatibles mediante servicios de Google; no es exclusivo de teléfonos Pixel. No garantiza avisos en todos los Android. La [ayuda oficial de Android](https://support.google.com/android/answer/16885780?hl=en) describe requisitos y ajustes de detección.

Samsung EasySetup conserva un perfil separado. La [documentación Samsung](https://www.samsung.com/ie/support/mobile-devices/how-to-connect-galaxy-buds-or-galaxy-buds-plus-to-another-device/) diferencia el popup Galaxy de la conexión con Galaxy Wearable en otras marcas. Esto documenta accesorios reales, no demuestra avisos de los anuncios de NukeWireless. No se añade un supuesto aviso universal ni un accesorio emparejable.

## Verificación

Fuentes de app `1ce466db3fd9a299337ad5543356b311b65f27cb`: [Development build](https://github.com/Gokuencinar/NukeWireless/actions/runs/37797858816) aprobado. Compilación arm64/iOS16.3 y pruebas de recursos/lógica aprobadas. Simulador: 26 comprobaciones por idioma, cuatro ciclos reales de segundo plano por idioma; selección, emisión individual/conjunta, bloqueo concurrente, cancelación, errores y final silencioso conservados. Logos cargados y revisión visual español claro/oscuro.

Siete pruebas de paquete aprobadas, incluyendo los cinco PDF y su igualdad con las fuentes. El manifiesto coincide con las fuentes actuales. SHA-256 app `b1fb2c5624abd1c27bb38a1d0d565b927896ae6c05d7486ef229bdbc0254c728`. App31 se conserva y su manifiesto de fuentes sigue coincidiendo; su compilación anterior no se presenta como una compilación nueva de dev50.

Instalado por SSH en el iPhone XS/iOS16.3.1 usando la clave conocida. Verificados dpkg dev50/app31, CFBundleVersion25.5.50, cinco logos instalados, CodeDirectory me.midnightchips.harpy-reloaded, trabajador inactivo, bluetoothd running y ausencia de nuevos crashes relevantes en la comparación posterior. Aceptación manual de la nueva UI pendiente. No se repite una prueba de radio para este cambio exclusivamente de interfaz; se conserva el informe dev49 de recepción pasiva.

Recuperación: cerrar NukeWireless e instalar /var/mobile/Documents/NukeWireless-dev49-backup.deb desde el mismo entorno del jailbreak. App31 permanece instalado. Sin respring ni reinicio general.
