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
de 96 bytes, exige coincidencia de IP e interfaz y rechaza registros truncados,
MAC inválida o identidades ambiguas. No amplía el barrido ni emite paquetes.

La prueba C cubre alineación de cuatro bytes, otra IP/interfaz, tabla truncada,
longitudes inválidas, MAC ausente y duplicados coincidentes/contradictorios.
El preflight del lanzamiento nativo se registra como `wifi_block_launch` en el
informe exportable. `captured` solo acredita identidad disponible, no el corte
real del tráfico. No cambia los permisos de la app o el ayudante.

App diagnostic6, CFBundleVersion 20006. El trabajador Bluetooth permanece en
diagnostic1. La entrega conserva un instalador único por bootstrap. Compilación,
paquete, instalación y comprobación de bloqueo/desbloqueo pendientes.

## Reporte externo recibido

iPhone XR / iOS 18.5 (22F76) / Relaxin RootHide: escaneo Wi-Fi y BLE aprobados por
el tester; bloqueo Wi-Fi no probado. El cliente Android del punto de acceso no
apareció. Emisión Bluetooth no probada: se instaló únicamente el antiguo paquete
de app, sin el trabajador. La advertencia del catálogo decía app32 aunque el
componente actual es diagnostic1. Diagnostic6 corrige ese texto; el instalador
unificado ya contiene el trabajador. Esto no acredita todavía transporte Bluetooth
ni detección de clientes del punto de acceso en el XR. Hace falta el JSON original
para investigar esos dos puntos, sin inferir compatibilidad física universal.
