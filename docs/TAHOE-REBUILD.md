# Reconstrucción Tahoe / Tahoe rebuild

Fecha de reconstrucción / Rebuild date: 2026-07-31

## Diagnóstico que motivó la reconstrucción

Los archivos `opencore-2026-07-31-164354.txt` y
`opencore-2026-07-31-164421.txt` del USB no contenían un intento de Tahoe. El
segundo registraba:

```text
SdkVersion 15.6
SdkBuild 24G78
OCAK: Read kernel version 24.6.0 (240600)
```

Los parches AMD, el kernel collection y las extensiones preenlazadas terminaban
con `Success`. El final real era:

```text
AAPL: #[EB|LOG:EXITBS:START]
OC: Boot failed - Aborted
OCB: StartImage failed - Aborted
```

OpenCore recuperaba el control y volvía al selector veinte segundos después. No
había kernel panic. La evidencia era compatible con `boot.efi` devolviendo
`EFI_ABORTED`, no con un fallo de serial. Además, Reset NVRAM borraba
`BootOrder` y la entrada UEFI de Gentoo. Después de conservar este diagnóstico,
los dos TXT de Sequoia se eliminaron del USB para que la siguiente prueba deje
únicamente registros Tahoe nuevos.

The two USB logs did not contain a Tahoe attempt. They loaded Sequoia 15.6,
Darwin 24.6. AMD patching and kext linking succeeded, then `boot.efi` returned
`EFI_ABORTED` after `EXITBS:START`. OpenCore regained control; no kernel panic
was recorded. Reset NVRAM also removed the Gentoo boot entry.

## Recovery verificada / Verified Recovery

La Recovery activa se descargó directamente desde Apple mediante `macrecovery`
con el identificador que Dortania publica para Tahoe:

```text
Catalog product: 122-26025
ProductVersion: 26.6
ProductBuildVersion: 25G72
```

`macrecovery` verificó todos los chunks contra `BaseSystem.chunklist`. El script
del repositorio también lee `SystemVersion.plist` dentro del DMG y exige una
versión `26.x` antes de particionar un USB.

The active Recovery was downloaded from Apple, verified against its chunklist,
and identified from its embedded `SystemVersion.plist` as Tahoe 26.6 build
25G72. The USB helper rejects non-26.x images.

## Procedencia reproducible / Reproducible provenance

| Componente / Component | Procedencia / Source | Revisión / Revision |
| --- | --- | --- |
| OpenCore DEBUG | Dortania build-repo, tag `OpenCorePkg-3eb5eea` | 1.0.8, 2026-06-08 |
| OpenCore ZIP SHA-256 | Publicado por Dortania y comprobado localmente | `939605d0b2b476b06e6f2e883ca9b9a6f592e71ed31bdad151c3932430a79efc` |
| `apfs_aligned.efi`, `HfsPlus.efi` | Acidanthera OcBinaryData | `e74e533d8f89c1d5014cfb47c185502bf415741f` |
| AMD patches | Fork usado por OpCore-Simplify, `laobamac/AMD_Vanilla` | `a174cca80efe2377fde3b902666c70863ea66454` |
| OpCore-Simplify audit | `lzhoang2801/OpCore-Simplify` | `40eb4bd31952363faa73c5b2ae7e6f1d5e1d2aeb` |
| NootedRed compatibility audit | `ChefKissInc/NootedRed` | `0f847f2b8b14eeb0f0014fc06e5c6e7c04076b5f` |

Los archivos `BOOTx64.efi` y `OpenCore.efi` del repositorio coinciden por
SHA-256 con el paquete DEBUG anterior. `config.plist` se creó desde su
`Sample.plist`, no mediante una edición acumulativa del archivo previo.

The repository's core EFI binaries hash-identically to the downloaded DEBUG
package. The configuration was built from that package's `Sample.plist`, not by
continuing to stack edits on the prior configuration.

## Decisiones Tahoe específicas / Tahoe-specific decisions

- `MacBookPro16,2` se conserva: está soportado por Tahoe y es la selección de
  OpCore-Simplify para portátiles AMD.
- La identidad SMBIOS existente se conserva de forma coherente. No se generó
  otra serial porque no influye en `EXITBS` ni en el acceso al dispositivo raíz.
- `UEFI/APFS/EnableJumpstart=NO` y `apfs_aligned.efi` se añadieron conforme a la
  plantilla Tahoe de OpCore-Simplify.
- El firmware reporta Memory Attribute Table, por lo que se usa la pareja
  `EnableWriteUnprotector=NO` y `RebuildAppleMemoryMap=YES`.
- `SetupVirtualMap=YES` y `SyncRuntimePermissions=YES` forman la base limpia de
  AMD/UEFI. El ensayo anterior con `SetupVirtualMap=NO` no corrigió el aborto.
- `SecureBootModel=Disabled`, `DmgLoading=Signed`, `Vault=Optional` y
  `ScanPolicy=0` permiten el diagnóstico de Recovery Tahoe.
- `XhciPortLimit=NO`, `ReleaseUsbOwnership=YES` y el mapa USB específico se
  mantienen para evitar perder el medio de instalación.
- `ResetNvramEntry.efi` se retiró durante esta etapa para proteger el arranque
  de Gentoo.

English summary: keep the supported `MacBookPro16,2` identity; use Tahoe's
aligned APFS driver with jumpstart disabled; use the MAT-aware AMD memory-map
combination; keep the real USB map; and remove Reset NVRAM from the diagnostic
picker.

## ACPI y kexts mínimos / Minimal ACPI and kexts

ACPI habilitado:

```text
SSDT-EC.aml
SSDT-RTCAWAC.aml
SSDT-USB-Reset.aml
SSDT-USBX.aml
```

Las rutas usadas por estas tablas se comprobaron contra el DSDT generado por
OpenCore. ALS0, PNLF, PLUG-ALT y XOSI se retiraron de la primera prueba porque
son funciones posteriores al arranque.

Entradas de kext habilitadas:

```text
Lilu.kext
NootedRed.kext
AppleMCEReporterDisabler.kext
ForgedInvariant.kext
GenericUSBXHCI.kext
VirtualSMC.kext
USBToolBox.kext
UTBMap.kext
VoodooPS2Controller.kext
VoodooPS2Keyboard.kext
```

NootedRed 0.8.10 reconoce la iGPU Renoir y su código actual admite Tahoe y
Recovery. Los cuatro parches `cpuid_cores_per_package` usan el valor `06`. Solo
la variante PAT Shaneee correspondiente está habilitada; las variantes PAT
alternativas permanecen deshabilitadas.

The enabled ACPI and kext set is limited to firmware correction, AMD graphics,
SMC emulation, USB continuity, and the internal keyboard. AMD core-count bytes
are set to six, and mutually exclusive PAT variants are not enabled together.

## Elementos retirados temporalmente / Temporarily removed

- AppleALC y la propiedad `layout-id`: Tahoe retiró AppleHDA.
- Intel Bluetooth y BlueToolFixup; al reactivarlos Tahoe requiere
  `-ibtcompatbeta`.
- `itlwm`; Recovery no debe depender de la AX200.
- NVMeFix, lector de tarjetas, batería, sensor de luz y brillo.
- VoodooI2C/HID y plugins PS/2 de ratón o trackpad.
- RestrictEvents y variables `rev*` durante la prueba mínima.
- Propiedades `built-in` de red/NVMe que no son necesarias para entrar a
  Recovery.

These components are deferred, not declared permanently unsupported. Re-enable
them in small groups after the Recovery GUI is reached, validating and saving a
new log after each group.

## Validaciones realizadas / Validation performed

```text
ocvalidate 1.0.8: No issues found
Enabled ACPI entries: 4
Enabled kernel entries: 10
Enabled UEFI drivers: 3
Missing referenced files: 0
SetupVirtualMap: true
EnableJumpstart: false
SMBIOS model: MacBookPro16,2
Shell syntax check: passed
Embedded Recovery version: 26.6 (25G72)
```

Estas validaciones demuestran consistencia estructural, no que el equipo ya
haya arrancado. El siguiente registro válido debe mostrar Darwin 25.x. Si vuelve
a fallar, se debe cambiar una sola variable por prueba; los primeros aislamientos
son NootedRed sin aceleración y, después, el conjunto USB.

These checks prove structural consistency, not a successful physical boot. The
next valid log must identify Darwin 25.x. If it still fails, change one variable
per test; the first controlled isolation is NootedRed acceleration, followed by
the USB stack.

## Fuentes / Sources

- [Dortania AMD Zen guide](https://dortania.github.io/OpenCore-Install-Guide/AMD/zen.html)
- [Dortania Tahoe notes](https://dortania.github.io/OpenCore-Install-Guide/extras/tahoe.html)
- [Dortania Linux installer](https://dortania.github.io/OpenCore-Install-Guide/installer-guide/linux-install.html)
- [Acidanthera OpenCorePkg](https://github.com/acidanthera/OpenCorePkg)
- [AMD Vanilla](https://github.com/AMD-OSX/AMD_Vanilla)
- [NootedRed](https://github.com/ChefKissInc/NootedRed)
- [OpCore-Simplify](https://github.com/lzhoang2801/OpCore-Simplify)
