# EFI OpenCore — HP Pavilion Laptop 15-eh0xxx

EFI construida para el hardware y firmware de este equipo; no es una configuración genérica.

## Objetivo

- macOS Ventura 13 (Darwin 22.x).
- OpenCore 1.0.8.
- Generada y ajustada con [OpCore-Simplify](https://github.com/lzhoang2801/OpCore-Simplify).

OpCore-Simplify detectó soporte funcional en versiones posteriores, pero recomendó Ventura como el límite de mayor estabilidad para este APU Renoir. Por ello esta revisión no apunta a Sequoia.

## Hardware verificado

| Componente | Identificación exacta | Configuración aplicada |
| --- | --- | --- |
| Equipo / firmware | HP Pavilion 15-eh0xxx, placa 87C5, BIOS F.32 (2025-08-14) | Tablas ACPI del firmware F.32 |
| CPU / iGPU | AMD Ryzen 5 4500U (Renoir), Radeon Vega 6 `1002:1636` | NootedRed + ForgedInvariant |
| Audio | Realtek ALC287, controlador AMD `1022:15e3` | AppleALC, `layout-id = 11` |
| Wi-Fi / Bluetooth | Intel AX200 `8086:2723`, BT `8087:0029` | itlwm, IntelBluetoothFirmware, IntelBTPatcher y BlueToolFixup |
| Almacenamiento | WD Green SN350 NVMe `15b7:5014` | NVMeFix |
| Lector SD | Realtek RTS522A `10ec:522a` | Sinetek-rtsx |
| Teclado / trackpad | PS/2 PNP0303 / Synaptics I²C SYNA32AA | VoodooPS2Controller, VoodooI2C y VoodooI2CHID |
| USB | Dos controladores AMD `1022:1639` | GenericUSBXHCI + USBToolBox + mapa de 12 puertos |
| Cámara | HP Wide Vision HD `30c9:000e` | UVC nativo por el puerto USB interno mapeado |
| Batería / brillo | BAT0 ACPI / panel interno | SMCBatteryManager, SMCLightSensor, PNLF y BrightnessKeys |
| Memoria | 20 GB RAM | Soporte nativo; no requiere inyección |

## ACPI y USB

Solo se cargan los ocho SSDT generados para este firmware (`ALS0`, `EC`, `PLUG-ALT`, `PNLF`, `RTCAWAC`, `USB-Reset`, `USBX` y `XOSI`), en lugar de cargar el DSDT y todas las tablas originales como SSDT.

`UTBMap.kext` conserva y valida los seis puertos de cada controlador contra el DSDT: USB-C/USB-A externos y cámara/Bluetooth internos. No se usa `UTBDefault.kext`.

## Validaciones realizadas

- Informe de hardware validado por OpCore-Simplify.
- DSDT y SSDT de BIOS F.32 desensamblados correctamente con iASL.
- Todas las referencias activas de ACPI, kexts y drivers existen en el EFI.
- `ocvalidate` de OpenCore 1.0.8: sin incidencias.

## Uso seguro

Este repositorio no modifica `/boot/efi` ni el cargador de Linux. Copia `EFI/` primero a una memoria USB de instalación y conserva el EFI anterior hasta confirmar el arranque.

La BIOS debe arrancar en UEFI con Secure Boot desactivado. El primer arranque conserva `-v debug=0x100 keepsyms=1` para diagnosticar un fallo; elimínalos solo tras confirmar estabilidad. Para Wi-Fi en macOS instala HeliPort: `itlwm` es la opción estable, pero no ofrece AirDrop ni Instant Hotspot. Tras cualquier actualización de BIOS, vuelve a extraer ACPI y valida el EFI antes de usarlo.

### Crear el USB desde Linux

El script [tools/prepare-ventura-usb.sh](tools/prepare-ventura-usb.sh) implementa el método FAT32 de Dortania: descarga Ventura Recovery con `macrecovery`, crea una GPT nueva, copia `com.apple.recovery.boot` y el EFI. Por seguridad solo acepta discos USB extraíbles, rechaza los que estén montados y exige escribir el nombre del disco antes de borrarlo.

```bash
sudo ./tools/prepare-ventura-usb.sh --device /dev/sdX
```

Si `BaseSystem.dmg` y `BaseSystem.chunklist` ya están en `~/Proyectos/opencore/Utilities/macrecovery/com.apple.recovery.boot/`, añade `--skip-download`. Usa `/dev/sdX` únicamente después de confirmar con `lsblk` que es la memoria USB; el comando borra por completo ese disco.
