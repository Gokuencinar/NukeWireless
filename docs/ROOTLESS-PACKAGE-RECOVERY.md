# Error al desinstalar los DEB rootless antiguos

El mensaje `cannot remove '/var/jb/.': Invalid argument` procede de una entrada
incorrecta en la lista de archivos del paquete, no demuestra un fallo de la app.
Se ha confirmado esa entrada en los DEB rootless diagnostic5+bundle1 y
diagnostic6+bundle1/bundle2. No distribuir esos archivos.

El empaquetador de bundle3 omite la raíz `.` antes de añadir el prefijo rootless
y normaliza los componentes `.` en las rutas del tar. Los controles de fuentes,
hashes, permisos y dependencias se mantienen.

## Recuperar una instalación afectada de Dopamine

Cerrar Sileo/Zebra y NukeWireless. Copiar al iPhone el archivo
[`repair_rootless_package_list.sh`](../scripts/repair_rootless_package_list.sh).
En una terminal del iPhone, ejecutarlo con `sudo sh`, indicando la ruta real
donde se haya guardado. Si está en Documents:

```sh
sudo sh /var/mobile/Documents/repair_rootless_package_list.sh
```

Introducir la contraseña de `mobile`, configurada en Dopamine. No hace falta
entrar mediante `su`: ese comando pide la contraseña independiente de `root`.
La propia [interfaz de Dopamine 2.4.4](https://github.com/opa334/Dopamine/blob/2.4.4/Application/Dopamine/en.lproj/Localizable.strings#L75)
explica que su opción cambia `mobile` y que esa contraseña se usa con `sudo`.
Al escribirla no se muestran caracteres; es normal.

Si una copia antigua del script muestra `awk: not found`, sustituirla por la
actual y repetir el mismo comando. Esa copia se detenía antes de reemplazar
el registro original. La revisión actual filtra la línea con funciones internas
de `sh`; la prueba de recuperación utiliza un PATH sin `awk`.

El script comprueba el paquete y su versión, hace una copia de seguridad y
elimina **solo la línea exacta `/var/jb/.`** de su registro `.list`. Conserva las
demás líneas, propietario y permisos. Imprime la ruta de la copia. No borra
archivos del jailbreak ni desinstala paquetes por su cuenta. Si no encuentra la
base rootless o la versión esperada, se detiene sin modificar el registro.

Después, volver a Sileo/Zebra y repetir la desinstalación. Para instalar otra
vez, utilizar la revisión corregida de la misma variante. No borrar `/var/jb`,
la base de datos de dpkg ni el registro `.list` completo.

La opción de ruta de base de datos del script se reserva a pruebas o a una
ubicación comprobada; para Dopamine se detecta `/var/jb/var/lib/dpkg`.

## Validación

Las pruebas del instalador abarcan instalación, migración y retirada de las tres
variantes, con un archivo testigo del bootstrap que debe conservarse. Otra prueba
reproduce el fallo antiguo, comprueba la copia y el cambio de una sola línea,
repite la reparación y exige que la retirada posterior funcione. Se ejecutan en
raíces temporales Linux, con scripts ficticios que no ejecutan código iOS.
La prueba física del tester se registra por separado y sigue pendiente.
La [ejecución Linux 38059066627](https://github.com/Gokuencinar/NukeWireless/actions/runs/38059066627)
aprobó las ocho pruebas de fixtures, incluida la reproducción y recuperación.
