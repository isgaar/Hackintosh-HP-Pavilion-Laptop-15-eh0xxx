#!/usr/bin/env bash
# Crea un USB de recuperación de macOS con el EFI de este repositorio.
# Basado en el método 2 de la guía de Dortania para Linux.

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
MACOS_VERSION="sequoia"
EFI_PARTITION=""
RECOVERY_PARTITION=""
RECOVERY_PARTITION_INDEX=""
RECOVERY_HFS_MEMBER=""
DMG2IMG=""
SEVEN_ZIP=""

readonly RECOVERY_MLB="00000000000000000"
readonly MIN_USB_BYTES=$((4 * 1024 * 1024 * 1024))

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<EOF
Uso / Usage:
  sudo $0 --device /dev/sdX [--os sequoia|ventura] [--macrecovery /ruta/a/macrecovery] [--skip-download]

Opciones / Options:
  --device RUTA         Disco USB completo que se va a borrar (ej. /dev/sda).
  --device PATH         Complete USB disk to erase (e.g. /dev/sda).
  --macrecovery RUTA    Directorio que contiene macrecovery.py. Por defecto:
  --macrecovery PATH    Directory containing macrecovery.py. Default:
                         \${MACRECOVERY_DIR} o ~/Proyectos/opencore/Utilities/macrecovery
  --os VERSION           Recovery to download: sequoia (default) or ventura.
  --os VERSION           Recovery a descargar: sequoia (predeterminado) o ventura.
  --skip-download       Reutiliza una imagen de Recovery ya descargada.
  --skip-download       Reuse an already downloaded Recovery image.
  -h, --help            Muestra esta ayuda / Show this help.

El script crea una GPT con una partición FAT32 OPENCORE para la EFI y una
partición HFS para la imagen de Recovery. Descarga la Recovery elegida y extrae
su partición HFS con dmg2img o 7z. No se puede ejecutar de forma no interactiva:
antes de borrar se debe confirmar el texto solicitado.

The script creates a GPT with a FAT32 OPENCORE partition for the EFI and an HFS
partition for the Recovery image. It downloads the selected Recovery and
extracts its HFS partition with dmg2img or 7z. It cannot run non-interactively:
the requested confirmation must be entered before the disk is erased.
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

    local board_id
    local recovery_name

    case "$MACOS_VERSION" in
        sequoia)
            board_id="Mac-7BA5B2D9E42DDD94"
            recovery_name="macOS Sequoia"
            ;;
        ventura)
            board_id="Mac-B4831CEBD52A0C4C"
            recovery_name="macOS Ventura"
            ;;
        *)
            die "Versión no compatible: $MACOS_VERSION. Usa sequoia o ventura."
            ;;
    esac

    printf 'Descargando %s Recovery mediante macrecovery...\n' "$recovery_name"
    (
        cd -- "$MACRECOVERY_DIR"
        python3 ./macrecovery.py \
            -b "$board_id" \
            -m "$RECOVERY_MLB" \
            download
    )
}

find_hfs_partition_index() {
    local partition_list

    if [[ -n "$DMG2IMG" ]]; then
        partition_list="$("$DMG2IMG" -l "$RECOVERY_DMG" 2>&1)" || die "No se pudo listar la imagen de Recovery con dmg2img."
        RECOVERY_PARTITION_INDEX="$(awk '
            /^partition [0-9]+:/ { part_no = $2; sub(/:/, "", part_no) }
            /Apple_HFS/ && !found { result = part_no; found = 1 }
            END { if (found) print result }
        ' <<< "$partition_list")"
    else
        # Fuerza la capa DMG. Sin -tDmg, 7z abre el HFS anidado y puede no
        # emitir el miembro crudo 4.hfs aunque termine con estado correcto.
        partition_list="$("$SEVEN_ZIP" l -tDmg "$RECOVERY_DMG" 2>&1)" || die "No se pudo listar la imagen de Recovery con 7z."
        RECOVERY_HFS_MEMBER="$(awk '
            $NF ~ /^[0-9]+\.hfs$/ && !found { result = $NF; found = 1 }
            END { if (found) print result }
        ' <<< "$partition_list")"
        RECOVERY_PARTITION_INDEX="${RECOVERY_HFS_MEMBER%.hfs}"
    fi

    [[ "$RECOVERY_PARTITION_INDEX" =~ ^[0-9]+$ ]] || {
        printf '%s\n' "$partition_list" >&2
        die "No se encontró una partición Apple_HFS dentro de la imagen de Recovery."
    }
}

extract_hfs_recovery() {
    if [[ -n "$DMG2IMG" ]]; then
        "$DMG2IMG" -p "$RECOVERY_PARTITION_INDEX" "$RECOVERY_DMG" "$RECOVERY_PARTITION"
    else
        "$SEVEN_ZIP" e -tDmg -so "$RECOVERY_DMG" "$RECOVERY_HFS_MEMBER" > "$RECOVERY_PARTITION"
    fi
}

verify_hfs_recovery() {
    local signature

    signature="$(dd if="$RECOVERY_PARTITION" bs=1 skip=1024 count=2 status=none)" || die "No se pudo leer la cabecera de la partición Recovery."
    [[ "$signature" == "H+" ]] || die "La Recovery escrita no contiene una cabecera HFS+ válida; no arranques con este USB."
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
            [[ $# -ge 2 ]] || die "--os requiere sequoia o ventura."
            MACOS_VERSION="${2,,}"
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
case "$MACOS_VERSION" in
    sequoia|ventura) ;;
    *) die "Versión no compatible: $MACOS_VERSION. Usa sequoia o ventura." ;;
esac

require_command sgdisk
require_command lsblk
require_command findmnt
require_command mount
require_command umount
require_command mountpoint
require_command python3
require_command mktemp
require_command sync
require_command dd

DMG2IMG="$(command -v dmg2img || true)"
SEVEN_ZIP="$(command -v 7z || command -v 7zz || true)"
[[ -n "$DMG2IMG" || -n "$SEVEN_ZIP" ]] || die "Instala dmg2img o 7z/7zz para extraer la Recovery HFS."

FAT_FORMATTER="$(command -v mkfs.vfat || command -v mkfs.fat || true)"
[[ -n "$FAT_FORMATTER" ]] || die "Instala dosfstools (mkfs.vfat o mkfs.fat)."

DEVICE="$(readlink -f -- "$DEVICE")"
[[ -b "$DEVICE" ]] || die "$DEVICE no es un dispositivo de bloques."
[[ "$(lsblk --noheadings --raw --nodeps --output TYPE "$DEVICE")" == "disk" ]] || die "Indica el disco completo, no una partición."
[[ "$(lsblk --noheadings --raw --nodeps --output RM "$DEVICE")" == "1" ]] || die "$DEVICE no está marcado como extraíble; se rechaza por seguridad."
[[ "$(lsblk --noheadings --raw --nodeps --output TRAN "$DEVICE")" == "usb" ]] || die "$DEVICE no está conectado por USB; se rechaza por seguridad."
DEVICE_SIZE_BYTES="$(lsblk --bytes --noheadings --raw --nodeps --output SIZE "$DEVICE" | tr -d '[:space:]')"
[[ "$DEVICE_SIZE_BYTES" =~ ^[0-9]+$ && "$DEVICE_SIZE_BYTES" -ge "$MIN_USB_BYTES" ]] || die "$DEVICE debe tener al menos 4 GiB para usar el método HFS."
[[ -f "$EFI_SOURCE/BOOT/BOOTx64.efi" ]] || die "No encuentro $EFI_SOURCE/BOOT/BOOTx64.efi"
[[ -f "$EFI_SOURCE/OC/OpenCore.efi" ]] || die "No encuentro $EFI_SOURCE/OC/OpenCore.efi"
[[ -f "$EFI_SOURCE/OC/config.plist" ]] || die "No encuentro $EFI_SOURCE/OC/config.plist"
[[ -f "$MACRECOVERY_DIR/macrecovery.py" ]] || die "No encuentro macrecovery.py en: $MACRECOVERY_DIR"

if is_mounted; then
    die "$DEVICE o una de sus particiones está montada. Desmóntala o arranca desde otro medio antes de continuar."
fi

case "$DEVICE" in
    *[0-9])
        EFI_PARTITION="${DEVICE}p1"
        RECOVERY_PARTITION="${DEVICE}p2"
        ;;
    *)
        EFI_PARTITION="${DEVICE}1"
        RECOVERY_PARTITION="${DEVICE}2"
        ;;
esac

printf '\nEl siguiente disco se BORRARÁ por completo:\n\n'
lsblk --paths --output NAME,RM,SIZE,MODEL,TRAN,FSTYPE,LABEL,MOUNTPOINTS "$DEVICE"
printf '\nSe instalarán macOS Recovery y el EFI de este repositorio.\n'
printf 'macOS Recovery and this repository EFI will be installed.\n'
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

find_hfs_partition_index

printf '\nCreando GPT, FAT32 OPENCORE y partición HFS Recovery en %s...\n' "$DEVICE"
sgdisk --zap-all "$DEVICE"
sgdisk --clear \
    --new=1:1MiB:+512MiB --typecode=1:0700 --change-name=1:OPENCORE \
    --new=2:0:0 --typecode=2:AF00 --change-name=2:'macOS Recovery' \
    "$DEVICE"
sync

if command -v partprobe >/dev/null 2>&1; then
    partprobe "$DEVICE"
fi
if command -v udevadm >/dev/null 2>&1; then
    udevadm settle
fi
wait_for_partition "$EFI_PARTITION"
wait_for_partition "$RECOVERY_PARTITION"

"$FAT_FORMATTER" -F 32 -n OPENCORE "$EFI_PARTITION"

MOUNT_DIR="$(mktemp -d /tmp/opencore-macos-usb.XXXXXX)"
trap cleanup EXIT INT TERM
mount "$EFI_PARTITION" "$MOUNT_DIR"

printf 'Copiando EFI y extrayendo la partición HFS de Recovery...\n'
mkdir -p "$MOUNT_DIR/EFI"
cp -R "$EFI_SOURCE/." "$MOUNT_DIR/EFI/"
sync

[[ -f "$MOUNT_DIR/EFI/BOOT/BOOTx64.efi" ]] || die "No se copió BOOTx64.efi."
[[ -f "$MOUNT_DIR/EFI/OC/config.plist" ]] || die "No se copió config.plist."

umount "$MOUNT_DIR"
rmdir "$MOUNT_DIR"
MOUNT_DIR=""
trap - EXIT INT TERM

printf 'Extrayendo Recovery (partición %s de la imagen) a %s...\n' "$RECOVERY_PARTITION_INDEX" "$RECOVERY_PARTITION"
extract_hfs_recovery
verify_hfs_recovery
sync

printf '\nUSB preparado correctamente: EFI en %s y Recovery HFS verificada en %s.\n' "$EFI_PARTITION" "$RECOVERY_PARTITION"
printf 'Expúlsalo de forma segura y arranca desde la entrada UEFI del USB.\n'
