# Instalador único · diagnostic6+bundle2

Cada variante RootHide, Dopamine/rootless y rootful se distribuye ahora en un DEB
`com.gokuencinar.nukewireless_2.0.0~diagnostic6+bundle2_<arquitectura>.deb`.
Contiene la aplicación diagnostic6 y el componente Bluetooth diagnostic1.
Las etiquetas Debian identifican el bootstrap, no las arquitecturas del código.

El sufijo `+bundle2` identifica la revisión del instalador. La app indica
diagnostic6 y CFBundleVersion 20006; el trabajador mantiene diagnostic1.
El empaquetador conserva los binarios y permisos de sus dos DEB de entrada;
no equivale a conservar los binarios de diagnostic5. Las fuentes nativas de
esta entrega son `6f30ff2beb9d4109905b44c662de989e88ab2bf0`.

## Revisión bundle2: instalación sin límites de versión

Elimina `firmware (>= 15.0)` y `firmware (<< 19.0)` de las dependencias combinadas
del instalador, y retira `MinimumOSVersion` del Info.plist de la app. Conserva
todas las otras dependencias y los controles del transporte Bluetooth. No altera
los Mach-O, los permisos ni el código del catálogo; el postinst conserva la misma
firma con el identificador original. El mínimo compilado de los binarios sigue
siendo iOS 15.0. Instalar fuera del rango probado no demuestra que se pueda abrir
la app ni que sus funciones sean compatibles.

Se actualiza `compatibility.json` con `maximum_ios_exclusive: null` y una
`installation_policy` que identifica el alcance del cambio. La política
distingue `minimum_ios: null` de `binary_minimum_ios: "15.0"`. El manifiesto del
DEB distingue el commit/hash del empaquetador de los del código nativo y conserva
la procedencia íntegra de ambos paquetes de entrada. Sus fuentes se vuelven a
comprobar; no se modifican sus manifiestos para aceptar artefactos obsoletos.

Bundle2 validado el 10 de octubre de 2026: los tres DEB pasaron la comparación de
payload, scripts, permisos, dependencias, metadatos y procedencia en Windows
(cinco pruebas aprobadas; dos pruebas dpkg reservadas a Linux). Las fixtures de
[CI 38016603665](https://github.com/Gokuencinar/NukeWireless/actions/runs/38016603665)
pasaron seis pruebas: instalación nueva, migración desde paquetes separados,
propiedad y retirada, entre otras. La instalación sin proveedor `firmware` usa
una dependencia ficticia `ldid` de la misma arquitectura y no usa `--force-depends`.
La comparación del payload real se ejecutó localmente; CI usa solo fixtures.

Empaquetador de los DEB entregados: `4d30aad9167291bf032ced4f47bf5723dfd812ed`;
la corrección de arquitectura de la fixture se registra en `b152630` y no altera
el empaquetador ni los binarios. Instalación física de bundle2 pendiente. La
evidencia física que aparece más abajo corresponde a bundle1 en el iPhone XS
con iOS 16.3.1, no a sistemas posteriores ni anteriores a iOS 15.

## Instalación y actualización

Cerrar la app antes de instalar. Elegir un único paquete del bootstrap correcto.
Se mantienen las otras dependencias de los dos paquetes; el DEB no incluye el jailbreak,
ldid, el motor de inyección ni otras dependencias del sistema.

El paquete conserva `com.gokuencinar.nukewireless` y declara `Conflicts`, `Replaces`
y `Provides` con versión para `com.gokuencinar.nukewireless.bluetooth`.
Así el gestor transfiere los archivos del trabajador anterior al paquete único,
en lugar de dejar dos propietarios o exigir una segunda instalación. El gestor
puede mostrar la retirada del paquete auxiliar sustituido.

Las relaciones siguen las reglas de
[reemplazo de paquetes de Debian](https://www.debian.org/doc/debian-policy/ch-relationships.html#replacing-whole-packages-forcing-their-removal).

Los dos scripts postinst originales se ejecutan en subprocesos de shell con fallo
propagado; el `exit 0` de uno no puede omitir el otro. Se conservan las firmas y
permisos existentes, incluido `nwbt-run` con 4755. El prerm original de la app
conserva la limpieza PF. Bundle1 cambiaba la instrucción de desinstalación del
README del trabajador; bundle2 actualiza también el estado JSON de la política
de instalación y retira el mínimo declarado del Info.plist.

Desinstalar `com.gokuencinar.nukewireless` retira también el componente Bluetooth.
Para recuperar la distribución anterior: cerrar la app, retirar el paquete único
sin purgar los datos del usuario e instalar los dos DEB anteriores de la misma
variante. No instalar el trabajador separado junto al nuevo instalador ni hacer
respring/reinicio como procedimiento rutinario.

## Procedencia y comprobaciones

`scripts/build_unified_deb.py` recibe los dos DEB y sus manifiestos. Rechaza hashes,
fuentes, versiones y esquemas que no coincidan, conserva el payload nativo y
registra los hashes de entrada/salida en otro manifiesto. No ejecuta scripts de
mantenimiento en el equipo de compilación.

```sh
python scripts/build_unified_deb.py --inputs /ruta/diagnostic6 --output /ruta/diagnostic6-unified
python tests/test_unified_package.py --inputs /ruta/diagnostic6 --output /ruta/diagnostic6-unified
```

La prueba de entrega compara todos los archivos y sus permisos con las entradas,
los scripts, dependencias, relaciones de migración, hashes y orden del archivo.
Las pruebas de shell comprueban que se ejecutan ambos postinst y se propagan los
fallos. El workflow `Unified installer packaging` prueba dpkg en raíces Linux
temporales: instalación nueva, actualización desde los dos paquetes, propietario
de los archivos y desinstalación. Utiliza fixtures con scripts inofensivos, sin
ejecutar binarios ni scripts iOS en Linux.

Comprobaciones de entrega de las tres variantes y pruebas de shell aprobadas en
Windows. Instalación nueva, migración, propiedad y desinstalación pasaron con
fixtures Linux: [CI 38012032208](https://github.com/Gokuencinar/NukeWireless/actions/runs/38012032208).

El DEB unificado diagnostic6+bundle1 se instaló en iPhone XS / iOS 16.3.1 /
RootHide. dpkg sustituyó el paquete Bluetooth separado y el paquete principal
pasó a ser propietario de `nwbt-run`. Versiones, firma, código y permisos
verificados; diagnóstico de solo lectura sin alterar el servicio Bluetooth.
El usuario confirmó bloqueo y desbloqueo Wi-Fi en esa referencia. Es aceptación
manual, sin captura independiente del tráfico. iOS 15, 17, 18, rootless y rootful
requieren pruebas físicas.

## Dependencias del bootstrap

La app, Bluetooth Bridge, runner, inspector y ayudantes de red propios están
incluidos. Se mantienen como dependencias externas `arpoison`, `network-cmds`,
`ldid` y el proveedor de hooks del jailbreak (`ellekit` en RootHide,
`mobilesubstrate` en las otras variantes). RootHide exige también
`rootless-compat (>= 0.9)`. El gestor debe resolver sus bibliotecas transitivas.

Para el tester se recomienda abrir un solo DEB con Sileo y aceptar las
dependencias de los repositorios de su bootstrap. Fuentes oficiales:
[Procursus](https://apt.procurs.us/), [RootHide](https://roothide.github.io/) y
[ElleKit](https://ellekit.space/). RootHide emplea sus propias variantes de
Procursus. No es un paquete offline que incluya todo el bootstrap ni sustituye
el motor de inyección. El índice RootHide consultado para la referencia declara
`libnet9` y `libiosexec1` para `arpoison`; incluir solo su ejecutable no las reúne.
