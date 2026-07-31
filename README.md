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
- `tools/prepare-macos-recovery-usb.sh`: crea un USB de Recovery desde Linux
  con una EFI FAT32 y Recovery HFS, siguiendo el método 2 de Dortania.
- `tools/restore-gentoo-uefi-entry.sh`: vuelve a registrar el cargador de
  Gentoo en la NVRAM UEFI después de usar **Reset NVRAM**.

### Crear un USB desde Linux

Instala las dependencias de tu distribución: `python3`, `sgdisk`, `dosfstools`
(`mkfs.vfat`) y `dmg2img` o `7z`/`7zz`. Indica siempre el disco USB completo,
nunca una de sus particiones:

```bash
sudo ./tools/prepare-macos-recovery-usb.sh --device /dev/sdX
```

El script descarga la Recovery más reciente que sigue limitada a macOS Sequoia
de forma predeterminada, crea una GPT con una partición FAT32 `OPENCORE` para la
EFI y una partición HFS que recibe la Recovery extraída desde el DMG. El
`board-id` empleado por `macrecovery` solo selecciona la Recovery; no cambia el
SMBIOS del EFI. El script verifica la cabecera HFS+ antes de declarar éxito.
Para Ventura, añade `--os ventura`. Si la imagen de Recovery ya existe, puedes
reutilizarla:

```bash
sudo ./tools/prepare-macos-recovery-usb.sh \
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

Esta EFI usa el conjunto completo de binarios DEBUG de OpenCore 1.0.8 y un
`config.plist` validado con `ocvalidate` 1.0.8. Conserva automáticamente los
registros de cada intento en el USB:

- `opencore-*.txt`: registro de OpenCore en la raíz del volumen EFI.
- `panic-*.txt`: informe de kernel panic en la raíz, cuando exista.
- `SysReport/`: informe de firmware y hardware en la raíz.

Los argumentos de arranque `-v debug=0x12a keepsyms=1 msgbuf=1048576` preservan
la salida detallada del kernel. Tras reproducir un fallo, apaga el equipo, monta
el USB en Linux y guarda esos archivos antes de otro intento. Vuelve a los
binarios RELEASE de OpenCore cuando el arranque sea estable.

La EFI usa `RebuildAppleMemoryMap=YES`, `SyncRuntimePermissions=YES` y, como
ensayo controlado, `SetupVirtualMap=NO`: el registro confirma MAT y el último
intento devolvió `EFI_ABORTED` después de `EXITBS` con el mapa virtual forzado.
La entrada **Reset NVRAM** se mantiene visible durante el diagnóstico:
ejecútala una vez después de actualizar la EFI y vuelve a arrancar macOS
Recovery.

La EFI incluye una entrada explícita al cargador systemd-boot del ESP interno,
con una ruta de dispositivo completa, además de las entradas que OpenCore
detecte automáticamente. Si se sustituye o se reparticiona el disco interno,
esa ruta debe revisarse desde el registro de OpenCore.

### Restaurar el arranque de Gentoo tras Reset NVRAM

**Reset NVRAM** borra también las entradas de arranque guardadas por el
firmware. Una vez iniciado Gentoo por cualquier vía, con su ESP montado en
`/boot/efi`, restáurala con:

```bash
sudo ./tools/restore-gentoo-uefi-entry.sh
```

El script detecta systemd-boot o GRUB de Gentoo, valida que el archivo exista y
crea una entrada `Gentoo Linux` en la NVRAM. La sitúa primero en `BootOrder` sin
modificar particiones, el ESP ni el cargador. Para un cargador en otra ruta,
indícalo explícitamente con `--loader '\EFI\gentoo\grubx64.efi'`.

Consulta la [guía de instalación de Dortania](https://dortania.github.io/OpenCore-Install-Guide/)
para comprender cada ajuste antes de modificarlo.

## English

### Purpose

This OpenCore EFI is prepared for macOS installation on an AMD laptop. It keeps
only the SSDTs, kexts, and USB map needed by this configuration. Review and test
it from a USB drive before copying it to an internal EFI partition.

### Contents

- `EFI/`: the OpenCore bootloader, ACPI tables, drivers, and kexts.
- `tools/prepare-macos-recovery-usb.sh`: creates a Recovery USB on Linux with
  a FAT32 EFI and HFS Recovery partition, following Dortania's method 2.
- `tools/restore-gentoo-uefi-entry.sh`: registers the Gentoo boot loader in
  UEFI NVRAM again after using **Reset NVRAM**.

### Create a USB installer on Linux

Install your distribution's `python3`, `sgdisk`, `dosfstools` (`mkfs.vfat`),
and `dmg2img` or `7z`/`7zz` packages. Always specify the complete USB disk,
never one of its partitions:

```bash
sudo ./tools/prepare-macos-recovery-usb.sh --device /dev/sdX
```

By default, the script downloads the newest Recovery that is still capped at
macOS Sequoia. It creates a GPT with a FAT32 `OPENCORE` partition for the EFI
and an HFS partition that receives the Recovery extracted from the DMG. The
`board-id` passed to `macrecovery` only selects the Recovery; it does not change
the EFI SMBIOS. The script verifies the HFS+ header before it reports success.
Add `--os ventura` for Ventura. Reuse an existing Recovery image when
appropriate:

```bash
sudo ./tools/prepare-macos-recovery-usb.sh \
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

This EFI uses the complete OpenCore 1.0.8 DEBUG binary set and a `config.plist`
validated with `ocvalidate` 1.0.8. It automatically keeps records from each
attempt on the USB drive:

- `opencore-*.txt`: OpenCore log at the EFI volume root.
- `panic-*.txt`: kernel-panic report at the root, when available.
- `SysReport/`: firmware and hardware report at the root.

The `-v debug=0x12a keepsyms=1 msgbuf=1048576` boot arguments retain detailed
kernel output. After reproducing a failure, shut down, mount the USB on Linux,
and save these files before another attempt. Return to OpenCore RELEASE binaries
once booting is stable.

The EFI uses `RebuildAppleMemoryMap=YES`, `SyncRuntimePermissions=YES`, and,
as a controlled test, `SetupVirtualMap=NO`: the log confirms Memory Attribute
Table (MAT) support, while the latest attempt returned `EFI_ABORTED` after
`EXITBS` with a forced virtual map. The **Reset NVRAM** entry stays visible
while debugging: run it once after updating the EFI, then boot macOS Recovery
again.

The EFI includes an explicit entry for the internal ESP's systemd-boot loader
using a full device path, in addition to entries OpenCore can discover
automatically. If the internal drive is replaced or repartitioned, review that
path in the OpenCore log.

### Restore Gentoo booting after Reset NVRAM

**Reset NVRAM** also removes the boot entries stored by the firmware. Once
Gentoo has been booted by any route and its ESP is mounted at `/boot/efi`, run:

```bash
sudo ./tools/restore-gentoo-uefi-entry.sh
```

The script detects systemd-boot or Gentoo GRUB, verifies that the loader exists,
and creates a `Gentoo Linux` NVRAM entry. It places it first in `BootOrder`
without modifying partitions, the ESP, or the loader. For a loader at another
path, state it explicitly with `--loader '\EFI\gentoo\grubx64.efi'`.

Read the [Dortania OpenCore Install Guide](https://dortania.github.io/OpenCore-Install-Guide/)
before changing settings.
