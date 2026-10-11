# Diagnóstico ampliado: diagnostic10

Estado: fuentes implementadas; compilación, paquete e instalación pendientes.
Trabajador Bluetooth sin cambios: 2.0.0~diagnostic2.

El reporte diagnostic8 del XR/iOS 18.5 registra preparación de arpoison y escaneos,
pero no confirma el inicio de los procesos, sus salidas ni recepción de tramas.
No demuestra protección ARP, IPv6 ni corte de tráfico. Probar desde otro equipo
con datos móviles apagados fue un supuesto solicitado por el desarrollador;
no sustituye la observación del tester. diagnostic9 no cambió este backend.

## Registro nuevo

- `wifi_block_preflight`: preparación; nunca prueba de lanzamiento.
- `wifi_device_action`, `wifi_bulk_action`, `wifi_bulk_item`: inicio, operación,
  índice y etiqueta anónima, estado del proceso, excepciones y resumen.
  `operation_id` y `peer_tag` tienen alcance de sesión; no son direcciones ni MAC.
- `wifi_block_process`: lanzamiento de la tarea interceptada, salida inesperada,
  duración, código de salida cuando la API está disponible y parada solicitada.
  Se observa la tarea local del lanzador; no acredita tráfico emitido o recibido.
- stderr: solo se captura cuando no existe redirección propia. Se drena sin bloquear
  la UI, conserva como máximo 4096 bytes en memoria y exporta categorías de error,
  nunca texto crudo. Se preservan lectores y handlers existentes. La captura puede
  ser incompleta; `stderr_capture` y `stderr_is_exhaustive` lo explicitan.
- Contexto de `en0`: presencia IPv6 local/no local, error de lectura y forwarding
  IPv4 conocido o desconocido. No prueba la familia usada por otro equipo.
  Protección ARP del router y recepción permanecen `unknown`.
- `important_events`: 32 errores, advertencias, interrupciones, observaciones y
  resultados de acciones conservados aunque los 64 eventos recientes roten.
  Persisten al reabrir. Cada evento nuevo incluye versión y sesión. No es un
  archivo ilimitado ni garantiza registrar todos los fallos.
- El informe expone fallos de escritura del diario. Exportar escribe de forma
  síncrona. Las interrupciones no se etiquetan como crash sin evidencia del sistema.

Se sigue al NSTask retenido y se verifica `isRunning` en el runtime, en vez de
considerar vivo un PID reciclado o zombie. Una parada que no ha terminado conserva
su registro para que la comprobación pueda fallar. No se señalan PIDs de tareas
terminadas. No se cambian tramas, cadencia, alcance del barrido, IPv6 ni permisos.

## Uso y límites

En Información → Diagnóstico, reproducir el fallo, añadir una observación de la
prueba y exportar JSON antes de borrar el diario. Sirve también para Wi-Fi y
punto de acceso. Para el XR: probar un único equipo propio con datos móviles
apagados, abrir contenido nuevo, desbloquear y comprobar recuperación.

Si el proceso está activo pero el otro equipo conserva Internet, el JSON por sí
solo no distingue un descarte del router de una ruta diferente. Se necesitan
registros del router o una captura autorizada en el receptor, junto con la prueba
de tráfico. `internet_cut_confirmed` sigue siendo `false`: no hay comprobación remota.

[Dynamic ARP Inspection, Cisco](https://www.cisco.com/c/en/us/td/docs/switches/lan/c9000/sec-crypto/fhs-sisf/fhs-and-sisf-configuration-guide/dynamic-arp-inspection.html)
documenta el descarte de asociaciones IP/MAC inválidas. Es una causa posible,
no una configuración comprobada del router del tester.
[IPv6 Neighbor Discovery, RFC 4861](https://www.rfc-editor.org/rfc/rfc4861.html)
es distinto de ARP IPv4; este backend no filtra el tráfico IPv6.

## Validación prevista

Pruebas macOS con procesos locales inofensivos: fallo de lanzamiento, salida
inesperada, stderr anonimizado, redirección existente, parada y API ausente.
Regresión de acciones Wi-Fi en simulador con `internet_cut_confirmed=false`.
Build, UI en ambos idiomas y paquetes de tres esquemas desde fuentes actuales.
Aceptación física pendiente; no se afirma corregido el corte real del XR.
