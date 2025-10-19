#!/usr/bin/env bash
set -euo pipefail

LOGFILE="/var/log/anon-setup.log"
exec 1>>"${LOGFILE}" 2>&1

echo "=== anon-setup: $(date) ==="

if [ "$(id -u)" -ne 0 ]; then
  echo "Este script debe ejecutarse como root."
  exit 1
fi

# ---------- CONFIGURACION ----------
# Si quieres que la MAC generada tenga un prefijo, ponlo aquí en formato XX:XX:XX
# Ejemplo: MAC_PREFIX="02:00:00"
# Si MAC_PREFIX está vacío, se usará macchanger -r para una MAC totalmente aleatoria.
MAC_PREFIX=""

# Tiempo (segundos) a esperar tras cambiar MAC antes de renovar DHCP
DHCP_WAIT=3
# ------------------------------------

# 1) Detectar interfaz de salida (robusto)
OUT_IF=$(ip route get 8.8.8.8 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
if [ -z "${OUT_IF}" ]; then
  OUT_IF=$(ip route | awk '/default/ {print $5; exit}')
fi
if [ -z "${OUT_IF}" ]; then
  echo "No se pudo detectar interfaz de salida. Abortando."
  exit 1
fi
echo "Interfaz detectada: ${OUT_IF}"

# 2) Determinar gateway (IP del gateway por defecto)
GW_IP=$(ip route | awk '/default/ {print $3; exit}')
if [ -z "${GW_IP}" ]; then
  echo "No se pudo determinar la IP de gateway por defecto. Continuando sin reglas DNS forzadas."
fi
echo "Gateway detectado: ${GW_IP}"

# 3) Instalar macchanger si no existe
if ! command -v macchanger >/dev/null 2>&1; then
  echo "macchanger no encontrado. Intentando instalar..."
  apt update -y || true
  apt install -y macchanger || echo "Instalación de macchanger fallida; continúa de todas formas."
fi

# 4) Cambiar MAC: con prefijo o aleatoria
echo "Cambiando MAC en ${OUT_IF}..."
ip link set "${OUT_IF}" down || echo "Warning: fallo al bajar interfaz ${OUT_IF}"

if [ -n "${MAC_PREFIX}" ]; then
  # normalizar prefijo (sin espacios) y comprobar formato básico
  PREF=${MAC_PREFIX// /}
  if ! printf '%s' "${PREF}" | grep -Eq '^([0-9A-Fa-f]{2}:){0,2}[0-9A-Fa-f]{2}$'; then
    echo "Formato de MAC_PREFIX invalido: ${MAC_PREFIX}. Usando macchanger -r."
    macchanger -r "${OUT_IF}" || echo "Warning: macchanger falló"
  else
    # generar 3 bytes aleatorios para completar la MAC
    # si prefijo tiene 3 bytes (XX:XX:XX) lo completamos con 3 bytes; si tiene menos, completamos hasta 6.
    IFS=':' read -ra PARTS <<< "${PREF}"
    COUNT=${#PARTS[@]}
    if [ "${COUNT}" -gt 6 ]; then
      echo "Prefijo demasiado largo; usando macchanger -r"
      macchanger -r "${OUT_IF}" || echo "Warning: macchanger falló"
    else
      NEED=$((6 - COUNT))
      SUF=""
      for i in $(seq 1 ${NEED}); do
        SUF+=":$(printf "%02x" $((RANDOM % 256)))"
      done
      NEW_MAC="${PREF}${SUF}"
      # limpiar posibles :: si prefijo vacío
      NEW_MAC=$(echo "${NEW_MAC}" | sed 's/::/:/g' | sed 's/^://')
      echo "Asignando MAC personalizada: ${NEW_MAC}"
      ip link set dev "${OUT_IF}" address "${NEW_MAC}" || {
        echo "Error asignando MAC manualmente; fallback a macchanger -r"
        macchanger -r "${OUT_IF}" || echo "Warning: macchanger falló"
      }
    fi
  fi
else
  macchanger -r "${OUT_IF}" || echo "Warning: macchanger falló"
fi

ip link set "${OUT_IF}" up || echo "Warning: fallo al subir interfaz ${OUT_IF}"
sleep "${DHCP_WAIT}"

# 5) Renovar DHCP para obtener IP con la nueva MAC (si dhclient disponible)
if command -v dhclient >/dev/null 2>&1; then
  echo "Renovando DHCP en ${OUT_IF}..."
  dhclient -r "${OUT_IF}" || true
  dhclient "${OUT_IF}" || echo "Aviso: dhclient falló"
elif command -v nmcli >/dev/null 2>&1; then
  echo "Usando NetworkManager (nmcli) para reconectar interfaz..."
  nmcli device disconnect "${OUT_IF}" || true
  sleep 1
  nmcli device connect "${OUT_IF}" || echo "Aviso: nmcli reconectar fallo"
else
  echo "No se encontró dhclient ni nmcli: asegúrate de renovar DHCP manualmente."
fi

NEW_MAC=$(cat /sys/class/net/"${OUT_IF}"/address 2>/dev/null || echo "unknown")
echo "Nueva MAC efectiva: ${NEW_MAC}"

# 6) Forzar DNS: escribir resolv.conf para apuntar al gateway (si lo detectamos)
if [ -n "${GW_IP}" ]; then
  echo "Forzando DNS a ${GW_IP} (sobrescribiendo /etc/resolv.conf si es posible)..."
  # Si NetworkManager está presente, usa nmcli para fijar DNS en la conexión actual
  if command -v nmcli >/dev/null 2>&1; then
    # intentar obtener la conexión asociada a la interfaz
    CONN=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v dev="${OUT_IF}" '$0 ~ dev {print $1; exit}')
    if [ -n "${CONN}" ]; then
      echo "Configurando DNS para la conexión NM: ${CONN}"
      nmcli connection modify "${CONN}" ipv4.dns "${GW_IP}" ipv4.ignore-auto-dns yes || echo "Aviso: fallo nmcli modify"
      nmcli connection up "${CONN}" || echo "Aviso: fallo nmcli up"
    else
      echo "No se encontró conexión NM activa para ${OUT_IF}; escribiendo /etc/resolv.conf directamente."
      echo -e "nameserver ${GW_IP}\noptions rotate\noptions timeout:1" > /etc/resolv.conf || echo "Aviso: no pude escribir /etc/resolv.conf"
    fi
  else
    # fallback simple: escribir en /etc/resolv.conf (puede ser sobrescrito por systemd-resolved / DHCP)
    echo -e "nameserver ${GW_IP}\noptions rotate\noptions timeout:1" > /etc/resolv.conf || echo "Aviso: no pude escribir /etc/resolv.conf"
  fi
else
  echo "No hay gateway detectado; no se cambiará resolv.conf."
fi

# 7) Política iptables: crear cadena ANON_DNS y bloquear DNS que no vaya al gateway
echo "Configurando reglas iptables para forzar DNS al gateway y bloquear otras consultas DNS..."

# crear cadena si no existe
iptables -nL ANON_DNS 2>/dev/null || iptables -N ANON_DNS || true
# vaciarla
iptables -F ANON_DNS || true

# permitir loopback y conexiones ya establecidas
iptables -A ANON_DNS -o lo -j ACCEPT
iptables -A ANON_DNS -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

if [ -n "${GW_IP}" ]; then
  # permitir DNS hacia la gateway
  iptables -A ANON_DNS -d "${GW_IP}" -p udp --dport 53 -j ACCEPT
  iptables -A ANON_DNS -d "${GW_IP}" -p tcp --dport 53 -j ACCEPT
fi

# bloquear el resto de DNS salientes (UDP/TCP 53)
iptables -A ANON_DNS -p udp --dport 53 -j DROP
iptables -A ANON_DNS -p tcp --dport 53 -j DROP

# insertar la cadena en OUTPUT si no está ya
if ! iptables -C OUTPUT -j ANON_DNS >/dev/null 2>&1; then
  iptables -A OUTPUT -j ANON_DNS || echo "Aviso: no pude añadir ANON_DNS a OUTPUT"
fi

# 8) Regenerar machine-id (si systemd está presente)
if command -v systemd-machine-id-setup >/dev/null 2>&1; then
  echo "Regenerando /etc/machine-id..."
  if [ -f /etc/machine-id ]; then
    rm -f /etc/machine-id || true
  fi
  systemd-machine-id-setup || echo "Warning: systemd-machine-id-setup falló"
else
  echo "systemd-machine-id-setup no disponible; generando /etc/machine-id con dbus-uuidgen..."
  dbus-uuidgen > /etc/machine-id || echo "Warning: dbus-uuidgen falló"
fi

# 9) Limpiar historiales basicos y journal
echo "Limpiando historiales y journal..."
if [ -n "${SUDO_USER-}" ]; then
  USER_HOME=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
  if [ -n "${USER_HOME}" ] && [ -f "${USER_HOME}/.bash_history" ]; then
    : > "${USER_HOME}/.bash_history" || echo "Aviso: no pude limpiar ${USER_HOME}/.bash_history"
  fi
fi
: > /root/.bash_history 2>/dev/null || true
history -cw || true

if command -v journalctl >/dev/null 2>&1; then
  journalctl --rotate || true
  journalctl --vacuum-time=1s || true
fi

# 10) Deshabilitar guest additions si existen
echo "Intentando deshabilitar servicios de Guest Additions / Tools..."
for svc in vboxservice vboxadd-service open-vm-tools vmtoolsd vmware-tools; do
  if systemctl list-units --full -all | grep -q "^${svc}"; then
    systemctl disable --now "${svc}" || true
  fi
done

echo "anon-setup completado. Recomendado: reiniciar la MV para asegurar que todo queda aplicado."
echo "=== Fin anon-setup: $(date) ==="
