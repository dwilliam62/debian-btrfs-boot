# debian-btrfs-boot 🛠️✅

Leer esto en: [English](README.md) | [Español](README.es.md)

❌🚧 VERSIÓN EN DESARROLLO — NO USE ESTE SCRIPT POR AHORA 🚧❌ Este proyecto
está en desarrollo activo. El script aún no está listo para instalaciones
reales. Úselo bajo su propio riesgo.

Autor: Don Williams

Configura un sistema Debian 12/13 (durante la instalación) para usar
subvolúmenes Btrfs para /, /home, /.snapshots, /var/log y /var/cache. Este
repositorio incluye un script robusto con comprobaciones de seguridad, salida
coloreada con iconos y registro detallado.

- Creado a partir del video de JustAGuyLinux
  https://www.youtube.com/watch?v=_zC4S7TA1GI
- por JustAGuyLinux https://www.youtube.com/@JustAGuyLinux

---

Destacados

- ✅ Seguro e idempotente: hace copia de seguridad de fstab, muestra
  previsualización de cambios y requiere confirmaciones explícitas.
- ⚠️ Barandillas: comprobaciones del entorno para el contexto del instalador de
  Debian, root, tipos de dispositivos y estado de montajes.
- 🧩 Flexible: preserva opciones clave de fstab (p. ej., ssd, noatime) mientras
  normaliza subvolúmenes y fuerza compress=zstd.
- 📜 Registros detallados: install.TIMESTAMP.log con contenidos de archivos y
  resultados de comandos.
- 🎨 UX con color: mensajes con secuencias ANSI e iconos para mayor claridad.

---

Cuándo ejecutar Ejecute este script desde la consola del instalador de Debian
después de haber particionado y formateado la unidad de destino, y cuando el
instalador haya montado el sistema de destino en /target y la partición EFI en
/target/boot/efi. Normalmente es antes del paso de instalación de paquetes.

Entorno esperado:

- Instalador de Debian 12 o 13
- Particionado GPT y firmware UEFI (/sys/firmware/efi presente)
- /cdrom existe
- /target montado como raíz Btrfs; /target/boot/efi montado como vfat

---

Diseño Btrfs resultante

- @ -> /
- @home -> /home
- @snapshots -> /.snapshots
- @log -> /var/log
- @cache -> /var/cache

---

Inicio rápido (descarga con wget) Desde la consola del instalador de Debian
(Ctrl+Alt+F2):

Primario (URL más amigable — redirección raw de GitHub)

```bash
wget -qO debian-btrfs-boot.sh https://github.com/dwilliam62/debian-btrfs-boot/raw/main/debian-btrfs-boot.sh
chmod +x debian-btrfs-boot.sh
```

Respaldo (raw.githubusercontent.com)

```bash
wget -qO debian-btrfs-boot.sh https://raw.githubusercontent.com/dwilliam62/debian-btrfs-boot/main/debian-btrfs-boot.sh
chmod +x debian-btrfs-boot.sh
```

Enlaces del script:

- Vista en repositorio:
  https://github.com/dwilliam62/debian-btrfs-boot/blob/main/debian-btrfs-boot.sh
- Archivo raw (respaldo):
  https://raw.githubusercontent.com/dwilliam62/debian-btrfs-boot/main/debian-btrfs-boot.sh

Uso

1. Desde la consola del instalador (Ctrl+Alt+F2), descargue el script con wget
   (ver arriba) en un directorio de trabajo.
2. Ejecútelo con confirmaciones (recomendado):

```bash
# Previsualización, sin cambios
./debian-btrfs-boot.sh --dry-run

# Ejecución interactiva (requiere escribir YES y luego Proceed)
./debian-btrfs-boot.sh

# No interactivo (si sabe lo que hace)
./debian-btrfs-boot.sh -y
```

Opciones:

- --dry-run Muestra lo que ocurriría sin hacer cambios
- -y, --yes Asume "YES" para proceder y "Proceed" para finalizar
- --target PATH Punto de montaje de la raíz de destino (por defecto: /target)

Registro (logging)

- Se escribe un registro detallado en install.YYYY-MM-DD_HH-MM-SS.log en el
  directorio de trabajo actual.
- Al completarse con éxito (sin dry-run), el registro se copia al directorio del
  usuario root del sistema de destino (p. ej.,
  /target/root/install.YYYY-MM-DD_HH-MM-SS.log) para revisión posterior.

---

Qué hace el script (alto nivel)

1. Comprobaciones previas (❌ aborta si falla)
   - Privilegios de root, contexto del instalador de Debian (/cdrom), /target y
     /target/boot/efi montados
   - El tipo de sistema de archivos de la raíz es btrfs; EFI es vfat
   - Existe /target/etc/fstab; se analiza para obtener especificadores de
     dispositivo y opciones
2. Confirmación (❓ escriba YES)
   - Muestra dispositivos detectados y el diseño planificado
3. Copia de seguridad de fstab (✅ copia segura en
   /target/etc/fstab.TIMESTAMP.backup)
4. Desmonta /target/boot/efi y /target (⚠️ con mensajes claros)
5. Monta el nivel superior de btrfs (subvolid=5) en /mnt
6. Renombra @rootfs -> @ si es necesario; crea @home, @snapshots, @log, @cache
   (idempotente)
7. Monta los nuevos subvolúmenes en /target
8. Vuelve a montar EFI en /target/boot/efi
9. Construye nuevas entradas de fstab
   - Preserva opciones existentes no relacionadas con subvol ni compress
   - Garantiza noatime; fuerza compress=zstd (sobrescribe otras configuraciones
     de compress)
   - Usa el mismo especificador de origen que la línea raíz original (UUID=...,
     PARTUUID=..., LABEL=..., o /dev/...)
   - Establece dump/pass en 0 0 para entradas btrfs
10. Muestra los cambios propuestos de fstab, escribe fstab.modified.TIMESTAMP
11. Confirmación final (❓ escriba Proceed) o revertir

- Si se aborta, restaura el fstab original y guarda la copia modificada como
  revertida

12. Instala el fstab modificado e indica volver al instalador (✅ éxito)

---

Revisión del plan, correcciones y barandillas

- Corrección de comandos y rutas
  - mmount -> mount
  - /target/etc/fstb -> /target/etc/fstab
  - compress=ztd -> compress=zstd
  - /var/logs -> /var/log
- Secuencia para renombrar subvolúmenes
  - Debe montarse el nivel superior de btrfs (subvolid=5) en un directorio de
    trabajo (p. ej., /mnt) antes de renombrar @rootfs a @ mediante mv
    /mnt/@rootfs /mnt/@
- Idempotencia y detección
  - Si @ ya existe, omite el renombrado
  - Crear subvolúmenes solo si faltan; no fallar si ya existen
- Manejo flexible de opciones
  - Preserva opciones existentes como ssd, noatime, autodefrag, etc., mientras
    normaliza las opciones subvol=
  - El script siempre establece compress=zstd (no preserva otros valores de
    compress)
- Campos fsck en fstab
  - Btrfs no requiere fsck; el script establece 0 0 para entradas btrfs de forma
    consistente
  - La línea de EFI se preserva tal cual
- Recuperación y seguridad
  - Copia de seguridad temprana de fstab con sello de tiempo
  - Dos confirmaciones: YES antes de desmontar; Proceed antes de aplicar
  - Modo DRY-RUN para previsualizar cambios con seguridad
  - Registra lecturas/cambios de archivos y acciones de comandos
  - Captura interrupciones con advertencia
- Comprobaciones del entorno
  - Requiere contexto del instalador de Debian (/cdrom), root, /target y
    /target/boot/efi montados, y raíz btrfs

---

Solución de problemas

- El script dice que /target no está montado
  - En el instalador, use la instalación guiada para montar el destino, o
    móntelo manualmente antes de ejecutar
- La raíz no es btrfs
  - Revise el paso de particionado; asegúrese de que la partición raíz esté
    formateada como btrfs
- EFI no es vfat
  - Asegúrese de que la partición del sistema EFI sea FAT32 y esté montada en
    /target/boot/efi
- Los subvolúmenes ya existen
  - El script es idempotente; omitirá la creación y continuará

---

Desarrollo

- Punto de entrada: ./debian-btrfs-boot.sh
- Estilo: /bin/sh (POSIX), compatible con BusyBox; salida coloreada con iconos
- Cambios y registros: install.TIMESTAMP.log en el directorio de trabajo

Licencia

- MIT — ver LICENSE
