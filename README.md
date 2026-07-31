# OpenCore Tahoe bootstrap EFI

[Español](#español) · [English](#english)

## Español

### Estado y alcance

Este repositorio contiene una EFI de diagnóstico reconstruida para iniciar
**macOS Tahoe 26.x Recovery** en un portátil AMD Renoir. Es una configuración
mínima de primera etapa: todavía debe confirmarse en el equipo real antes de
considerarla estable o copiarla al disco interno.

Dortania no ofrece soporte oficial para CPU AMD de portátil. La base OpenCore y
los ajustes generales siguen su guía, mientras que el soporte de la iGPU Renoir
depende de NootedRed y de parches comunitarios. No existe una configuración que
pueda garantizar un arranque sin pruebas físicas.

No se almacenan en la documentación números de serie, UUID, direcciones ROM ni
rutas personales. La identidad SMBIOS del archivo `config.plist` no debe
publicarse en capturas o reportes.

### Perfil mínimo de arranque

La EFI se reconstruyó desde el `Sample.plist` y los binarios DEBUG de OpenCore
1.0.8 correspondientes a la misma compilación. Incluye únicamente:

- ACPI: `SSDT-EC`, `SSDT-RTCAWAC`, `SSDT-USB-Reset` y `SSDT-USBX`.
- Kexts: Lilu, NootedRed, VirtualSMC, AppleMCEReporterDisabler,
  ForgedInvariant, GenericUSBXHCI, USBToolBox, el mapa USB y el teclado PS/2.
- Drivers: `apfs_aligned.efi`, `HfsPlus.efi` y `OpenRuntime.efi`.
- 27 parches AMD compatibles con Darwin 25, ajustados a seis núcleos.
- SMBIOS `MacBookPro16,2`, compatible con Tahoe.
- Registro persistente de OpenCore y reporte de hardware en la memoria USB.
- Una entrada explícita para el cargador EFI de Gentoo.

Para Tahoe, `UEFI -> APFS -> EnableJumpstart` está desactivado y se carga
`apfs_aligned.efi`. Los argumentos iniciales son:

```text
-v debug=0x100 keepsyms=1
```

La entrada Reset NVRAM se retiró de esta etapa. Al usarla se eliminaban también
`BootOrder` y la entrada UEFI de Gentoo, sin corregir el fallo de macOS.

### Crear el USB Tahoe desde Linux

Instala `python3`, `sgdisk`, `dosfstools` (`mkfs.vfat`) y `7z` o `7zz`. El
script solo admite macOS Tahoe y exige un disco USB completo, no una partición:

```bash
sudo ./tools/prepare-macos-recovery-usb.sh --device /dev/sdX
```

La descarga utiliza el comando de Tahoe publicado por Dortania:

```bash
python3 ./macrecovery.py \
  -b Mac-CFF7D910A743CAAF \
  -m 00000000000000000 \
  -os latest download
```

El `board-id` anterior selecciona el catálogo de Recovery; no sustituye el
SMBIOS del EFI. Si la descarga ya existe, se puede reutilizar:

```bash
sudo ./tools/prepare-macos-recovery-usb.sh \
  --device /dev/sdX \
  --skip-download
```

Antes de modificar el disco, el script abre `SystemVersion.plist` dentro del
DMG y rechaza cualquier versión que no sea 26.x. Después crea una GPT, una
partición FAT32 `OPENCORE`, una partición HFS Recovery y verifica la cabecera
HFS+ escrita.

El disco indicado se borra por completo. El script rechaza dispositivos no USB,
discos que no estén marcados como extraíbles y unidades montadas. Comprueba el
destino con `lsblk` y escribe exactamente `ACEPTO` cuando estés seguro.

### Primera prueba controlada

1. En UEFI, desactiva Secure Boot y CSM. Activa XHCI Hand-off si la opción
   existe. Mantén Above 4G Decoding activado y Re-Size BAR desactivado.
2. Prepara de nuevo el USB con el script; copiar solo la carpeta EFI no cambia
   una Recovery Sequoia antigua por Tahoe.
3. Arranca la entrada UEFI del USB y elige `macOS Base System`.
4. No selecciones Reset NVRAM.
5. Tras el intento, monta la partición `OPENCORE` en Linux y revisa el TXT más
   reciente. Un intento Tahoe debe mostrar kernel Darwin `25.x`, no `24.x`.

Los registros anteriores mostraban Sequoia 15.6/Darwin 24.6. Todos los parches
AMD terminaban correctamente, pero `boot.efi` devolvía `EFI_ABORTED` después de
`EXITBS:START`; no había kernel panic. Por eso cambiar repetidamente la serial
no podía resolverlo.

### Funciones pospuestas

Para aislar el primer arranque se retiraron temporalmente audio, Wi-Fi,
Bluetooth, batería, brillo, lector de tarjetas, NVMeFix y trackpad I2C. Se
reincorporarán por grupos después de alcanzar la interfaz de Recovery.

Tahoe eliminó AppleHDA, por lo que AppleALC no proporciona audio analógico de
forma normal. Para la instalación se recomienda audio USB. La AX200 tampoco
debe considerarse una conexión fiable dentro de Recovery; usa Ethernet USB o
un instalador sin conexión.

### Gentoo y NVRAM

OpenCore conserva una entrada directa al cargador systemd-boot del ESP interno.
Si el firmware pierde su entrada de Gentoo, inicia el `.efi` manualmente una vez
y vuelve a registrarlo desde Linux:

```bash
sudo ./tools/restore-gentoo-uefi-entry.sh
```

El script no modifica particiones ni archivos del ESP; únicamente crea y ordena
la entrada UEFI mediante `efibootmgr`.

Consulta [TAHOE-REBUILD.md](docs/TAHOE-REBUILD.md) para la procedencia exacta de
los componentes, decisiones de aislamiento y lista de validaciones.

## English

### Status and scope

This repository contains a diagnostic EFI rebuilt to boot **macOS Tahoe 26.x
Recovery** on an AMD Renoir laptop. It is a minimal first-stage configuration;
it still requires validation on the physical machine before it can be called
stable or copied to an internal disk.

Dortania does not officially support AMD laptop CPUs. General OpenCore settings
follow its guide, while Renoir iGPU support depends on NootedRed and community
AMD patches. No EFI can be guaranteed to boot without hardware testing.

The documentation contains no serial numbers, UUIDs, ROM addresses, or personal
paths. Do not expose the SMBIOS identity from `config.plist` in screenshots or
reports.

### Minimal boot profile

The EFI was rebuilt from the matching OpenCore 1.0.8 DEBUG `Sample.plist` and
binaries. It contains only:

- ACPI: `SSDT-EC`, `SSDT-RTCAWAC`, `SSDT-USB-Reset`, and `SSDT-USBX`.
- Kexts: Lilu, NootedRed, VirtualSMC, AppleMCEReporterDisabler,
  ForgedInvariant, GenericUSBXHCI, USBToolBox, the USB map, and PS/2 keyboard.
- Drivers: `apfs_aligned.efi`, `HfsPlus.efi`, and `OpenRuntime.efi`.
- 27 Darwin 25-capable AMD patches, adjusted for six cores.
- A Tahoe-compatible `MacBookPro16,2` SMBIOS.
- Persistent OpenCore logs and firmware hardware reports on the USB drive.
- An explicit Gentoo EFI loader entry.

For Tahoe, `UEFI -> APFS -> EnableJumpstart` is disabled and
`apfs_aligned.efi` is loaded. Initial boot arguments are:

```text
-v debug=0x100 keepsyms=1
```

Reset NVRAM was removed from this stage because it also erased `BootOrder` and
the Gentoo UEFI entry without fixing macOS.

### Create the Tahoe USB on Linux

Install `python3`, `sgdisk`, `dosfstools` (`mkfs.vfat`), and `7z` or `7zz`.
Pass the complete removable USB disk, never one of its partitions:

```bash
sudo ./tools/prepare-macos-recovery-usb.sh --device /dev/sdX
```

The script uses Dortania's Tahoe recovery command and supports Tahoe only. Reuse
an existing download with:

```bash
sudo ./tools/prepare-macos-recovery-usb.sh \
  --device /dev/sdX \
  --skip-download
```

Before erasing anything, the script reads `SystemVersion.plist` from the DMG and
rejects every image that is not macOS 26.x. It then creates a GPT, a FAT32
`OPENCORE` partition, an HFS Recovery partition, and validates the written HFS+
header.

The selected disk is erased completely. The script rejects non-USB devices,
non-removable disks, and mounted volumes. Verify the target with `lsblk` and type
the exact word `ACEPTO` only when the target is correct.

### Controlled first test

1. Disable Secure Boot and CSM in UEFI. Enable XHCI Hand-off when available.
   Keep Above 4G Decoding enabled and Re-Size BAR disabled.
2. Rebuild the USB with the script; copying only the EFI cannot turn an old
   Sequoia Recovery into Tahoe.
3. Boot the USB UEFI entry and select `macOS Base System`.
4. Do not use Reset NVRAM.
5. Mount `OPENCORE` from Linux after the attempt and inspect the newest TXT. A
   real Tahoe attempt must report Darwin `25.x`, not `24.x`.

The previous logs were Sequoia 15.6/Darwin 24.6. AMD patching completed, but
`boot.efi` returned `EFI_ABORTED` after `EXITBS:START`; there was no kernel
panic. Repeated serial changes therefore could not fix the failure.

### Deferred functionality

Audio, Wi-Fi, Bluetooth, battery, brightness, card reader, NVMeFix, and I2C
trackpad support are intentionally absent from the first-stage EFI. They should
be reintroduced in small groups only after Recovery reaches its graphical UI.

Tahoe removed AppleHDA, so AppleALC no longer supplies normal analog audio. Use
USB audio during installation. The AX200 should not be treated as dependable
inside Recovery either; use USB Ethernet or an offline installer.

### Gentoo and NVRAM

OpenCore keeps a direct entry for the internal systemd-boot EFI loader. If the
firmware loses the Gentoo entry, boot its `.efi` manually once and restore it
from Linux:

```bash
sudo ./tools/restore-gentoo-uefi-entry.sh
```

The helper changes no partitions or ESP files; it only recreates and orders the
UEFI entry with `efibootmgr`.

See [TAHOE-REBUILD.md](docs/TAHOE-REBUILD.md) for component provenance,
isolation decisions, and validation results.

## References

- [Dortania OpenCore Install Guide](https://dortania.github.io/OpenCore-Install-Guide/)
- [Dortania: macOS Tahoe notes](https://dortania.github.io/OpenCore-Install-Guide/extras/tahoe.html)
- [Dortania: Linux installer](https://dortania.github.io/OpenCore-Install-Guide/installer-guide/linux-install.html)
- [AMD Vanilla](https://github.com/AMD-OSX/AMD_Vanilla)
- [NootedRed](https://github.com/ChefKissInc/NootedRed)
- [OpCore-Simplify](https://github.com/lzhoang2801/OpCore-Simplify)
