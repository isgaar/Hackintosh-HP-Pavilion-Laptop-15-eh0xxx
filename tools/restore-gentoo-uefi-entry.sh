#!/usr/bin/env bash
# Registra de nuevo systemd-boot o GRUB de Gentoo en la NVRAM UEFI.
# No modifica el ESP, el cargador ni ninguna partición.

set -Eeuo pipefail

ESP_MOUNT="/boot/efi"
LOADER=""
LABEL="Gentoo Linux"

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Uso / Usage:
  sudo ./tools/restore-gentoo-uefi-entry.sh [--esp /boot/efi] [--loader '\EFI\systemd\systemd-bootx64.efi'] [--label 'Gentoo Linux']

Registra (o vuelve a priorizar) el cargador EFI de Gentoo en la NVRAM UEFI.
No instala, copia, borra ni formatea archivos o particiones. Debe ejecutarse
desde Gentoo iniciado en modo UEFI, con el ESP interno montado.

Opciones / Options:
  --esp RUTA       Punto de montaje del ESP. Predeterminado: /boot/efi.
  --loader RUTA    Ruta UEFI dentro del ESP. Debe comenzar con '\'. Si se
                    omite, se detecta systemd-boot y después GRUB de Gentoo.
  --label TEXTO    Nombre que aparecerá en el firmware. Predeterminado:
                    Gentoo Linux.
  -h, --help       Muestra esta ayuda / Show this help.

Ejemplo tras usar Reset NVRAM / Example after Reset NVRAM:
  sudo ./tools/restore-gentoo-uefi-entry.sh

Para un cargador personalizado / For a custom loader:
  sudo ./tools/restore-gentoo-uefi-entry.sh \
    --loader '\EFI\gentoo\grubx64.efi'
EOF
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Falta el comando requerido: $1"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --esp)
            [[ $# -ge 2 ]] || die "--esp requiere una ruta."
            ESP_MOUNT="$2"
            shift 2
            ;;
        --loader)
            [[ $# -ge 2 ]] || die "--loader requiere una ruta."
            LOADER="$2"
            shift 2
            ;;
        --label)
            [[ $# -ge 2 && -n "$2" ]] || die "--label requiere un texto no vacío."
            LABEL="$2"
            shift 2
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
[[ -d /sys/firmware/efi/efivars ]] || die "El sistema no se inició en modo UEFI o efivarfs no está disponible."
require_command efibootmgr
require_command findmnt
require_command lsblk

ESP_MOUNT="$(readlink -f -- "$ESP_MOUNT")"
findmnt --target "$ESP_MOUNT" >/dev/null 2>&1 || die "El ESP no está montado en $ESP_MOUNT. Móntalo y vuelve a ejecutar el script."

ESP_DEVICE="$(findmnt --noheadings --output SOURCE --target "$ESP_MOUNT" | head -n1)"
[[ -b "$ESP_DEVICE" ]] || die "No se pudo determinar el dispositivo del ESP montado en $ESP_MOUNT."
[[ "$(lsblk --noheadings --raw --output FSTYPE "$ESP_DEVICE" | head -n1)" == "vfat" ]] || die "$ESP_DEVICE no parece ser una partición EFI FAT32."

if [[ -z "$LOADER" ]]; then
    for candidate in \
        '\EFI\systemd\systemd-bootx64.efi' \
        '\EFI\gentoo\grubx64.efi' \
        '\EFI\Gentoo\grubx64.efi'; do
        host_path="$ESP_MOUNT/${candidate#\\}"
        host_path="${host_path//\\//}"
        if [[ -f "$host_path" ]]; then
            LOADER="$candidate"
            break
        fi
    done
fi

[[ "$LOADER" == \\* ]] || die "La ruta --loader debe comenzar con '\\', por ejemplo \\EFI\\systemd\\systemd-bootx64.efi."
LOADER_HOST="$ESP_MOUNT/${LOADER#\\}"
LOADER_HOST="${LOADER_HOST//\\//}"
[[ -f "$LOADER_HOST" ]] || {
    printf 'Cargadores EFI disponibles en %s:\n' "$ESP_MOUNT" >&2
    find "$ESP_MOUNT/EFI" -type f -iname '*.efi' -printf '  /%P\n' 2>/dev/null >&2 || true
    die "No existe el cargador solicitado: $LOADER"
}

DISK_NAME="$(lsblk --noheadings --raw --output PKNAME "$ESP_DEVICE" | head -n1)"
PARTITION_NUMBER="$(lsblk --noheadings --raw --output PARTN "$ESP_DEVICE" | head -n1)"
[[ -n "$DISK_NAME" && "$PARTITION_NUMBER" =~ ^[0-9]+$ ]] || die "No se pudo obtener el disco y número de partición de $ESP_DEVICE."
DISK="/dev/$DISK_NAME"

# Reutilizar una entrada del mismo nombre evita crear duplicados al ejecutar el
# script más de una vez. Tras Reset NVRAM no habrá ninguna y se creará una.
EXISTING_ID="$(efibootmgr | awk -v label="$LABEL" '
    $0 ~ /^Boot[0-9A-Fa-f]{4}/ {
        id = substr($1, 5, 4)
        sub(/^Boot[0-9A-Fa-f]{4}\*?[[:space:]]*/, "")
        if ($0 == label) { print toupper(id); exit }
    }
')"

if [[ -n "$EXISTING_ID" ]]; then
    BOOT_ID="$EXISTING_ID"
    printf 'Se reutilizará la entrada UEFI existente Boot%s: %s\n' "$BOOT_ID" "$LABEL"
else
    printf 'Registrando %s en %s (partición %s): %s\n' "$LABEL" "$DISK" "$PARTITION_NUMBER" "$LOADER"
    efibootmgr --create --disk "$DISK" --part "$PARTITION_NUMBER" --label "$LABEL" --loader "$LOADER"
    BOOT_ID="$(efibootmgr | awk -v label="$LABEL" '
        $0 ~ /^Boot[0-9A-Fa-f]{4}/ {
            id = substr($1, 5, 4)
            sub(/^Boot[0-9A-Fa-f]{4}\*?[[:space:]]*/, "")
            if ($0 == label) { result = toupper(id) }
        }
        END { print result }
    ')"
    [[ -n "$BOOT_ID" ]] || die "La entrada se creó, pero no se pudo localizar en la NVRAM. Revisa: efibootmgr -v"
fi

CURRENT_ORDER="$(efibootmgr | awk -F': ' '/^BootOrder:/ { print $2 }')"
NEW_ORDER="$BOOT_ID"
IFS=',' read -r -a order_items <<< "$CURRENT_ORDER"
for item in "${order_items[@]}"; do
    item="${item^^}"
    [[ -n "$item" && "$item" != "$BOOT_ID" ]] && NEW_ORDER+=",$item"
done

efibootmgr --bootorder "$NEW_ORDER"
printf '\nListo. Boot%s (%s) quedó primero en BootOrder.\n' "$BOOT_ID" "$LABEL"
printf 'Esto solo reconstruye la entrada de NVRAM; no modifica el cargador EFI.\n'
efibootmgr | sed -n '1,20p'
