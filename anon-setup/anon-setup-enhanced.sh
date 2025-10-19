#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# ANON-SETUP ENHANCED - Script de anonimización avanzado
# =============================================================================

VERSION="2.0"
LOGFILE="/var/log/anon-setup.log"
BACKUP_DIR="/var/backups/anon-setup"
CONFIG_FILE="/etc/anon-setup.conf"

# Redireccionar output a log
exec 1>>"${LOGFILE}" 2>&1

echo "=== anon-setup v${VERSION}: $(date) ==="

# ---------- PARSEO DE ARGUMENTOS ----------
VERBOSE=0
QUIET=0
RESTORE=0
SKIP_VPN_CHECK=0

while [[ $# -gt 0 ]]; do
  case $1 in
    -v|--verbose) VERBOSE=1; shift ;;
    -q|--quiet) QUIET=1; shift ;;
    -r|--restore) RESTORE=1; shift ;;
    --skip-vpn-check) SKIP_VPN_CHECK=1; shift ;;
    -h|--help)
      echo "Uso: $0 [-v|--verbose] [-q|--quiet] [-r|--restore] [--skip-vpn-check]"
      exit 0
      ;;
    *) echo "Opción desconocida: $1"; exit 1 ;;
  esac
done

# ---------- FUNCIONES AUXILIARES ----------
log_info() {
  [[ $QUIET -eq 0 ]] && echo "[INFO] $*"
}

log_verbose() {
  [[ $VERBOSE -eq 1 ]] && echo "[VERBOSE] $*"
}

log_error() {
  echo "[ERROR] $*" >&2
}

notify_user() {
  if command -v notify-send >/dev/null 2>&1 && [ -n "${SUDO_USER-}" ]; then
    sudo -u "${SUDO_USER}" DISPLAY=:0 notify-send "Anon-Setup" "$1" 2>/dev/null || true
  fi
}

check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    log_error "Este script debe ejecutarse como root."
    exit 1
  fi
}

create_backup() {
  log_info "Creando backup de configuración previa..."
  mkdir -p "${BACKUP_DIR}"
  
  # Backup de configuraciones importantes
  cp /etc/hostname "${BACKUP_DIR}/hostname.bak" 2>/dev/null || true
  cp /etc/resolv.conf "${BACKUP_DIR}/resolv.conf.bak" 2>/dev/null || true
  cp /etc/machine-id "${BACKUP_DIR}/machine-id.bak" 2>/dev/null || true
  cp /etc/timezone "${BACKUP_DIR}/timezone.bak" 2>/dev/null || true
  
  # Guardar MAC original
  if [ -n "${OUT_IF-}" ]; then
    cat /sys/class/net/"${OUT_IF}"/address > "${BACKUP_DIR}/mac_${OUT_IF}.bak" 2>/dev/null || true
  fi
  
  # Guardar reglas iptables
  iptables-save > "${BACKUP_DIR}/iptables.bak" 2>/dev/null || true
  
  log_verbose "Backup guardado en ${BACKUP_DIR}"
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
    log_verbose "Hostname restaurado"
  fi
  
  # Restaurar resolv.conf
  if [ -f "${BACKUP_DIR}/resolv.conf.bak" ]; then
    cp "${BACKUP_DIR}/resolv.conf.bak" /etc/resolv.conf
    log_verbose "DNS restaurado"
  fi
  
  # Restaurar machine-id
  if [ -f "${BACKUP_DIR}/machine-id.bak" ]; then
    cp "${BACKUP_DIR}/machine-id.bak" /etc/machine-id
    log_verbose "Machine-ID restaurado"
  fi
  
  # Restaurar timezone
  if [ -f "${BACKUP_DIR}/timezone.bak" ]; then
    cp "${BACKUP_DIR}/timezone.bak" /etc/timezone
    log_verbose "Timezone restaurado"
  fi
  
  # Restaurar iptables
  if [ -f "${BACKUP_DIR}/iptables.bak" ]; then
    iptables-restore < "${BACKUP_DIR}/iptables.bak"
    log_verbose "Reglas iptables restauradas"
  fi
  
  log_info "Restauración completada. Considera reiniciar el sistema."
  exit 0
}

# ---------- CONFIGURACIÓN ----------
# Cargar config si existe
if [ -f "${CONFIG_FILE}" ]; then
  source "${CONFIG_FILE}"
fi

# Variables con valores por defecto
MAC_PREFIX="${MAC_PREFIX:-}"
DHCP_WAIT="${DHCP_WAIT:-3}"
CHANGE_HOSTNAME="${CHANGE_HOSTNAME:-1}"
CHANGE_TIMEZONE="${CHANGE_TIMEZONE:-1}"
BLOCK_IPV6="${BLOCK_IPV6:-1}"
CLEAN_LOGS="${CLEAN_LOGS:-1}"
REQUIRE_VPN="${REQUIRE_VPN:-0}"

# ---------- INICIO ----------
check_root

if [ $RESTORE -eq 1 ]; then
  restore_backup
fi

create_backup

# ---------- 1. DETECCIÓN DE INTERFAZ ----------
log_info "Detectando interfaz de red..."
OUT_IF=$(ip route get 8.8.8.8 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
if [ -z "${OUT_IF}" ]; then
  OUT_IF=$(ip route | awk '/default/ {print $5; exit}')
fi
if [ -z "${OUT_IF}" ]; then
  log_error "No se pudo detectar interfaz de salida. Abortando."
  exit 1
fi
log_info "Interfaz detectada: ${OUT_IF}"

# Detectar tipo de interfaz
IF_TYPE="unknown"
if [ -d "/sys/class/net/${OUT_IF}/wireless" ]; then
  IF_TYPE="wifi"
elif [ -f "/sys/class/net/${OUT_IF}/device/class" ]; then
  IF_TYPE="ethernet"
fi
log_verbose "Tipo de interfaz: ${IF_TYPE}"

# ---------- 2. DETECCIÓN DE GATEWAY ----------
GW_IP=$(ip route | awk '/default/ {print $3; exit}')
if [ -z "${GW_IP}" ]; then
  log_error "No se pudo determinar la IP de gateway por defecto."
  GW_IP=""
fi
log_info "Gateway detectado: ${GW_IP}"

# ---------- 3. VERIFICACIÓN DE VPN (OPCIONAL) ----------
if [ $REQUIRE_VPN -eq 1 ] && [ $SKIP_VPN_CHECK -eq 0 ]; then
  log_info "Verificando conexión VPN..."
  VPN_ACTIVE=0
  
  # Verificar interfaces VPN comunes
  for vpn_if in tun0 tap0 wg0 ppp0; do
    if ip link show "$vpn_if" >/dev/null 2>&1; then
      VPN_ACTIVE=1
      log_info "VPN detectada en interfaz: $vpn_if"
      break
    fi
  done
  
  if [ $VPN_ACTIVE -eq 0 ]; then
    log_error "No se detectó conexión VPN activa. Use --skip-vpn-check para omitir."
    notify_user "⚠️ VPN no detectada - Anonimización cancelada"
    exit 1
  fi
fi

# ---------- 4. INSTALACIÓN DE DEPENDENCIAS ----------
log_info "Verificando dependencias..."
PACKAGES_TO_INSTALL=""

if ! command -v macchanger >/dev/null 2>&1; then
  PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL macchanger"
fi

if [ -n "$PACKAGES_TO_INSTALL" ]; then
  log_info "Instalando paquetes faltantes: $PACKAGES_TO_INSTALL"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq || true
  apt-get install -y $PACKAGES_TO_INSTALL || log_error "Instalación de paquetes falló"
fi

# ---------- 5. CAMBIO DE MAC ADDRESS ----------
log_info "Cambiando MAC address en ${OUT_IF}..."
OLD_MAC=$(cat /sys/class/net/"${OUT_IF}"/address 2>/dev/null || echo "unknown")
log_verbose "MAC anterior: ${OLD_MAC}"

ip link set "${OUT_IF}" down || log_error "Fallo al bajar interfaz ${OUT_IF}"

if [ -n "${MAC_PREFIX}" ]; then
  PREF=${MAC_PREFIX// /}
  if ! printf '%s' "${PREF}" | grep -Eq '^([0-9A-Fa-f]{2}:){0,2}[0-9A-Fa-f]{2}$'; then
    log_error "Formato de MAC_PREFIX inválido: ${MAC_PREFIX}. Usando macchanger -e."
    macchanger -e "${OUT_IF}" || log_error "macchanger falló"
  else
    IFS=':' read -ra PARTS <<< "${PREF}"
    COUNT=${#PARTS[@]}
    if [ "${COUNT}" -gt 6 ]; then
      log_error "Prefijo demasiado largo; usando macchanger -e"
      macchanger -e "${OUT_IF}" || log_error "macchanger falló"
    else
      NEED=$((6 - COUNT))
      SUF=""
      for i in $(seq 1 ${NEED}); do
        SUF+=":$(printf "%02x" $((RANDOM % 256)))"
      done
      NEW_MAC="${PREF}${SUF}"
      NEW_MAC=$(echo "${NEW_MAC}" | sed 's/::/:/g' | sed 's/^://')
      log_verbose "Asignando MAC personalizada: ${NEW_MAC}"
      ip link set dev "${OUT_IF}" address "${NEW_MAC}" || {
        log_error "Error asignando MAC manualmente; fallback a macchanger -e"
        macchanger -e "${OUT_IF}" || log_error "macchanger falló"
      }
    fi
  fi
else
  # Usar -e para mantener vendor OUI (más realista)
  macchanger -e "${OUT_IF}" || log_error "macchanger falló"
fi

ip link set "${OUT_IF}" up || log_error "Fallo al subir interfaz ${OUT_IF}"
sleep "${DHCP_WAIT}"

# ---------- 6. RENOVACIÓN DHCP ----------
log_info "Renovando configuración de red..."

if [ "$IF_TYPE" == "wifi" ] && command -v nmcli >/dev/null 2>&1; then
  log_verbose "Usando NetworkManager para WiFi..."
  nmcli device disconnect "${OUT_IF}" || true
  sleep 2
  nmcli device connect "${OUT_IF}" || log_error "nmcli reconectar falló"
elif command -v dhclient >/dev/null 2>&1; then
  log_verbose "Usando dhclient..."
  dhclient -r "${OUT_IF}" || true
  sleep 1
  dhclient "${OUT_IF}" || log_error "dhclient falló"
elif command -v nmcli >/dev/null 2>&1; then
  log_verbose "Usando NetworkManager..."
  nmcli device disconnect "${OUT_IF}" || true
  sleep 1
  nmcli device connect "${OUT_IF}" || log_error "nmcli reconectar falló"
else
  log_error "No se encontró dhclient ni nmcli: renueva DHCP manualmente."
fi

# Verificar cambio de MAC
NEW_MAC=$(cat /sys/class/net/"${OUT_IF}"/address 2>/dev/null || echo "unknown")
log_info "Nueva MAC efectiva: ${NEW_MAC}"

if [ "$OLD_MAC" == "$NEW_MAC" ]; then
  log_error "ADVERTENCIA: La MAC no cambió. Puede haber un problema."
  notify_user "⚠️ MAC address no cambió"
fi

# ---------- 7. CONFIGURACIÓN DE DNS ----------
if [ -n "${GW_IP}" ]; then
  log_info "Configurando DNS a ${GW_IP}..."
  
  if command -v nmcli >/dev/null 2>&1; then
    CONN=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v dev="${OUT_IF}" '$0 ~ dev {print $1; exit}')
    if [ -n "${CONN}" ]; then
      log_verbose "Configurando DNS para conexión NM: ${CONN}"
      nmcli connection modify "${CONN}" ipv4.dns "${GW_IP}" ipv4.ignore-auto-dns yes || log_error "nmcli modify falló"
      nmcli connection up "${CONN}" || log_error "nmcli up falló"
    else
      log_verbose "Escribiendo /etc/resolv.conf directamente"
      echo -e "nameserver ${GW_IP}\noptions rotate\noptions timeout:1" > /etc/resolv.conf || log_error "No pude escribir /etc/resolv.conf"
    fi
  else
    echo -e "nameserver ${GW_IP}\noptions rotate\noptions timeout:1" > /etc/resolv.conf || log_error "No pude escribir /etc/resolv.conf"
  fi
fi

# ---------- 8. REGLAS IPTABLES AVANZADAS ----------
log_info "Configurando reglas de firewall..."

# Crear cadena ANON_DNS
iptables -nL ANON_DNS 2>/dev/null || iptables -N ANON_DNS || true
iptables -F ANON_DNS || true

# Permitir loopback y conexiones establecidas
iptables -A ANON_DNS -o lo -j ACCEPT
iptables -A ANON_DNS -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

if [ -n "${GW_IP}" ]; then
  # Permitir DNS solo al gateway
  iptables -A ANON_DNS -d "${GW_IP}" -p udp --dport 53 -j ACCEPT
  iptables -A ANON_DNS -d "${GW_IP}" -p tcp --dport 53 -j ACCEPT
fi

# Bloquear DNS a otros destinos
iptables -A ANON_DNS -p udp --dport 53 -j DROP
iptables -A ANON_DNS -p tcp --dport 53 -j DROP

# Bloquear puertos de telemetría comunes
log_verbose "Bloqueando puertos de telemetría..."
for port in 443 80; do
  # Bloquear dominios de telemetría conocidos (requiere resolución previa)
  # Esto es básico, idealmente usarías una lista más completa
  iptables -A ANON_DNS -p tcp --dport $port -m string --string "telemetry" --algo bm -j DROP || true
done

# Aplicar cadena a OUTPUT
if ! iptables -C OUTPUT -j ANON_DNS >/dev/null 2>&1; then
  iptables -A OUTPUT -j ANON_DNS || log_error "No pude añadir ANON_DNS a OUTPUT"
fi

# Bloquear IPv6 si está configurado
if [ $BLOCK_IPV6 -eq 1 ]; then
  log_info "Bloqueando IPv6..."
  
  # Crear cadena para IPv6
  ip6tables -nL ANON_IPV6 2>/dev/null || ip6tables -N ANON_IPV6 || true
  ip6tables -F ANON_IPV6 || true
  
  # Bloquear todo excepto loopback
  ip6tables -A ANON_IPV6 -o lo -j ACCEPT
  ip6tables -A ANON_IPV6 -j DROP
  
  if ! ip6tables -C OUTPUT -j ANON_IPV6 >/dev/null 2>&1; then
    ip6tables -A OUTPUT -j ANON_IPV6 || log_error "No pude configurar reglas IPv6"
  fi
  
  # Deshabilitar IPv6 en sysctl
  sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || true
fi

# ---------- 9. PARÁMETROS DEL KERNEL ----------
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

# Deshabilitar source routing
sysctl -w net.ipv4.conf.all.accept_source_route=0 >/dev/null 2>&1 || true

log_verbose "Parámetros del kernel configurados"

# ---------- 10. CAMBIO DE HOSTNAME ----------
if [ $CHANGE_HOSTNAME -eq 1 ]; then
  log_info "Cambiando hostname..."
  NEW_HOSTNAME="host-$(head /dev/urandom | tr -dc a-z0-9 | head -c 8)"
  
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
fi

# ---------- 11. CAMBIO DE TIMEZONE ----------
if [ $CHANGE_TIMEZONE -eq 1 ]; then
  log_info "Cambiando timezone..."
  
  # Lista de timezones comunes para aleatorizar
  TIMEZONES=(
    "UTC"
    "America/New_York"
    "America/Los_Angeles"
    "Europe/London"
    "Europe/Paris"
    "Asia/Tokyo"
    "Australia/Sydney"
  )
  
  RANDOM_TZ=${TIMEZONES[$RANDOM % ${#TIMEZONES[@]}]}
  
  if [ -f "/usr/share/zoneinfo/${RANDOM_TZ}" ]; then
    ln -sf "/usr/share/zoneinfo/${RANDOM_TZ}" /etc/localtime
    echo "${RANDOM_TZ}" > /etc/timezone
    log_info "Timezone cambiado a: ${RANDOM_TZ}"
  else
    log_error "Timezone ${RANDOM_TZ} no encontrado"
  fi
fi

# ---------- 12. REGENERACIÓN DE MACHINE-ID ----------
log_info "Regenerando machine-id..."

if [ -f /etc/machine-id ]; then
  rm -f /etc/machine-id || true
fi

if [ -f /var/lib/dbus/machine-id ]; then
  rm -f /var/lib/dbus/machine-id || true
fi

if command -v systemd-machine-id-setup >/dev/null 2>&1; then
  systemd-machine-id-setup || log_error "systemd-machine-id-setup falló"
else
  if command -v dbus-uuidgen >/dev/null 2>&1; then
    dbus-uuidgen > /etc/machine-id || log_error "dbus-uuidgen falló"
  else
    # Generar UUID manualmente
    cat /proc/sys/kernel/random/uuid | tr -d '-' > /etc/machine-id || log_error "Generación manual de machine-id falló"
  fi
fi

log_verbose "Machine-id regenerado"

# ---------- 13. LIMPIEZA DE LOGS Y HISTORIALES ----------
if [ $CLEAN_LOGS -eq 1 ]; then
  log_info "Limpiando historiales y logs..."
  
  # Limpiar bash history de todos los usuarios
  for user_home in /home/* /root; do
    if [ -d "$user_home" ]; then
      for hist_file in .bash_history .zsh_history .python_history .mysql_history .lesshst .viminfo; do
        if [ -f "$user_home/$hist_file" ]; then
          : > "$user_home/$hist_file" 2>/dev/null || true
          log_verbose "Limpiado: $user_home/$hist_file"
        fi
      done
      
      # Limpiar thumbnails
      if [ -d "$user_home/.cache/thumbnails" ]; then
        rm -rf "$user_home/.cache/thumbnails"/* 2>/dev/null || true
      fi
      
      # Limpiar cache de navegadores
      for cache_dir in .cache/mozilla .cache/chromium .cache/google-chrome; do
        if [ -d "$user_home/$cache_dir" ]; then
          rm -rf "$user_home/$cache_dir"/* 2>/dev/null || true
        fi
      done
    fi
  done
  
  # Limpiar historial actual
  history -cw 2>/dev/null || true
  
  # Limpiar journal
  if command -v journalctl >/dev/null 2>&1; then
    journalctl --rotate 2>/dev/null || true
    journalctl --vacuum-time=1s 2>/dev/null || true
  fi
  
  # Limpiar logs del sistema (selectivo)
  for log_file in /var/log/auth.log /var/log/syslog /var/log/kern.log; do
    if [ -f "$log_file" ]; then
      : > "$log_file" 2>/dev/null || true
    fi
  done
  
  # Limpiar cache de apt
  apt-get clean 2>/dev/null || true
  
  # Limpiar /tmp y /var/tmp (cuidadosamente)
  find /tmp -type f -atime +1 -delete 2>/dev/null || true
  find /var/tmp -type f -atime +7 -delete 2>/dev/null || true
  
  log_verbose "Limpieza completada"
fi

# ---------- 14. DESHABILITAR GUEST ADDITIONS / VM TOOLS ----------
log_info "Deshabilitando servicios de virtualización..."

VM_SERVICES=(
  "vboxservice"
  "vboxadd-service"
  "open-vm-tools"
  "vmtoolsd"
  "vmware-tools"
  "qemu-guest-agent"
  "virtualbox-guest-utils"
)

for svc in "${VM_SERVICES[@]}"; do
  if systemctl list-unit-files | grep -q "^${svc}"; then
    systemctl disable --now "${svc}" 2>/dev/null || true
    log_verbose "Deshabilitado: ${svc}"
  fi
done

# Deshabilitar portapapeles compartido de VirtualBox
if command -v VBoxControl >/dev/null 2>&1; then
  VBoxControl guestproperty set /VirtualBox/GuestAdd/SharedFolders/MountDir "" 2>/dev/null || true
  log_verbose "Configuración de VirtualBox ajustada"
fi

# ---------- 15. LIMPIEZA DE SWAP ----------
log_info "Limpiando swap..."
if [ -n "$(swapon --show)" ]; then
  swapoff -a 2>/dev/null || true
  swapon -a 2>/dev/null || true
  log_verbose "Swap limpiado"
fi

# ---------- 16. SCRIPT DE HARDENING PARA NAVEGADOR ----------
log_info "Generando script de hardening para Firefox..."

BROWSER_SCRIPT="/usr/local/bin/firefox-anon.sh"
cat > "${BROWSER_SCRIPT}" << 'EOF'
#!/bin/bash
# Script de hardening para Firefox

FIREFOX_PROFILES="${HOME}/.mozilla/firefox"

if [ ! -d "${FIREFOX_PROFILES}" ]; then
  echo "No se encontraron perfiles de Firefox"
  exit 0
fi

for profile in "${FIREFOX_PROFILES}"/*.default*; do
  if [ -d "$profile" ]; then
    PREFS="${profile}/user.js"
    
    echo "Configurando perfil: $(basename $profile)"
    
    cat >> "${PREFS}" << 'PREFS'
// Deshabilitar WebRTC
user_pref("media.peerconnection.enabled", false);
user_pref("media.navigator.enabled", false);

// Resistencia a fingerprinting
user_pref("privacy.resistFingerprinting", true);
user_pref("privacy.trackingprotection.fingerprinting.enabled", true);
user_pref("privacy.trackingprotection.cryptomining.enabled", true);

// Deshabilitar telemetría
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("datareporting.healthreport.uploadEnabled", false);

// DNS sobre HTTPS
user_pref("network.trr.mode", 2);

// Deshabilitar geolocalización
user_pref("geo.enabled", false);

// Cookies
user_pref("network.cookie.cookieBehavior", 1);
PREFS
    
    echo "Perfil configurado: $(basename $profile)"
  fi
done

echo "Hardening de Firefox completado"
EOF

chmod +x "${BROWSER_SCRIPT}" 2>/dev/null || true
log_verbose "Script de Firefox creado en ${BROWSER_SCRIPT}"

# Ejecutar si existe usuario SUDO_USER
if [ -n "${SUDO_USER-}" ]; then
  sudo -u "${SUDO_USER}" bash "${BROWSER_SCRIPT}" 2>/dev/null || true
fi

# ---------- 17. VERIFICACIÓN Y TEST ----------
log_info "Realizando verificaciones finales..."

# Verificar DNS
if command -v dig >/dev/null 2>&1; then
  DNS_TEST=$(dig +short google.com 2>/dev/null | head -n1)
  if [ -n "$DNS_TEST" ]; then
    log_info "✓ DNS funcional (test: ${DNS_TEST})"
  else
    log_error "✗ DNS no responde"
  fi
fi

# Verificar IP pública (opcional, requiere curl)
if command -v curl >/dev/null 2>&1; then
  PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "N/A")
  log_info "IP pública actual: ${PUBLIC_IP}"
fi

# Generar reporte
REPORT_FILE="/var/log/anon-setup-report.txt"
cat > "${REPORT_FILE}" << REPORT
=== REPORTE DE ANONIMIZACIÓN ===
Fecha: $(date)
Versión: ${VERSION}

CONFIGURACIÓN:
- Interfaz: ${OUT_IF} (${IF_TYPE})
- MAC anterior: ${OLD_MAC}
- MAC nueva: ${NEW_MAC}
- Gateway: ${GW_IP}
- Hostname: $(hostname)
- Timezone: $(cat /etc/timezone 2>/dev/null || echo "N/A")
- Machine-ID: $(cat /etc/machine-id 2>/dev/null | head -c 8)...

VERIFICACIONES:
- Cambio de MAC: $([ "$OLD_MAC" != "$NEW_MAC" ] && echo "✓ OK" || echo "✗ FALLO")
- DNS funcional: $([ -n "$DNS_TEST" ] && echo "✓ OK" || echo "? No verificado")
- IPv6 bloqueado: $([ $BLOCK_IPV6 -eq 1 ] && echo "✓ Sí" || echo "✗ No")
- IP pública: ${PUBLIC_IP}

SERVICIOS VM DESHABILITADOS:
$(for svc in "${VM_SERVICES[@]}"; do
  if systemctl list-unit-files | grep -q "^${svc}"; then
    echo "- ${svc}"
  fi
done)

BACKUP: ${BACKUP_DIR}
Para restaurar: $0 --restore
REPORT

log_info "Reporte generado en: ${REPORT_FILE}"

# ---------- 18. NOTIFICACIÓN FINAL ----------
notify_user "✅ Anonimización completada"

log_info "=== Anonimización completada ==="
log_info "Se recomienda REINICIAR el sistema para asegurar que todos los cambios surtan efecto."
log_info "Para restaurar configuración previa: $0 --restore"

echo "=== Fin anon-setup: $(date) ==="

# Opcional: auto-reinicio después de X segundos (comentado por seguridad)
# read -t 30 -p "Reiniciando en 30 segundos... (Ctrl+C para cancelar)" || shutdown -r +1