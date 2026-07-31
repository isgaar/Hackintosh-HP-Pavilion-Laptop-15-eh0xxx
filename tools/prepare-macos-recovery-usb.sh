#!/usr/bin/env bash
# Crea un USB de recuperación de macOS Tahoe con el método FAT32 de Dortania.

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
EFI_PARTITION=""
RECOVERY_PRODUCT_VERSION=""

readonly RECOVERY_MLB="00000000000000000"
readonly TAHOE_BOARD_ID="Mac-CFF7D910A743CAAF"
readonly MIN_USB_BYTES=$((2 * 1024 * 1024 * 1024))

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<EOF
Uso / Usage:
  sudo $0 --device /dev/sdX [--macrecovery /ruta/a/macrecovery] [--skip-download]

Opciones / Options:
  --device RUTA         Disco USB completo que se va a borrar (ej. /dev/sda).
  --device PATH         Complete USB disk to erase (e.g. /dev/sda).
  --macrecovery RUTA    Directorio que contiene macrecovery.py. Por defecto:
  --macrecovery PATH    Directory containing macrecovery.py. Default:
                         \${MACRECOVERY_DIR} o ~/Proyectos/opencore/Utilities/macrecovery
  --os tahoe            Alias opcional; únicamente Tahoe es compatible.
  --os tahoe            Optional alias; only Tahoe is supported.
  --skip-download       Reutiliza una imagen de Recovery ya descargada.
  --skip-download       Reuse an already downloaded Recovery image.
  -h, --help            Muestra esta ayuda / Show this help.

El script crea una sola partición FAT32 OPENCORE. Copia EFI/ y los archivos
BaseSystem.dmg y BaseSystem.chunklist a com.apple.recovery.boot/, tal como el
método principal de Dortania para Linux. No se puede ejecutar de forma no
interactiva: antes de borrar se debe confirmar el texto solicitado.

The script creates one FAT32 OPENCORE partition. It copies EFI/ and
BaseSystem.dmg and BaseSystem.chunklist to com.apple.recovery.boot/, following
Dortania's primary Linux method. It cannot run non-interactively: the requested
confirmation must be entered before the disk is erased.
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
    local partition="$1"
    local attempts=0
    while [[ ! -b "$partition" && $attempts -lt 10 ]]; do
        sleep 1
        attempts=$((attempts + 1))
    done

    [[ -b "$partition" ]] || die "No apareció la partición esperada: $partition"
}

download_recovery() {
    if [[ "$SKIP_DOWNLOAD" == true ]]; then
        return
    fi

    printf 'Descargando macOS Tahoe Recovery mediante macrecovery...\n'
    (
        cd -- "$MACRECOVERY_DIR"
        python3 ./macrecovery.py \
            -b "$TAHOE_BOARD_ID" \
            -m "$RECOVERY_MLB" \
            -os latest \
            download
    )
}

verify_tahoe_recovery() {
    RECOVERY_PRODUCT_VERSION="$(
        "$SEVEN_ZIP" e -so "$RECOVERY_DMG" \
            'macOS Base System/System/Library/CoreServices/SystemVersion.plist' 2>/dev/null |
            python3 -c 'import plistlib, sys; print(plistlib.loads(sys.stdin.buffer.read()).get("ProductVersion", ""))'
    )"

    [[ "$RECOVERY_PRODUCT_VERSION" == 26.* ]] || {
        [[ -n "$RECOVERY_PRODUCT_VERSION" ]] || RECOVERY_PRODUCT_VERSION="desconocida / unknown"
        die "La imagen descargada es macOS $RECOVERY_PRODUCT_VERSION; este EFI y este script son exclusivamente para Tahoe 26.x."
    }

    printf 'Recovery verificada: macOS Tahoe %s.\n' "$RECOVERY_PRODUCT_VERSION"
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
        --os)
            [[ $# -ge 2 ]] || die "--os requiere tahoe."
            [[ "${2,,}" == "tahoe" ]] || die "Versión no compatible: $2. Usa tahoe."
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

SEVEN_ZIP="$(command -v 7z || command -v 7zz || true)"
[[ -n "$SEVEN_ZIP" ]] || die "Instala 7z/7zz para verificar la Recovery de Tahoe."

FAT_FORMATTER="$(command -v mkfs.vfat || command -v mkfs.fat || true)"
[[ -n "$FAT_FORMATTER" ]] || die "Instala dosfstools (mkfs.vfat o mkfs.fat)."

DEVICE="$(readlink -f -- "$DEVICE")"
[[ -b "$DEVICE" ]] || die "$DEVICE no es un dispositivo de bloques."
[[ "$(lsblk --noheadings --raw --nodeps --output TYPE "$DEVICE")" == "disk" ]] || die "Indica el disco completo, no una partición."
[[ "$(lsblk --noheadings --raw --nodeps --output RM "$DEVICE")" == "1" ]] || die "$DEVICE no está marcado como extraíble; se rechaza por seguridad."
[[ "$(lsblk --noheadings --raw --nodeps --output TRAN "$DEVICE")" == "usb" ]] || die "$DEVICE no está conectado por USB; se rechaza por seguridad."
DEVICE_SIZE_BYTES="$(lsblk --bytes --noheadings --raw --nodeps --output SIZE "$DEVICE" | tr -d '[:space:]')"
[[ "$DEVICE_SIZE_BYTES" =~ ^[0-9]+$ && "$DEVICE_SIZE_BYTES" -ge "$MIN_USB_BYTES" ]] || die "$DEVICE debe tener al menos 2 GiB para Recovery Tahoe."
[[ -f "$EFI_SOURCE/BOOT/BOOTx64.efi" ]] || die "No encuentro $EFI_SOURCE/BOOT/BOOTx64.efi"
[[ -f "$EFI_SOURCE/OC/OpenCore.efi" ]] || die "No encuentro $EFI_SOURCE/OC/OpenCore.efi"
[[ -f "$EFI_SOURCE/OC/config.plist" ]] || die "No encuentro $EFI_SOURCE/OC/config.plist"
[[ -f "$MACRECOVERY_DIR/macrecovery.py" ]] || die "No encuentro macrecovery.py en: $MACRECOVERY_DIR"

if is_mounted; then
    die "$DEVICE o una de sus particiones está montada. Desmóntala o arranca desde otro medio antes de continuar."
fi

case "$DEVICE" in
    *[0-9]) EFI_PARTITION="${DEVICE}p1" ;;
    *) EFI_PARTITION="${DEVICE}1" ;;
esac

printf '\nEl siguiente disco se BORRARÁ por completo:\n\n'
lsblk --paths --output NAME,RM,SIZE,MODEL,TRAN,FSTYPE,LABEL,MOUNTPOINTS "$DEVICE"
printf '\nSe instalarán macOS Tahoe Recovery y el EFI de este repositorio.\n'
printf 'macOS Tahoe Recovery and this repository EFI will be installed.\n'
read -r -p "Escribe exactamente 'ACEPTO' para continuar / Type exactly 'ACEPTO' to continue: " confirmation
[[ "$confirmation" == "ACEPTO" ]] || die "Confirmación incorrecta / Invalid confirmation; no se modificó ningún disco."

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

verify_tahoe_recovery

printf '\nCreando GPT y una partición FAT32 OPENCORE en %s...\n' "$DEVICE"
sgdisk --zap-all "$DEVICE"
sgdisk --clear --new=1:1MiB:0 --typecode=1:0700 --change-name=1:OPENCORE "$DEVICE"
sync

if command -v partprobe >/dev/null 2>&1; then
    partprobe "$DEVICE"
fi
if command -v udevadm >/dev/null 2>&1; then
    udevadm settle
fi
wait_for_partition "$EFI_PARTITION"
"$FAT_FORMATTER" -F 32 -n OPENCORE "$EFI_PARTITION"

MOUNT_DIR="$(mktemp -d /tmp/opencore-macos-usb.XXXXXX)"
trap cleanup EXIT INT TERM
mount "$EFI_PARTITION" "$MOUNT_DIR"

printf 'Copiando EFI y Recovery al volumen FAT32...\n'
mkdir -p "$MOUNT_DIR/EFI" "$MOUNT_DIR/com.apple.recovery.boot"
cp -R "$EFI_SOURCE/." "$MOUNT_DIR/EFI/"
cp "$RECOVERY_DMG" "$MOUNT_DIR/com.apple.recovery.boot/BaseSystem.dmg"
cp "$RECOVERY_CHUNKLIST" "$MOUNT_DIR/com.apple.recovery.boot/BaseSystem.chunklist"
sync

[[ -f "$MOUNT_DIR/EFI/BOOT/BOOTx64.efi" ]] || die "No se copió BOOTx64.efi."
[[ -f "$MOUNT_DIR/EFI/OC/config.plist" ]] || die "No se copió config.plist."
[[ -s "$MOUNT_DIR/com.apple.recovery.boot/BaseSystem.dmg" ]] || die "No se copió BaseSystem.dmg."
[[ -s "$MOUNT_DIR/com.apple.recovery.boot/BaseSystem.chunklist" ]] || die "No se copió BaseSystem.chunklist."

umount "$MOUNT_DIR"
rmdir "$MOUNT_DIR"
MOUNT_DIR=""
trap - EXIT INT TERM

printf '\nUSB Tahoe preparado correctamente: EFI y com.apple.recovery.boot en %s.\n' "$EFI_PARTITION"
printf 'Expúlsalo de forma segura y arranca desde la entrada UEFI del USB.\n'
