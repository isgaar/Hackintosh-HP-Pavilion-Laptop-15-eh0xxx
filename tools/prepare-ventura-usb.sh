#!/usr/bin/env bash
# Crea un USB de recuperación de macOS Ventura con el EFI de este repositorio.
# Basado en el método 1 de la guía de Dortania para Linux.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
EFI_SOURCE="$REPO_DIR/EFI"
INVOKING_USER="${SUDO_USER:-${USER:-root}}"
INVOKING_HOME="$(getent passwd "$INVOKING_USER" 2>/dev/null | cut -d: -f6 || true)"
INVOKING_HOME="${INVOKING_HOME:-$HOME}"
DEFAULT_MACRECOVERY_DIR="${MACRECOVERY_DIR:-$INVOKING_HOME/Proyectos/opencore/Utilities/macrecovery}"

DEVICE=""
MACRECOVERY_DIR="$DEFAULT_MACRECOVERY_DIR"
SKIP_DOWNLOAD=false
MOUNT_DIR=""

readonly VENTURA_BOARD_ID="Mac-B4831CEBD52A0C4C"
readonly VENTURA_MLB="00000000000000000"

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<EOF
Uso:
  sudo $0 --device /dev/sdX [--macrecovery /ruta/a/macrecovery] [--skip-download]

Opciones:
  --device RUTA         Disco USB completo que se va a borrar (ej. /dev/sda).
  --macrecovery RUTA    Directorio con macrecovery.py. Por defecto:
                         \${MACRECOVERY_DIR} o $DEFAULT_MACRECOVERY_DIR
  --skip-download       Reutiliza BaseSystem.dmg y BaseSystem.chunklist ya descargados.
  -h, --help            Muestra esta ayuda.

El script crea una GPT con una única partición FAT32 OPENCORE, descarga Recovery
de Ventura, copia com.apple.recovery.boot y el directorio EFI de este repositorio.
No se puede ejecutar de forma no interactiva: antes de borrar se debe confirmar el
nombre exacto del disco.
EOF
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Falta el comando requerido: $1"
}

cleanup() {
    local exit_code=$?

    if [[ -n "$MOUNT_DIR" ]]; then
        if mountpoint -q "$MOUNT_DIR"; then
            umount "$MOUNT_DIR" || true
        fi
        rmdir "$MOUNT_DIR" 2>/dev/null || true
    fi

    exit "$exit_code"
}

is_mounted() {
    local node
    while IFS= read -r node; do
        [[ -n "$node" ]] || continue
        if findmnt --raw --noheadings --source "$node" >/dev/null 2>&1; then
            return 0
        fi
    done < <(lsblk --noheadings --raw --paths --output NAME "$DEVICE")

    return 1
}

wait_for_partition() {
    local attempts=0
    while [[ ! -b "$PARTITION" && $attempts -lt 10 ]]; do
        sleep 1
        attempts=$((attempts + 1))
    done

    [[ -b "$PARTITION" ]] || die "No apareció la partición esperada: $PARTITION"
}

download_recovery() {
    if [[ "$SKIP_DOWNLOAD" == true ]]; then
        return
    fi

    printf 'Descargando macOS Ventura Recovery mediante macrecovery...\n'
    (
        cd -- "$MACRECOVERY_DIR"
        python3 ./macrecovery.py \
            -b "$VENTURA_BOARD_ID" \
            -m "$VENTURA_MLB" \
            download
    )
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --device)
            [[ $# -ge 2 ]] || die "--device requiere una ruta de disco."
            DEVICE="$2"
            shift 2
            ;;
        --macrecovery)
            [[ $# -ge 2 ]] || die "--macrecovery requiere una ruta."
            MACRECOVERY_DIR="$2"
            shift 2
            ;;
        --skip-download)
            SKIP_DOWNLOAD=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Opción desconocida: $1"
            ;;
    esac
done

[[ $EUID -eq 0 ]] || die "Ejecuta el script con sudo."
[[ -n "$DEVICE" ]] || {
    usage
    die "Debes indicar --device /dev/sdX."
}

require_command sgdisk
require_command lsblk
require_command findmnt
require_command mount
require_command umount
require_command mountpoint
require_command python3
require_command mktemp
require_command sync

FAT_FORMATTER="$(command -v mkfs.vfat || command -v mkfs.fat || true)"
[[ -n "$FAT_FORMATTER" ]] || die "Instala dosfstools (mkfs.vfat o mkfs.fat)."

DEVICE="$(readlink -f -- "$DEVICE")"
[[ -b "$DEVICE" ]] || die "$DEVICE no es un dispositivo de bloques."
[[ "$(lsblk --noheadings --raw --output TYPE "$DEVICE")" == "disk" ]] || die "Indica el disco completo, no una partición."
[[ "$(lsblk --noheadings --raw --output RM "$DEVICE")" == "1" ]] || die "$DEVICE no está marcado como extraíble; se rechaza por seguridad."
[[ "$(lsblk --noheadings --raw --output TRAN "$DEVICE")" == "usb" ]] || die "$DEVICE no está conectado por USB; se rechaza por seguridad."
[[ -f "$EFI_SOURCE/BOOT/BOOTx64.efi" ]] || die "No encuentro $EFI_SOURCE/BOOT/BOOTx64.efi"
[[ -f "$EFI_SOURCE/OC/OpenCore.efi" ]] || die "No encuentro $EFI_SOURCE/OC/OpenCore.efi"
[[ -f "$EFI_SOURCE/OC/config.plist" ]] || die "No encuentro $EFI_SOURCE/OC/config.plist"
[[ -f "$MACRECOVERY_DIR/macrecovery.py" ]] || die "No encuentro macrecovery.py en: $MACRECOVERY_DIR"

if is_mounted; then
    die "$DEVICE o una de sus particiones está montada. Desmóntala o arranca desde otro medio antes de continuar."
fi

case "$DEVICE" in
    *[0-9]) PARTITION="${DEVICE}p1" ;;
    *) PARTITION="${DEVICE}1" ;;
esac

printf '\nEl siguiente disco se BORRARÁ por completo:\n\n'
lsblk --paths --output NAME,RM,SIZE,MODEL,TRAN,FSTYPE,LABEL,MOUNTPOINTS "$DEVICE"
printf '\nSe instalarán macOS Ventura Recovery y el EFI de: %s\n' "$REPO_DIR"
read -r -p "Escribe exactamente 'BORRAR $DEVICE' para continuar: " confirmation
[[ "$confirmation" == "BORRAR $DEVICE" ]] || die "Confirmación incorrecta; no se modificó ningún disco."

download_recovery

RECOVERY_DIR="$MACRECOVERY_DIR/com.apple.recovery.boot"
if [[ -f "$RECOVERY_DIR/BaseSystem.dmg" && -f "$RECOVERY_DIR/BaseSystem.chunklist" ]]; then
    RECOVERY_DMG="$RECOVERY_DIR/BaseSystem.dmg"
    RECOVERY_CHUNKLIST="$RECOVERY_DIR/BaseSystem.chunklist"
elif [[ -f "$RECOVERY_DIR/RecoveryImage.dmg" && -f "$RECOVERY_DIR/RecoveryImage.chunklist" ]]; then
    RECOVERY_DMG="$RECOVERY_DIR/RecoveryImage.dmg"
    RECOVERY_CHUNKLIST="$RECOVERY_DIR/RecoveryImage.chunklist"
else
    die "No encuentro BaseSystem/RecoveryImage .dmg y .chunklist en $RECOVERY_DIR"
fi

printf '\nCreando GPT y FAT32 OPENCORE en %s...\n' "$DEVICE"
sgdisk --zap-all "$DEVICE"
sgdisk --clear --new=1:1MiB:0 --typecode=1:0700 --change-name=1:OPENCORE "$DEVICE"
sync

if command -v partprobe >/dev/null 2>&1; then
    partprobe "$DEVICE"
fi
if command -v udevadm >/dev/null 2>&1; then
    udevadm settle
fi
wait_for_partition

"$FAT_FORMATTER" -F 32 -n OPENCORE "$PARTITION"

MOUNT_DIR="$(mktemp -d /tmp/opencore-ventura-usb.XXXXXX)"
trap cleanup EXIT INT TERM
mount "$PARTITION" "$MOUNT_DIR"

printf 'Copiando Recovery y EFI...\n'
mkdir -p "$MOUNT_DIR/com.apple.recovery.boot" "$MOUNT_DIR/EFI"
cp -v "$RECOVERY_DMG" "$RECOVERY_CHUNKLIST" "$MOUNT_DIR/com.apple.recovery.boot/"
cp -R "$EFI_SOURCE/." "$MOUNT_DIR/EFI/"
sync

[[ -f "$MOUNT_DIR/com.apple.recovery.boot/$(basename -- "$RECOVERY_DMG")" ]] || die "No se copió la imagen de Recovery."
[[ -f "$MOUNT_DIR/com.apple.recovery.boot/$(basename -- "$RECOVERY_CHUNKLIST")" ]] || die "No se copió el chunklist de Recovery."
[[ -f "$MOUNT_DIR/EFI/BOOT/BOOTx64.efi" ]] || die "No se copió BOOTx64.efi."
[[ -f "$MOUNT_DIR/EFI/OC/config.plist" ]] || die "No se copió config.plist."

umount "$MOUNT_DIR"
rmdir "$MOUNT_DIR"
MOUNT_DIR=""
trap - EXIT INT TERM

printf '\nUSB preparado correctamente: %s (%s)\n' "$DEVICE" "$PARTITION"
printf 'Expúlsalo de forma segura y arranca desde la entrada UEFI del USB.\n'
