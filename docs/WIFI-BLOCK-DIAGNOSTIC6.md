# diagnostic6 · identidad de la puerta de enlace Wi-Fi

El usuario informó que Bloquear ponía la mano roja brevemente, después azul, sin
cortar el acceso. Se reprodujo la presentación en diagnostic5 con los paquetes
separados en el iPhone XS / iOS 16.3.1 / RootHide. `arpoison`, `network-cmds`,
`ldid`, `rootless-compat` y ElleKit estaban instalados. No es una regresión causada
por reunir app y trabajador Bluetooth en un DEB.

El registro del intento muestra `sc-good: yes`, `sc-interface: en0`, la IP del
router y `arp-sysctl-mac: not found`, seguido de `gateway-found: no`. El ayudante
se lanzó, pero esto no demuestra que el bloqueo estuviera operativo.

El fallback local de `rt_metrics` usaba `unsigned long`, de 64 bits en arm64,
cuando la cabecera Apple fijada emplea campos de 32 bits. El parser saltaba una
cabecera incorrecta y redondeaba sockaddr a ocho bytes en lugar de cuatro.
El adaptador usa ahora la cabecera Apple ya incluida con el helper de punto de
acceso y comprueba su tamaño al compilar. `NWRouteNeighbors.h` procesa el formato
de 92 bytes, exige coincidencia de IP e interfaz y rechaza registros truncados,
MAC inválida o identidades ambiguas. No amplía el barrido ni emite paquetes.

La prueba C cubre alineación de cuatro bytes, otra IP/interfaz, tabla truncada,
longitudes inválidas, MAC ausente y duplicados coincidentes/contradictorios.
El preflight del lanzamiento nativo se registra como `wifi_block_launch` en el
informe exportable. `captured` solo acredita identidad disponible, no el corte
real del tráfico. No cambia los permisos de la app o el ayudante.

App diagnostic6, CFBundleVersion 20006. El trabajador Bluetooth permanece en
diagnostic1. La entrega conserva un instalador único por bootstrap.

## Validación y entrega

Fuentes compiladas: `6f30ff2beb9d4109905b44c662de989e88ab2bf0`.
Los trabajos [compatibilidad](https://github.com/Gokuencinar/NukeWireless/actions/runs/38011950750),
[desarrollo](https://github.com/Gokuencinar/NukeWireless/actions/runs/38011950828) e
[instalador](https://github.com/Gokuencinar/NukeWireless/actions/runs/38012032208) pasaron.
El primer intento detectó que la constante del parser era 96 en vez de 92;
se corrigieron el tamaño, las fixtures y los asserts de offsets antes de empaquetar.
Siete suites C locales, ocho comprobaciones de compatibilidad y siete del paquete
intermedio aprobadas. Simulador: 46 comprobaciones por idioma y cuatro ciclos
reales de segundo plano por idioma, con el mismo PID. Capturas del menú Bluetooth
oscuro y la hoja de acciones Wi-Fi revisadas.

Se inspeccionaron los tres DEB unificados: componentes propios, enlaces nativos,
dependencias, scripts, permisos, hashes y procedencia. El DEB RootHide
`2.0.0~diagnostic6+bundle1` se instaló en el iPhone XS / iOS 16.3.1. dpkg transfirió
el trabajador al paquete principal y dejó el auxiliar sin instalar. Firma del
ejecutable, CFBundleVersion 20006, commit e identidad del código instalado
verificados. Diagnóstico Bluetooth de solo lectura sin HCI, sin cambiar el PID
del servicio y sin nuevos crashes relevantes durante la instalación.

SHA-256 RootHide: `e9599a0197091567ea6415cbbf386591cf60218c52d22dba37ffd541d9fa56a7`.
Recuperación: cerrar la app, retirar el paquete unificado sin purgar datos e
instalar `/var/mobile/Documents/NukeWireless-diagnostic5-backup.deb` junto a
`/var/mobile/Documents/NukeWireless-diagnostic1-bluetooth-backup.deb`.
No se requiere un reinicio general por rutina. Pendientes: aceptación del corte
y restauración de tráfico Wi-Fi y verificación física en los otros entornos.

## Reporte externo recibido

iPhone XR / iOS 18.5 (22F76) / Relaxin RootHide: escaneo Wi-Fi y BLE aprobados por
el tester; bloqueo Wi-Fi no probado. El cliente Android del punto de acceso no
apareció. Emisión Bluetooth no probada: se instaló únicamente el antiguo paquete
de app, sin el trabajador. La advertencia del catálogo decía app32 aunque el
componente actual es diagnostic1. Diagnostic6 corrige ese texto; el instalador
unificado ya contiene el trabajador. Esto no acredita todavía transporte Bluetooth
ni detección de clientes del punto de acceso en el XR. Hace falta el JSON original
para investigar esos dos puntos, sin inferir compatibilidad física universal.
