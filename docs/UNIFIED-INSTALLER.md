# Instalador único · diagnostic5+bundle1

Cada variante RootHide, Dopamine/rootless y rootful se distribuye ahora en un DEB
`com.gokuencinar.nukewireless_2.0.0~diagnostic5+bundle1_<arquitectura>.deb`.
Contiene la aplicación diagnostic5 y el componente Bluetooth diagnostic1.
Las etiquetas Debian identifican el bootstrap, no las arquitecturas del código.

El sufijo `+bundle1` cambia la revisión del instalador para que pueda actualizar
diagnostic5. La app sigue indicando diagnostic5 y su CFBundleVersion 20005;
el trabajador mantiene diagnostic1. No se han recompilado ni modificado los
binarios, entitlements, identidad de firma, rutas, interfaz o funciones.
Las fuentes nativas de la app son `4f2f7c76ce2c570e882ca0cb6a5e9d5bbaea59ac`.

## Instalación y actualización

Cerrar la app antes de instalar. Elegir un único paquete del bootstrap correcto.
Se mantienen las dependencias de los dos paquetes; el DEB no incluye el jailbreak,
ldid, el motor de inyección ni otras dependencias del sistema.

El paquete conserva `com.gokuencinar.nukewireless` y declara `Conflicts`, `Replaces`
y `Provides` con versión para `com.gokuencinar.nukewireless.bluetooth`.
Así el gestor transfiere los archivos del trabajador anterior al paquete único,
en lugar de dejar dos propietarios o exigir una segunda instalación. El gestor
puede mostrar la retirada del paquete auxiliar sustituido.

Los dos scripts postinst originales se ejecutan en subprocesos de shell con fallo
propagado; el `exit 0` de uno no puede omitir el otro. Se conservan las firmas y
permisos existentes, incluido `nwbt-run` con 4755. El prerm original de la app
conserva la limpieza PF. La única modificación de un archivo de datos existente
es la instrucción de desinstalación del README del trabajador.

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
python scripts/build_unified_deb.py --inputs /ruta/diagnostic5 --output /ruta/diagnostic5-unified
python tests/test_unified_package.py --inputs /ruta/diagnostic5 --output /ruta/diagnostic5-unified
```

La prueba de entrega compara todos los archivos y sus permisos con las entradas,
los scripts, dependencias, relaciones de migración, hashes y orden del archivo.
Las pruebas de shell comprueban que se ejecutan ambos postinst y se propagan los
fallos. El workflow `Unified installer packaging` prueba dpkg en raíces Linux
temporales: instalación nueva, actualización desde los dos paquetes, propietario
de los archivos y desinstalación. Utiliza fixtures con scripts inofensivos, sin
ejecutar binarios ni scripts iOS en Linux.

La inspección del paquete y la migración simulada no equivalen a instalación
verificada en iPhone. La instalación física del formato unificado está pendiente.
Las evidencias físicas de diagnostic5 corresponden al formato anterior en
iPhone XS / iOS 16.3.1 / RootHide. iOS 15, 17, 18, rootless y rootful requieren
pruebas en los dispositivos de los testers.
