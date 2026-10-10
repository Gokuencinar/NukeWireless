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
En una terminal del iPhone, entrar como root y ejecutarlo mediante `sh`, indicando
la ruta real donde se haya guardado. No usar una contraseña de otro dispositivo.

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
La prueba física del tester se registra por separado.
