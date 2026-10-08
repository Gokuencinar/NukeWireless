# Alineación de marcas y créditos · dev52/app31

El selector del catálogo Bluetooth usa una columna de imagen común de 64×24 pt y alineación al inicio del botón. Los centros de Apple/Microsoft y Google/Samsung quedan en la misma columna; los nombres y subtítulos comparten el mismo inicio. El logo Samsung ampliado se conserva. Las cabeceras mantienen su tamaño y las imágenes siguen siendo plantillas para colores dinámicos. La vista de una columna para texto de accesibilidad también se conserva.

Los créditos muestran únicamente GokuEn junto al avatar y GitHub · GokuEn en el enlace. El destino real de GitHub y los identificadores de firma/paquete se mantienen. El texto del overlay de compatibilidad también se actualiza; no se presenta esto como validación funcional en otros dispositivos.

Se conservan las [acciones Wi-Fi de dev51](WIFI-SEARCH-ACTIONS-DEV51.md): tocar un resultado por IP, MAC, fabricante o nombre abre bloquear/desbloquear, cambiar/quitar nombre y copiar IP, manteniendo la búsqueda. App31 no cambia.

## Validación

Fuentes `50cb538957a609ecd6044082dc76a3aababe1786`: [Development build](https://github.com/Gokuencinar/NukeWireless/actions/runs/37820843219) aprobado, arm64/iOS16.3. Simulador: 33 comprobaciones por idioma, cuatro ciclos reales de segundo plano por idioma. Revisadas capturas claras/oscuras del selector, créditos y menú/cambio de nombre Wi-Fi. Siete pruebas de paquete aprobadas y manifiesto igual a fuentes actuales. SHA-256 `d6f3f239dcaf5baef2c853a8b38a3a735076c171828f9abeac1a4a11dbf23da8`.

Instalado por SSH .22 en el iPhone XS/iOS16.3.1 con clave conocida. Verificados dpkg dev52/app31, CFBundleVersion25.5.52, los cinco logos por bytes y CodeDirectory me.midnightchips.harpy-reloaded; no nuevos crashes relevantes en la comparación posterior, trabajador inactivo y bluetoothd running. No se repiten operaciones de radio ni bloqueo real para estos cambios de presentación.

Aceptación manual de la alineación, créditos y acciones Wi-Fi confirmada por el usuario el 8 de octubre de 2026: «esta correcto», en respuesta a la pregunta de aceptación de dev52. Esta confirmación corresponde a la interfaz y al cambio/retirada del nombre personalizado; no añade una prueba de bloqueo real o recepción de radio. Dev50 fue confirmado por el usuario el 8 de octubre; dev51 fue instalado y verificado antes de este ajuste.

Recuperación: cerrar NukeWireless e instalar /var/mobile/Documents/NukeWireless-dev51-backup.deb en el mismo entorno del jailbreak. App31 permanece instalado. Sin respring ni reinicio general.
