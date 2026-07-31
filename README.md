# OpenCore EFI

[Español](#español) · [English](#english)

## Español

### Propósito

EFI de OpenCore preparada para una instalación de macOS en un portátil AMD. Se
mantienen únicamente los SSDT, kexts y el mapa USB necesarios para esta
configuración. Revísala y pruébala siempre en una memoria USB antes de copiarla
a una partición EFI interna.

### Contenido

- `EFI/`: cargador OpenCore, ACPI, controladores y kexts.
- `tools/prepare-ventura-usb.sh`: crea un USB de Recovery desde Linux siguiendo
  el método FAT32 de Dortania.

### Crear un USB desde Linux

Instala las dependencias de tu distribución: `python3`, `sgdisk` y
`dosfstools` (`mkfs.vfat`). Indica siempre el disco USB completo, nunca una de
sus particiones:

```bash
sudo ./tools/prepare-ventura-usb.sh --device /dev/sdX
```

El script descarga macOS Ventura Recovery con `macrecovery`, crea una tabla GPT
con una partición FAT32 `OPENCORE` y copia Recovery más `EFI/`. Si la imagen de
Recovery ya existe, puedes reutilizarla:

```bash
sudo ./tools/prepare-ventura-usb.sh \
  --device /dev/sdX \
  --macrecovery /ruta/a/macrecovery \
  --skip-download
```

El destino se borra por completo. Como medida de seguridad, el script solo
acepta discos USB extraíbles, rechaza discos montados y exige escribir
`ACEPTO` antes de particionar. Confirma el dispositivo con `lsblk` antes de
aceptar.

### Arranque y diagnóstico

Usa UEFI y desactiva Secure Boot. Mantén el modo verboso durante las primeras
pruebas y conserva una copia de la EFI que funcionaba antes de cualquier cambio.
Si falla el arranque, guarda una fotografía de las últimas líneas en pantalla y
valida `EFI/OC/config.plist` con la versión de `ocvalidate` que corresponda a
OpenCore.

Esta EFI usa los binarios DEBUG de OpenCore y conserva automáticamente los
registros de cada intento en el USB:

- `opencore-*.txt`: registro de OpenCore en la raíz del volumen EFI.
- `panic-*.txt`: informe de kernel panic en la raíz, cuando exista.
- `SysReport/`: informe de firmware y hardware en la raíz.

Los argumentos de arranque `-v debug=0x12a keepsyms=1 msgbuf=1048576` preservan
la salida detallada del kernel. Tras reproducir un fallo, apaga el equipo, monta
el USB en Linux y guarda esos archivos antes de otro intento. Vuelve a los
binarios RELEASE de OpenCore cuando el arranque sea estable.

Consulta la [guía de instalación de Dortania](https://dortania.github.io/OpenCore-Install-Guide/)
para comprender cada ajuste antes de modificarlo.

## English

### Purpose

This OpenCore EFI is prepared for macOS installation on an AMD laptop. It keeps
only the SSDTs, kexts, and USB map needed by this configuration. Review and test
it from a USB drive before copying it to an internal EFI partition.

### Contents

- `EFI/`: the OpenCore bootloader, ACPI tables, drivers, and kexts.
- `tools/prepare-ventura-usb.sh`: creates a Recovery USB on Linux using
  Dortania's FAT32 method.

### Create a USB installer on Linux

Install your distribution's `python3`, `sgdisk`, and `dosfstools`
(`mkfs.vfat`) packages. Always specify the complete USB disk, never one of its
partitions:

```bash
sudo ./tools/prepare-ventura-usb.sh --device /dev/sdX
```

The script downloads macOS Ventura Recovery with `macrecovery`, creates a GPT
with one FAT32 `OPENCORE` partition, then copies Recovery and `EFI/`. Reuse an
existing Recovery image when appropriate:

```bash
sudo ./tools/prepare-ventura-usb.sh \
  --device /dev/sdX \
  --macrecovery /path/to/macrecovery \
  --skip-download
```

The target drive is completely erased. As a safeguard, the script accepts only
removable USB disks, rejects mounted disks, and requires the exact word
`ACEPTO` before partitioning. Confirm the target with `lsblk` before accepting.

### Booting and troubleshooting

Use UEFI and disable Secure Boot. Keep verbose booting enabled while testing and
retain a known-good EFI backup before making changes. If booting fails, capture
the final on-screen lines and validate `EFI/OC/config.plist` with the
`ocvalidate` version that matches OpenCore.

This EFI uses OpenCore DEBUG binaries and automatically keeps records from each
attempt on the USB drive:

- `opencore-*.txt`: OpenCore log at the EFI volume root.
- `panic-*.txt`: kernel-panic report at the root, when available.
- `SysReport/`: firmware and hardware report at the root.

The `-v debug=0x12a keepsyms=1 msgbuf=1048576` boot arguments retain detailed
kernel output. After reproducing a failure, shut down, mount the USB on Linux,
and save these files before another attempt. Return to OpenCore RELEASE binaries
once booting is stable.

Read the [Dortania OpenCore Install Guide](https://dortania.github.io/OpenCore-Install-Guide/)
before changing settings.
