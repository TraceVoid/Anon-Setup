#!/usr/bin/env bash
#
# ==============================================================================
# ANON-SETUP ENHANCED v2.0
# ==============================================================================
# Script de anonimización avanzado para máquinas virtuales
# 
# Autor: TraceVoid
# Licencia: GPLv3
# Repositorio: https://github.com/TraceVoid/Anon-Setup
#
# ADVERTENCIA: Solo para uso legítimo en entornos autorizados
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONSTANTES Y CONFIGURACIÓN INICIAL
# ==============================================================================

readonly VERSION="2.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOGFILE="/var/log/anon-setup.log"
readonly BACKUP_DIR="/var/backups/anon-setup"
readonly CONFIG_FILE="/etc/anon-setup.conf"
readonly REPORT_FILE="/var/log/anon-setup-report.txt"
readonly BROWSER_SCRIPT="/usr/local/bin/firefox-anon.sh"

# Redireccionar output a log
exec 1>>"${LOGFILE}" 2>&1

echo "=== anon-setup v${VERSION}: $(date) ==="

# ==============================================================================
# VARIABLES GLOBALES
# ==============================================================================

# Flags de argumentos
VERBOSE=0
QUIET=0
RESTORE=0
SKIP_VPN_CHECK=0

# Variables de configuración (valores por defecto)
MAC_PREFIX="${MAC_PREFIX:-}"
DHCP_WAIT="${DHCP_WAIT:-3}"
CHANGE_HOSTNAME="${CHANGE_HOSTNAME:-1}"
CHANGE_TIMEZONE="${CHANGE_TIMEZONE:-1}"
BLOCK_IPV6="${BLOCK_IPV6:-1}"
CLEAN_LOGS="${CLEAN_LOGS:-1}"
REQUIRE_VPN="${REQUIRE_VPN:-0}"

# Variables de sistema (se inicializan después)
OUT_IF=""
IF_TYPE="unknown"
GW_IP=""
OLD_MAC=""
NEW_MAC=""
DNS_TEST=""
PUBLIC_IP="N/A"

# Lista de servicios de VM a deshabilitar
declare -a VM_SERVICES=(
  "vboxservice"
  "vboxadd-service"
  "open-vm-tools"
  "vmtoolsd"
  "vmware-tools"
  "qemu-guest-agent"
  "virtualbox-guest-utils"
)

# Lista de timezones para aleatorizar
declare -a TIMEZONES=(
  "UTC"
  "America/New_York"
  "America/Los_Angeles"
  "America/Chicago"
  "Europe/London"
  "Europe/Paris"
  "Europe/Berlin"
  "Asia/Tokyo"
  "Asia/Shanghai"
  "Australia/Sydney"
)

# ==============================================================================
# FUNCIONES AUXILIARES - LOGGING Y NOTIFICACIONES
# ==============================================================================

log_info() {
  [[ $QUIET -eq 0 ]] && echo "[INFO] $*"
}

log_verbose() {
  [[ $VERBOSE -eq 1 ]] && echo "[VERBOSE] $*"
}

log_error() {
  echo "[ERROR] $*" >&2
}

log_success() {
  [[ $QUIET -eq 0 ]] && echo "[SUCCESS] $*"
}

notify_user() {
  if command -v notify-send >/dev/null 2>&1 && [ -n "${SUDO_USER-}" ]; then
    sudo -u "${SUDO_USER}" DISPLAY=:0 notify-send "Anon-Setup" "$1" 2>/dev/null || true
  fi
}

# ==============================================================================
# FUNCIONES AUXILIARES - VALIDACIÓN Y UTILIDADES
# ==============================================================================

check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    log_error "Este script debe ejecutarse como root."
    echo "Uso: sudo $SCRIPT_NAME [opciones]"
    exit 1
  fi
}

show_help() {
  cat << EOF
Anon-Setup Enhanced v${VERSION}
Script de anonimización avanzado para máquinas virtuales

USO:
  sudo $SCRIPT_NAME [OPCIONES]

OPCIONES:
  -v, --verbose          Modo verbose (información detallada)
  -q, --quiet            Modo silencioso (solo errores)
  -r, --restore          Restaurar configuración original
  --skip-vpn-check       Omitir verificación de VPN
  -h, --help             Mostrar esta ayuda

EJEMPLOS:
  sudo $SCRIPT_NAME                    # Ejecución estándar
  sudo $SCRIPT_NAME -v                 # Con información detallada
  sudo $SCRIPT_NAME --restore          # Restaurar configuración
  sudo $SCRIPT_NAME --skip-vpn-check   # Ejecutar sin VPN

ARCHIVOS:
  Configuración: ${CONFIG_FILE}
  Logs:         ${LOGFILE}
  Reporte:      ${REPORT_FILE}
  Backup:       ${BACKUP_DIR}

MÁS INFORMACIÓN:
  https://github.com/TraceVoid/Anon-Setup
EOF
  exit 0
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -v|--verbose)
        VERBOSE=1
        shift
        ;;
      -q|--quiet)
        QUIET=1
        shift
        ;;
      -r|--restore)
        RESTORE=1
        shift
        ;;
      --skip-vpn-check)
        SKIP_VPN_CHECK=1
        shift
        ;;
      -h|--help)
        show_help
        ;;
      *)
        log_error "Opción desconocida: $1"
        echo "Use '$SCRIPT_NAME --help' para ver las opciones disponibles."
        exit 1
        ;;
    esac
  done
}

load_config() {
  if [ -f "${CONFIG_FILE}" ]; then
    log_verbose "Cargando configuración desde ${CONFIG_FILE}"
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
  else
    log_verbose "No se encontró archivo de configuración, usando valores por defecto"
  fi
}

# ==============================================================================
# FUNCIONES DE BACKUP Y RESTAURACIÓN
# ==============================================================================

create_backup() {
  log_info "Creando backup de configuración previa..."
  mkdir -p "${BACKUP_DIR}"
  
  # Backup de configuraciones del sistema
  cp /etc/hostname "${BACKUP_DIR}/hostname.bak" 2>/dev/null || true
  cp /etc/resolv.conf "${BACKUP_DIR}/resolv.conf.bak" 2>/dev/null || true
  cp /etc/machine-id "${BACKUP_DIR}/machine-id.bak" 2>/dev/null || true
  cp /etc/timezone "${BACKUP_DIR}/timezone.bak" 2>/dev/null || true
  
  # Guardar MAC original
  if [ -n "${OUT_IF}" ]; then
    cat /sys/class/net/"${OUT_IF}"/address > "${BACKUP_DIR}/mac_${OUT_IF}.bak" 2>/dev/null || true
  fi
  
  # Guardar reglas iptables
  iptables-save > "${BACKUP_DIR}/iptables.bak" 2>/dev/null || true
  ip6tables-save > "${BACKUP_DIR}/ip6tables.bak" 2>/dev/null || true
  
  # Guardar parámetros sysctl
  sysctl -a > "${BACKUP_DIR}/sysctl.bak" 2>/dev/null || true
  
  log_verbose "Backup completado en ${BACKUP_DIR}"
}

restore_backup() {
  log_info "Restaurando configuración previa..."
  
  if [ ! -d "${BACKUP_DIR}" ]; then
    log_error "No existe directorio de backup: ${BACKUP_DIR}"
    exit 1
  fi
  
  # Restaurar hostname
  if [ -f "${BACKUP_DIR}/hostname.bak" ]; then
    cp "${BACKUP_DIR}/hostname.bak" /etc/hostname
    hostname "$(cat /etc/hostname)"
    log_verbose "✓ Hostname restaurado"
  fi
  
  # Restaurar resolv.conf
  if [ -f "${BACKUP_DIR}/resolv.conf.bak" ]; then
    cp "${BACKUP_DIR}/resolv.conf.bak" /etc/resolv.conf
    log_verbose "✓ DNS restaurado"
  fi
  
  # Restaurar machine-id
  if [ -f "${BACKUP_DIR}/machine-id.bak" ]; then
    cp "${BACKUP_DIR}/machine-id.bak" /etc/machine-id
    log_verbose "✓ Machine-ID restaurado"
  fi
  
  # Restaurar timezone
  if [ -f "${BACKUP_DIR}/timezone.bak" ]; then
    cp "${BACKUP_DIR}/timezone.bak" /etc/timezone
    ln -sf "/usr/share/zoneinfo/$(cat /etc/timezone)" /etc/localtime
    log_verbose "✓ Timezone restaurado"
  fi
  
  # Restaurar iptables
  if [ -f "${BACKUP_DIR}/iptables.bak" ]; then
    iptables-restore < "${BACKUP_DIR}/iptables.bak"
    log_verbose "✓ Reglas iptables restauradas"
  fi
  
  if [ -f "${BACKUP_DIR}/ip6tables.bak" ]; then
    ip6tables-restore < "${BACKUP_DIR}/ip6tables.bak"
    log_verbose "✓ Reglas ip6tables restauradas"
  fi
  
  # Re-habilitar IPv6 si estaba activo
  sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null 2>&1 || true
  
  log_success "Restauración completada"
  log_info "Se recomienda reiniciar el sistema para aplicar todos los cambios"
  
  notify_user "✅ Configuración restaurada"
  exit 0
}

# ==============================================================================
# FUNCIONES DE DETECCIÓN DE SISTEMA
# ==============================================================================

detect_network_interface() {
  log_info "Detectando interfaz de red..."
  
  # Método 1: Usando ip route get
  OUT_IF=$(ip route get 8.8.8.8 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
  
  # Método 2: Fallback a ruta por defecto
  if [ -z "${OUT_IF}" ]; then
    OUT_IF=$(ip route | awk '/default/ {print $5; exit}')
  fi
  
  # Validación
  if [ -z "${OUT_IF}" ]; then
    log_error "No se pudo detectar interfaz de salida"
    log_error "Interfaces disponibles:"
    ip link show | grep -E "^[0-9]+:" | awk '{print $2}' | sed 's/:$//' >&2
    exit 1
  fi
  
  log_info "Interfaz detectada: ${OUT_IF}"
  log_verbose "Validando interfaz ${OUT_IF}..."
  
  if ! ip link show "${OUT_IF}" >/dev/null 2>&1; then
    log_error "La interfaz ${OUT_IF} no existe o no es accesible"
    exit 1
  fi
}

detect_interface_type() {
  log_verbose "Detectando tipo de interfaz..."
  
  if [ -d "/sys/class/net/${OUT_IF}/wireless" ]; then
    IF_TYPE="wifi"
  elif [ -f "/sys/class/net/${OUT_IF}/device/class" ]; then
    IF_TYPE="ethernet"
  else
    IF_TYPE="unknown"
  fi
  
  log_info "Tipo de interfaz: ${IF_TYPE}"
}

detect_gateway() {
  log_info "Detectando gateway..."
  
  GW_IP=$(ip route | awk '/default/ {print $3; exit}')
  
  if [ -z "${GW_IP}" ]; then
    log_error "No se pudo determinar la IP del gateway por defecto"
    GW_IP=""
  else
    log_info "Gateway detectado: ${GW_IP}"
  fi
}

# ==============================================================================
# FUNCIÓN DE VERIFICACIÓN DE VPN
# ==============================================================================

check_vpn_connection() {
  if [ $REQUIRE_VPN -eq 1 ] && [ $SKIP_VPN_CHECK -eq 0 ]; then
    log_info "Verificando conexión VPN..."
    local VPN_ACTIVE=0
    
    # Verificar interfaces VPN comunes
    local vpn_interfaces=("tun0" "tap0" "wg0" "ppp0" "utun" "ipsec")
    
    for vpn_if in "${vpn_interfaces[@]}"; do
      if ip link show "$vpn_if" >/dev/null 2>&1; then
        VPN_ACTIVE=1
        log_info "✓ VPN detectada en interfaz: $vpn_if"
        break
      fi
    done
    
    if [ $VPN_ACTIVE -eq 0 ]; then
      log_error "No se detectó conexión VPN activa"
      log_error "Opciones:"
      log_error "  1. Conecta a una VPN antes de ejecutar"
      log_error "  2. Usa --skip-vpn-check para omitir esta verificación"
      log_error "  3. Desactiva REQUIRE_VPN en ${CONFIG_FILE}"
      notify_user "⚠️ VPN no detectada - Anonimización cancelada"
      exit 1
    fi
  else
    log_verbose "Verificación de VPN omitida"
  fi
}

# ==============================================================================
# FUNCIÓN DE INSTALACIÓN DE DEPENDENCIAS
# ==============================================================================

install_dependencies() {
  log_info "Verificando dependencias..."
  
  local PACKAGES_TO_INSTALL=""
  
  # Verificar macchanger
  if ! command -v macchanger >/dev/null 2>&1; then
    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL macchanger"
    log_verbose "macchanger no encontrado, se instalará"
  fi
  
  if [ -n "$PACKAGES_TO_INSTALL" ]; then
    log_info "Instalando paquetes faltantes:$PACKAGES_TO_INSTALL"
    export DEBIAN_FRONTEND=noninteractive
    
    if apt-get update -qq 2>/dev/null && apt-get install -y $PACKAGES_TO_INSTALL 2>/dev/null; then
      log_success "Dependencias instaladas correctamente"
    else
      log_error "Fallo al instalar dependencias. Continuando de todas formas..."
    fi
  else
    log_verbose "Todas las dependencias están instaladas"
  fi
}

# ==============================================================================
# FUNCIÓN DE CAMBIO DE TIMEZONE
# ==============================================================================

change_timezone() {
  if [ $CHANGE_TIMEZONE -ne 1 ]; then
    log_verbose "Cambio de timezone desactivado"
    return 0
  fi
  
  log_info "Cambiando timezone..."
  
  # Seleccionar timezone aleatorio
  local RANDOM_TZ=${TIMEZONES[$RANDOM % ${#TIMEZONES[@]}]}
  
  if [ -f "/usr/share/zoneinfo/${RANDOM_TZ}" ]; then
    ln -sf "/usr/share/zoneinfo/${RANDOM_TZ}" /etc/localtime
    echo "${RANDOM_TZ}" > /etc/timezone
    log_info "Timezone cambiado a: ${RANDOM_TZ}"
    log_success "Timezone actualizado"
  else
    log_error "Timezone ${RANDOM_TZ} no encontrado"
    return 1
  fi
}

# ==============================================================================
# FUNCIÓN DE REGENERACIÓN DE MACHINE-ID
# ==============================================================================

regenerate_machine_id() {
  log_info "Regenerando machine-id..."
  
  # Remover machine-id existente
  [ -f /etc/machine-id ] && rm -f /etc/machine-id
  [ -f /var/lib/dbus/machine-id ] && rm -f /var/lib/dbus/machine-id
  
  # Regenerar con systemd si está disponible
  if command -v systemd-machine-id-setup >/dev/null 2>&1; then
    if systemd-machine-id-setup 2>/dev/null; then
      log_verbose "✓ Machine-ID regenerado con systemd"
    else
      log_error "systemd-machine-id-setup falló"
      generate_machine_id_fallback
    fi
  else
    generate_machine_id_fallback
  fi
  
  log_success "Machine-ID regenerado"
}

generate_machine_id_fallback() {
  log_verbose "Usando método alternativo para machine-id..."
  
  if command -v dbus-uuidgen >/dev/null 2>&1; then
    dbus-uuidgen > /etc/machine-id 2>/dev/null || \
      log_error "dbus-uuidgen falló"
  else
    # Generar UUID manualmente
    cat /proc/sys/kernel/random/uuid | tr -d '-' > /etc/machine-id 2>/dev/null || \
      log_error "Generación manual de machine-id falló"
  fi
}

# ==============================================================================
# FUNCIÓN DE LIMPIEZA DE LOGS Y CACHE
# ==============================================================================

clean_system_traces() {
  if [ $CLEAN_LOGS -ne 1 ]; then
    log_verbose "Limpieza de logs desactivada"
    return 0
  fi
  
  log_info "Limpiando huellas del sistema..."
  
  clean_user_histories
  clean_system_logs
  clean_browser_cache
  clean_temporary_files
  clean_package_cache
  
  log_success "Limpieza completada"
}

clean_user_histories() {
  log_verbose "Limpiando historiales de usuarios..."
  
  local hist_files=(
    ".bash_history"
    ".zsh_history"
    ".python_history"
    ".mysql_history"
    ".lesshst"
    ".viminfo"
    ".nano_history"
  )
  
  for user_home in /home/* /root; do
    if [ -d "$user_home" ]; then
      for hist_file in "${hist_files[@]}"; do
        if [ -f "$user_home/$hist_file" ]; then
          : > "$user_home/$hist_file" 2>/dev/null || true
          log_verbose "✓ Limpiado: $user_home/$hist_file"
        fi
      done
      
      # Limpiar thumbnails
      if [ -d "$user_home/.cache/thumbnails" ]; then
        rm -rf "$user_home/.cache/thumbnails"/* 2>/dev/null || true
        log_verbose "✓ Thumbnails eliminados: $user_home"
      fi
    fi
  done
  
  # Limpiar historial actual de shell
  history -cw 2>/dev/null || true
}

clean_system_logs() {
  log_verbose "Limpiando logs del sistema..."
  
  # Rotar y limpiar journal
  if command -v journalctl >/dev/null 2>&1; then
    journalctl --rotate 2>/dev/null || true
    journalctl --vacuum-time=1s 2>/dev/null || true
    log_verbose "✓ Journal limpiado"
  fi
  
  # Limpiar logs específicos
  local log_files=(
    "/var/log/auth.log"
    "/var/log/syslog"
    "/var/log/kern.log"
    "/var/log/daemon.log"
    "/var/log/user.log"
  )
  
  for log_file in "${log_files[@]}"; do
    if [ -f "$log_file" ]; then
      : > "$log_file" 2>/dev/null || true
      log_verbose "✓ Limpiado: $log_file"
    fi
  done
}

clean_browser_cache() {
  log_verbose "Limpiando cache de navegadores..."
  
  for user_home in /home/* /root; do
    if [ -d "$user_home" ]; then
      # Firefox
      if [ -d "$user_home/.mozilla" ]; then
        find "$user_home/.mozilla" -name "*.sqlite" -delete 2>/dev/null || true
        find "$user_home/.mozilla" -name "cache*" -type d -exec rm -rf {} + 2>/dev/null || true
        log_verbose "✓ Cache Firefox limpiado: $user_home"
      fi
      
      # Chrome/Chromium
      for browser_dir in .cache/google-chrome .cache/chromium; do
        if [ -d "$user_home/$browser_dir" ]; then
          rm -rf "$user_home/$browser_dir"/* 2>/dev/null || true
          log_verbose "✓ Cache Chrome/Chromium limpiado: $user_home"
        fi
      done
    fi
  done
}

clean_temporary_files() {
  log_verbose "Limpiando archivos temporales..."
  
  # Limpiar /tmp (archivos antiguos)
  find /tmp -type f -atime +1 -delete 2>/dev/null || true
  
  # Limpiar /var/tmp (archivos muy antiguos)
  find /var/tmp -type f -atime +7 -delete 2>/dev/null || true
  
  log_verbose "✓ Archivos temporales limpiados"
}

clean_package_cache() {
  log_verbose "Limpiando cache de paquetes..."
  
  if command -v apt-get >/dev/null 2>&1; then
    apt-get clean 2>/dev/null || true
    log_verbose "✓ Cache APT limpiado"
  fi
  
  if command -v yum >/dev/null 2>&1; then
    yum clean all 2>/dev/null || true
    log_verbose "✓ Cache YUM limpiado"
  fi
}

# ==============================================================================
# FUNCIÓN DE LIMPIEZA DE SWAP
# ==============================================================================

clean_swap() {
  log_info "Limpiando swap..."
  
  if [ -n "$(swapon --show)" ]; then
    swapoff -a 2>/dev/null || true
    sleep 1
    swapon -a 2>/dev/null || true
    log_success "Swap limpiado"
  else
    log_verbose "No hay swap activo"
  fi
}

# ==============================================================================
# FUNCIÓN DE DESACTIVACIÓN DE SERVICIOS DE VM
# ==============================================================================

disable_vm_services() {
  log_info "Deshabilitando servicios de virtualización..."
  
  local disabled_count=0
  
  for svc in "${VM_SERVICES[@]}"; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}"; then
      if systemctl disable --now "${svc}" 2>/dev/null; then
        log_verbose "✓ Deshabilitado: ${svc}"
        ((disabled_count++))
      fi
    fi
  done
  
  # Deshabilitar portapapeles compartido de VirtualBox
  if command -v VBoxControl >/dev/null 2>&1; then
    VBoxControl guestproperty set /VirtualBox/GuestAdd/SharedFolders/MountDir "" 2>/dev/null || true
    log_verbose "✓ Configuración VirtualBox ajustada"
  fi
  
  if [ $disabled_count -gt 0 ]; then
    log_success "Servicios de VM deshabilitados: $disabled_count"
  else
    log_verbose "No se encontraron servicios de VM para deshabilitar"
  fi
}

# ==============================================================================
# FUNCIÓN DE HARDENING DE NAVEGADORES
# ==============================================================================

create_browser_hardening_script() {
  log_info "Generando script de hardening para Firefox..."
  
  cat > "${BROWSER_SCRIPT}" << 'EOF'
#!/bin/bash
# ==============================================================================
# Firefox Hardening Script - Generado por Anon-Setup
# ==============================================================================

FIREFOX_PROFILES="${HOME}/.mozilla/firefox"

if [ ! -d "${FIREFOX_PROFILES}" ]; then
  echo "No se encontraron perfiles de Firefox"
  exit 0
fi

echo "=== Configurando Firefox para mayor privacidad ==="

for profile in "${FIREFOX_PROFILES}"/*.default*; do
  if [ -d "$profile" ]; then
    PREFS="${profile}/user.js"
    
    echo "Configurando perfil: $(basename "$profile")"
    
    cat >> "${PREFS}" << 'PREFS'
// ==============================================================================
// CONFIGURACIÓN DE PRIVACIDAD Y SEGURIDAD
// Generado automáticamente por Anon-Setup
// ==============================================================================

// Deshabilitar WebRTC (previene fugas de IP)
user_pref("media.peerconnection.enabled", false);
user_pref("media.navigator.enabled", false);
user_pref("media.peerconnection.ice.default_address_only", true);
user_pref("media.peerconnection.ice.no_host", true);

// Resistencia a fingerprinting
user_pref("privacy.resistFingerprinting", true);
user_pref("privacy.trackingprotection.fingerprinting.enabled", true);
user_pref("privacy.trackingprotection.cryptomining.enabled", true);
user_pref("privacy.trackingprotection.enabled", true);
user_pref("privacy.trackingprotection.pbmode.enabled", true);

// Deshabilitar telemetría
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);

// DNS sobre HTTPS
user_pref("network.trr.mode", 2);
user_pref("network.trr.uri", "https://mozilla.cloudflare-dns.com/dns-query");

// Deshabilitar geolocalización
user_pref("geo.enabled", false);
user_pref("geo.provider.network.url", "");

// Cookies y rastreadores
user_pref("network.cookie.cookieBehavior", 1);
user_pref("network.cookie.lifetimePolicy", 2);
user_pref("privacy.firstparty.isolate", true);

// Deshabilitar prefetch y predicción
user_pref("network.dns.disablePrefetch", true);
user_pref("network.prefetch-next", false);
user_pref("network.predictor.enabled", false);

// Deshabilitar WebGL (fingerprinting)
user_pref("webgl.disabled", true);

// Canvas fingerprinting
user_pref("privacy.resistFingerprinting.block_mozAddonManager", true);

// Battery API
user_pref("dom.battery.enabled", false);

// Beacon API
user_pref("beacon.enabled", false);

// Clipboard events
user_pref("dom.event.clipboardevents.enabled", false);

PREFS
    
    echo "✓ Perfil configurado: $(basename "$profile")"
  fi
done

echo "=== Hardening de Firefox completado ==="
echo "Reinicia Firefox para aplicar los cambios"
EOF
  
  chmod +x "${BROWSER_SCRIPT}" 2>/dev/null || true
  log_verbose "✓ Script creado en ${BROWSER_SCRIPT}"
  
  # Ejecutar para el usuario actual si existe
  if [ -n "${SUDO_USER-}" ]; then
    log_verbose "Ejecutando hardening de Firefox para ${SUDO_USER}..."
    sudo -u "${SUDO_USER}" bash "${BROWSER_SCRIPT}" 2>/dev/null || true
  fi
  
  log_success "Script de hardening generado"
}

# ==============================================================================
# FUNCIÓN DE VERIFICACIÓN DEL SISTEMA
# ==============================================================================

verify_changes() {
  log_info "Realizando verificaciones finales..."
  
  local all_ok=true
  
  # Verificar DNS
  if command -v dig >/dev/null 2>&1; then
    DNS_TEST=$(dig +short +timeout=3 google.com 2>/dev/null | head -n1)
    if [ -n "$DNS_TEST" ]; then
      log_info "✓ DNS funcional (test: ${DNS_TEST})"
    else
      log_error "✗ DNS no responde"
      all_ok=false
    fi
  else
    log_verbose "dig no disponible, omitiendo test DNS"
  fi
  
  # Verificar IP pública (opcional)
  if command -v curl >/dev/null 2>&1; then
    PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "N/A")
    log_info "IP pública actual: ${PUBLIC_IP}"
  fi
  
  # Verificar cambio de MAC
  if [ "$OLD_MAC" != "$NEW_MAC" ]; then
    log_info "✓ MAC address cambiada correctamente"
  else
    log_error "✗ MAC address no cambió"
    all_ok=false
  fi
  
  # Verificar reglas iptables
  if iptables -L ANON_DNS -n >/dev/null 2>&1; then
    log_info "✓ Reglas iptables aplicadas"
  else
    log_error "✗ Reglas iptables no encontradas"
    all_ok=false
  fi
  
  if $all_ok; then
    log_success "Todas las verificaciones pasaron"
  else
    log_error "Algunas verificaciones fallaron"
  fi
}

# ==============================================================================
# FUNCIÓN DE GENERACIÓN DE REPORTE
# ==============================================================================

generate_report() {
  log_info "Generando reporte..."
  
  cat > "${REPORT_FILE}" << REPORT
==============================================================================
REPORTE DE ANONIMIZACIÓN - ANON-SETUP v${VERSION}
==============================================================================
Fecha: $(date)
Hostname: $(hostname)
==============================================================================

CONFIGURACIÓN DE RED:
  Interfaz:      ${OUT_IF} (${IF_TYPE})
  MAC anterior:  ${OLD_MAC}
  MAC nueva:     ${NEW_MAC}
  Gateway:       ${GW_IP}
  DNS:           ${GW_IP} (forzado)
  
IDENTIFICADORES DEL SISTEMA:
  Hostname:      $(hostname)
  Timezone:      $(cat /etc/timezone 2>/dev/null || echo "N/A")
  Machine-ID:    $(cat /etc/machine-id 2>/dev/null | head -c 8)...
  
VERIFICACIONES:
  Cambio MAC:    $([ "$OLD_MAC" != "$NEW_MAC" ] && echo "✓ OK" || echo "✗ FALLO")
  DNS funcional: $([ -n "$DNS_TEST" ] && echo "✓ OK (${DNS_TEST})" || echo "? No verificado")
  IPv6 bloqueado: $([ $BLOCK_IPV6 -eq 1 ] && echo "✓ Sí" || echo "✗ No")
  IP pública:    ${PUBLIC_IP}
  
CONFIGURACIÓN APLICADA:
  Cambio hostname:     $([ $CHANGE_HOSTNAME -eq 1 ] && echo "✓ Sí" || echo "✗ No")
  Cambio timezone:     $([ $CHANGE_TIMEZONE -eq 1 ] && echo "✓ Sí" || echo "✗ No")
  Bloqueo IPv6:        $([ $BLOCK_IPV6 -eq 1 ] && echo "✓ Sí" || echo "✗ No")
  Limpieza logs:       $([ $CLEAN_LOGS -eq 1 ] && echo "✓ Sí" || echo "✗ No")
  
SERVICIOS VM DESHABILITADOS:
$(for svc in "${VM_SERVICES[@]}"; do
  if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}"; then
    echo "  - ${svc}"
  fi
done)

REGLAS FIREWALL:
$(iptables -L ANON_DNS -n -v 2>/dev/null | head -n 10)

PARÁMETROS KERNEL MODIFICADOS:
  tcp_timestamps:        $(sysctl -n net.ipv4.tcp_timestamps 2>/dev/null || echo "N/A")
  ip_local_port_range:   $(sysctl -n net.ipv4.ip_local_port_range 2>/dev/null || echo "N/A")
  tcp_syncookies:        $(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null || echo "N/A")
  
ARCHIVOS IMPORTANTES:
  Log:           ${LOGFILE}
  Backup:        ${BACKUP_DIR}
  Config:        ${CONFIG_FILE}
  Browser Script: ${BROWSER_SCRIPT}
  
==============================================================================
RECOMENDACIONES POST-ANONIMIZACIÓN:
==============================================================================
1. Reinicia el sistema para asegurar que todos los cambios se apliquen
2. Verifica tu anonimato en: https://ipleak.net
3. Prueba WebRTC leaks en: https://browserleaks.com/webrtc
4. Ejecuta el script de Firefox: ${BROWSER_SCRIPT}
5. Para restaurar: sudo $SCRIPT_NAME --restore

==============================================================================
NOTAS DE SEGURIDAD:
==============================================================================
- Esto NO garantiza anonimato completo
- Usa en conjunto con VPN/Tor para mejor protección
- Algunas redes pueden bloquear MACs aleatorias
- Los cambios son temporales (se pierden al reiniciar sin servicio)

==============================================================================
REPORT
  
  log_info "Reporte generado en: ${REPORT_FILE}"
  
  # Mostrar resumen en pantalla si no está en modo quiet
  if [ $QUIET -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "  ANONIMIZACIÓN COMPLETADA"
    echo "=========================================="
    echo "MAC:      ${OLD_MAC} → ${NEW_MAC}"
    echo "Hostname: $(hostname)"
    echo "Reporte:  ${REPORT_FILE}"
    echo "=========================================="
    echo ""
  fi
}

# ==============================================================================
# FUNCIÓN PRINCIPAL
# ==============================================================================

main() {
  # Parsear argumentos
  parse_arguments "$@"
  
  # Verificar privilegios root
  check_root
  
  # Cargar configuración
  load_config
  
  # Si es restauración, ejecutar y salir
  if [ $RESTORE -eq 1 ]; then
    restore_backup
  fi
  
  # Detectar sistema
  detect_network_interface
  detect_interface_type
  detect_gateway
  
  # Crear backup antes de cualquier cambio
  create_backup
  
  # Verificar VPN si está requerido
  check_vpn_connection
  
  # Instalar dependencias
  install_dependencies
  
  # Aplicar cambios de red
  change_mac_address || log_error "Cambio de MAC falló"
  renew_dhcp || log_error "Renovación DHCP falló"
  configure_dns || log_error "Configuración DNS falló"
  
  # Configurar firewall y kernel
  configure_firewall
  configure_kernel_parameters
  
  # Cambiar identificadores
  change_hostname
  change_timezone
  regenerate_machine_id
  
  # Limpiar huellas
  clean_system_traces
  clean_swap
  
  # Deshabilitar servicios de VM
  disable_vm_services
  
  # Crear script de hardening de navegador
  create_browser_hardening_script
  
  # Verificar cambios
  verify_changes
  
  # Generar reporte
  generate_report
  
  # Notificación final
  notify_user "✅ Anonimización completada"
  
  # Mensaje final
  log_success "=== Anonimización completada exitosamente ==="
  log_info "Se recomienda REINICIAR el sistema para aplicar todos los cambios"
  log_info "Para restaurar la configuración: sudo $SCRIPT_NAME --restore"
  log_info "Ver reporte completo: cat ${REPORT_FILE}"
  
  echo "=== Fin anon-setup: $(date) ==="
}

# ==============================================================================
# PUNTO DE ENTRADA
# ==============================================================================

# Ejecutar función principal con todos los argumentos
main "$@"

exit 0IO DE MAC ADDRESS
# ==============================================================================

change_mac_address() {
  log_info "Cambiando MAC address en ${OUT_IF}..."
  
  # Guardar MAC actual
  OLD_MAC=$(cat /sys/class/net/"${OUT_IF}"/address 2>/dev/null || echo "unknown")
  log_verbose "MAC anterior: ${OLD_MAC}"
  
  # Bajar interfaz
  if ! ip link set "${OUT_IF}" down 2>/dev/null; then
    log_error "Fallo al bajar interfaz ${OUT_IF}"
    return 1
  fi
  
  # Cambiar MAC según configuración
  if [ -n "${MAC_PREFIX}" ]; then
    change_mac_with_prefix
  else
    change_mac_random
  fi
  
  # Subir interfaz
  if ! ip link set "${OUT_IF}" up 2>/dev/null; then
    log_error "Fallo al subir interfaz ${OUT_IF}"
    return 1
  fi
  
  sleep "${DHCP_WAIT}"
  
  # Verificar cambio
  NEW_MAC=$(cat /sys/class/net/"${OUT_IF}"/address 2>/dev/null || echo "unknown")
  log_info "Nueva MAC efectiva: ${NEW_MAC}"
  
  if [ "$OLD_MAC" == "$NEW_MAC" ]; then
    log_error "ADVERTENCIA: La MAC no cambió. Posibles causas:"
    log_error "  - Driver no soporta cambio de MAC"
    log_error "  - Interfaz gestionada por NetworkManager"
    log_error "  - Restricciones del hypervisor"
    notify_user "⚠️ MAC address no cambió"
    return 1
  else
    log_success "MAC cambiada exitosamente"
  fi
  
  return 0
}

change_mac_with_prefix() {
  local PREF=${MAC_PREFIX// /}
  
  # Validar formato del prefijo
  if ! printf '%s' "${PREF}" | grep -Eq '^([0-9A-Fa-f]{2}:){0,2}[0-9A-Fa-f]{2}$'; then
    log_error "Formato de MAC_PREFIX inválido: ${MAC_PREFIX}"
    log_info "Usando macchanger -e (vendor ending) en su lugar"
    macchanger -e "${OUT_IF}" 2>/dev/null || log_error "macchanger falló"
    return
  fi
  
  # Generar resto de la MAC
  IFS=':' read -ra PARTS <<< "${PREF}"
  local COUNT=${#PARTS[@]}
  
  if [ "${COUNT}" -gt 6 ]; then
    log_error "Prefijo demasiado largo (max 6 octetos)"
    macchanger -e "${OUT_IF}" 2>/dev/null || log_error "macchanger falló"
    return
  fi
  
  local NEED=$((6 - COUNT))
  local SUF=""
  
  for i in $(seq 1 ${NEED}); do
    SUF+=":$(printf "%02x" $((RANDOM % 256)))"
  done
  
  local NEW_MAC_ADDR="${PREF}${SUF}"
  NEW_MAC_ADDR=$(echo "${NEW_MAC_ADDR}" | sed 's/::/:/g' | sed 's/^://')
  
  log_verbose "Asignando MAC personalizada: ${NEW_MAC_ADDR}"
  
  if ip link set dev "${OUT_IF}" address "${NEW_MAC_ADDR}" 2>/dev/null; then
    log_verbose "✓ MAC asignada manualmente"
  else
    log_error "Error asignando MAC manualmente"
    log_info "Fallback a macchanger -e"
    macchanger -e "${OUT_IF}" 2>/dev/null || log_error "macchanger falló"
  fi
}

change_mac_random() {
  log_verbose "Usando macchanger -e (vendor ending aleatorio)"
  
  if macchanger -e "${OUT_IF}" 2>/dev/null; then
    log_verbose "✓ MAC cambiada con macchanger"
  else
    log_error "macchanger falló"
    log_info "Intentando método alternativo..."
    
    # Método alternativo: generar MAC manualmente
    local random_mac=$(printf '02:%02x:%02x:%02x:%02x:%02x\n' \
      $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) \
      $((RANDOM % 256)) $((RANDOM % 256)))
    
    ip link set dev "${OUT_IF}" address "${random_mac}" 2>/dev/null || \
      log_error "Método alternativo también falló"
  fi
}

# ==============================================================================
# FUNCIÓN DE RENOVACIÓN DHCP
# ==============================================================================

renew_dhcp() {
  log_info "Renovando configuración de red..."
  
  if [ "$IF_TYPE" == "wifi" ] && command -v nmcli >/dev/null 2>&1; then
    renew_dhcp_nmcli_wifi
  elif command -v dhclient >/dev/null 2>&1; then
    renew_dhcp_dhclient
  elif command -v nmcli >/dev/null 2>&1; then
    renew_dhcp_nmcli
  else
    log_error "No se encontró dhclient ni nmcli"
    log_error "Debes renovar DHCP manualmente"
    return 1
  fi
  
  log_success "Configuración de red renovada"
}

renew_dhcp_nmcli_wifi() {
  log_verbose "Usando NetworkManager para WiFi..."
  
  nmcli device disconnect "${OUT_IF}" 2>/dev/null || true
  sleep 2
  
  if nmcli device connect "${OUT_IF}" 2>/dev/null; then
    log_verbose "✓ Reconexión WiFi exitosa"
  else
    log_error "nmcli reconectar falló"
    return 1
  fi
}

renew_dhcp_dhclient() {
  log_verbose "Usando dhclient..."
  
  dhclient -r "${OUT_IF}" 2>/dev/null || true
  sleep 1
  
  if dhclient "${OUT_IF}" 2>/dev/null; then
    log_verbose "✓ DHCP renovado con dhclient"
  else
    log_error "dhclient falló"
    return 1
  fi
}

renew_dhcp_nmcli() {
  log_verbose "Usando NetworkManager..."
  
  nmcli device disconnect "${OUT_IF}" 2>/dev/null || true
  sleep 1
  
  if nmcli device connect "${OUT_IF}" 2>/dev/null; then
    log_verbose "✓ Reconexión exitosa"
  else
    log_error "nmcli reconectar falló"
    return 1
  fi
}

# ==============================================================================
# FUNCIÓN DE CONFIGURACIÓN DE DNS
# ==============================================================================

configure_dns() {
  if [ -z "${GW_IP}" ]; then
    log_error "No hay gateway detectado, omitiendo configuración DNS"
    return 1
  fi
  
  log_info "Configurando DNS a ${GW_IP}..."
  
  if command -v nmcli >/dev/null 2>&1; then
    configure_dns_networkmanager
  else
    configure_dns_manual
  fi
  
  log_success "DNS configurado"
}

configure_dns_networkmanager() {
  log_verbose "Configurando DNS via NetworkManager..."
  
  local CONN=$(nmcli -t -f NAME,DEVICE connection show --active | \
               awk -F: -v dev="${OUT_IF}" '$0 ~ dev {print $1; exit}')
  
  if [ -n "${CONN}" ]; then
    log_verbose "Conexión NM encontrada: ${CONN}"
    
    if nmcli connection modify "${CONN}" \
       ipv4.dns "${GW_IP}" \
       ipv4.ignore-auto-dns yes 2>/dev/null; then
      log_verbose "✓ DNS configurado en NetworkManager"
    else
      log_error "Fallo al modificar conexión NM"
      configure_dns_manual
      return
    fi
    
    nmcli connection up "${CONN}" 2>/dev/null || \
      log_error "Fallo al activar conexión NM"
  else
    log_verbose "No se encontró conexión NM para ${OUT_IF}"
    configure_dns_manual
  fi
}

configure_dns_manual() {
  log_verbose "Escribiendo /etc/resolv.conf directamente..."
  
  # Verificar si resolv.conf es inmutable
  if lsattr /etc/resolv.conf 2>/dev/null | grep -q '^....i'; then
    log_verbose "Removiendo atributo inmutable de resolv.conf"
    chattr -i /etc/resolv.conf 2>/dev/null || true
  fi
  
  # Escribir configuración DNS
  if cat > /etc/resolv.conf << EOF
nameserver ${GW_IP}
options rotate
options timeout:1
EOF
  then
    log_verbose "✓ /etc/resolv.conf actualizado"
  else
    log_error "No se pudo escribir /etc/resolv.conf"
  fi
}

# ==============================================================================
# FUNCIÓN DE CONFIGURACIÓN DE FIREWALL
# ==============================================================================

configure_firewall() {
  log_info "Configurando reglas de firewall..."
  
  configure_dns_firewall
  
  if [ $BLOCK_IPV6 -eq 1 ]; then
    configure_ipv6_firewall
  fi
  
  log_success "Firewall configurado"
}

configure_dns_firewall() {
  log_verbose "Configurando cadena ANON_DNS..."
  
  # Crear cadena si no existe
  if ! iptables -nL ANON_DNS >/dev/null 2>&1; then
    iptables -N ANON_DNS 2>/dev/null || true
  fi
  
  # Limpiar cadena
  iptables -F ANON_DNS 2>/dev/null || true
  
  # Reglas básicas
  iptables -A ANON_DNS -o lo -j ACCEPT
  iptables -A ANON_DNS -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  
  # Permitir DNS solo al gateway
  if [ -n "${GW_IP}" ]; then
    iptables -A ANON_DNS -d "${GW_IP}" -p udp --dport 53 -j ACCEPT
    iptables -A ANON_DNS -d "${GW_IP}" -p tcp --dport 53 -j ACCEPT
    log_verbose "✓ DNS permitido a gateway: ${GW_IP}"
  fi
  
  # Bloquear resto de DNS
  iptables -A ANON_DNS -p udp --dport 53 -j DROP
  iptables -A ANON_DNS -p tcp --dport 53 -j DROP
  
  # Aplicar cadena a OUTPUT
  if ! iptables -C OUTPUT -j ANON_DNS >/dev/null 2>&1; then
    iptables -A OUTPUT -j ANON_DNS || log_error "No se pudo añadir ANON_DNS a OUTPUT"
  fi
  
  log_verbose "✓ Reglas DNS configuradas"
}

configure_ipv6_firewall() {
  log_verbose "Bloqueando IPv6..."
  
  # Crear cadena IPv6
  if ! ip6tables -nL ANON_IPV6 >/dev/null 2>&1; then
    ip6tables -N ANON_IPV6 2>/dev/null || true
  fi
  
  # Limpiar cadena
  ip6tables -F ANON_IPV6 2>/dev/null || true
  
  # Bloquear todo excepto loopback
  ip6tables -A ANON_IPV6 -o lo -j ACCEPT
  ip6tables -A ANON_IPV6 -j DROP
  
  # Aplicar cadena
  if ! ip6tables -C OUTPUT -j ANON_IPV6 >/dev/null 2>&1; then
    ip6tables -A OUTPUT -j ANON_IPV6 || log_error "No se pudo configurar IPv6"
  fi
  
  # Deshabilitar IPv6 en sysctl
  sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || true
  
  log_verbose "✓ IPv6 bloqueado"
}

# ==============================================================================
# FUNCIÓN DE CONFIGURACIÓN DEL KERNEL
# ==============================================================================

configure_kernel_parameters() {
  log_info "Configurando parámetros del kernel..."
  
  # Deshabilitar ICMP timestamps
  sysctl -w net.ipv4.tcp_timestamps=0 >/dev/null 2>&1 || true
  
  # Randomizar puertos locales
  sysctl -w net.ipv4.ip_local_port_range="15000 65000" >/dev/null 2>&1 || true
  
  # Protección SYN flood
  sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null 2>&1 || true
  
  # Deshabilitar ICMP redirects
  sysctl -w net.ipv4.conf.all.accept_redirects=0 >/dev/null 2>&1 || true
  sysctl -w net.ipv4.conf.all.send_redirects=0 >/dev/null 2>&1 || true
  sysctl -w net.ipv4.conf.default.accept_redirects=0 >/dev/null 2>&1 || true
  sysctl -w net.ipv4.conf.default.send_redirects=0 >/dev/null 2>&1 || true
  
  # Deshabilitar source routing
  sysctl -w net.ipv4.conf.all.accept_source_route=0 >/dev/null 2>&1 || true
  sysctl -w net.ipv4.conf.default.accept_source_route=0 >/dev/null 2>&1 || true
  
  # Protección contra IP spoofing
  sysctl -w net.ipv4.conf.all.rp_filter=1 >/dev/null 2>&1 || true
  sysctl -w net.ipv4.conf.default.rp_filter=1 >/dev/null 2>&1 || true
  
  log_success "Parámetros del kernel configurados"
}

# ==============================================================================
# FUNCIÓN DE CAMBIO DE HOSTNAME
# ==============================================================================

change_hostname() {
  if [ $CHANGE_HOSTNAME -ne 1 ]; then
    log_verbose "Cambio de hostname desactivado"
    return 0
  fi
  
  log_info "Cambiando hostname..."
  
  local NEW_HOSTNAME="host-$(head /dev/urandom | tr -dc a-z0-9 | head -c 8)"
  
  if command -v hostnamectl >/dev/null 2>&1; then
    hostnamectl set-hostname "${NEW_HOSTNAME}" 2>/dev/null || {
      echo "${NEW_HOSTNAME}" > /etc/hostname
      hostname "${NEW_HOSTNAME}"
    }
  else
    echo "${NEW_HOSTNAME}" > /etc/hostname
    hostname "${NEW_HOSTNAME}"
  fi
  
  log_info "Nuevo hostname: ${NEW_HOSTNAME}"
  log_success "Hostname cambiado"
}
