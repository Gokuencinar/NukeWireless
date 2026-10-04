# Equipos y colores — dev19 / compat2

## Uso

- En Wi-Fi, toca la lupa de la barra superior para abrir **Equipos**.
- Busca por nombre, IP, MAC o fabricante. La búsqueda ignora mayúsculas y acentos.
- Filtra **Todos / Bloqueados / Sin bloqueo**.
- En el menú de ordenación elige IP, nombre o fabricante. La IP se ordena
  numéricamente; puedes priorizar el iPhone y el router cuando están identificados.
- Toca una fila para copiar su IP y ver el aviso de copia.
- En **Información → Color de acento**, elige cian, violeta o verde. Se aplica
  al momento a los controles, bordes y cuadrícula decorados por la extensión.

Orden, filtro, prioridad y color se guardan en las preferencias de la app.
La búsqueda se conserva únicamente mientras está abierto el panel. La selección
de idioma existente traduce todos sus textos al español o inglés.

## Alcance

Equipos es una tabla UIKit que presenta una copia de los resultados del puente
Wi-Fi. No reemplaza el datasource, delegate ni las identidades de la lista SwiftUI
original. Para volver a escanear o utilizar los menús de bloqueo, cierra el panel
y usa los controles existentes de Wi-Fi. Los filtros no restringen los objetivos
de Bloquear todos: ese botón sigue usando su lista y confirmación originales.

No se añaden sondeos de red, permisos de ubicación, llamadas de bloqueo ni
temporizadores nuevos. El panel observa el estado existente y aprovecha su
temporizador para actualizar los nombres y estados almacenados. La puerta de
enlace se lee con el lector SystemConfiguration que ya usaba el puente, fuera
del hilo principal; la generación del escaneo descarta respuestas antiguas.

“Sin bloqueo” representa el estado almacenado y reconciliado por el puente.
No certifica conectividad, ni detecta una desconexión de un equipo después del
escaneo. El panel no inventa equipos locales ni routers ausentes del resultado.

Los fondos claro/oscuro y los colores de las acciones destructivas mantienen
su significado. El acento no sustituye los colores explícitos internos del binario
Swift conservado ni recolorea el logotipo de inicio.

## Paquetes y límites

**dev19 RootHide** conserva las dos bibliotecas de rutas y los auxiliares del
paquete funcional, con la extensión compilada para iOS 16.3. **compat2** incluye
la misma interfaz compilada para iOS 15 en las tres variantes experimentales
descritas en [COMPATIBILITY.md](COMPATIBILITY.md).

La compilación y el empaquetado no demuestran las interacciones nuevas en un
iPhone. Dev18 sigue siendo la versión confirmada por el usuario; el nuevo
buscador, filtros, ordenación y cambio de acento necesitan observación en el
dispositivo antes de considerarse validados. Las variantes de otros iOS y
bootstraps mantienen sus límites anteriores de validación.
