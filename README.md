# Anon-Setup Enhanced - Script de Anonimización Avanzado para Máquinas Virtuales

![Shell Script](https://img.shields.io/badge/Shell_Script-121011?style=for-the-badge&logo=gnu-bash&logoColor=white)
![License](https://img.shields.io/badge/License-GPLv3-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Linux-lightgrey.svg)
![Version](https://img.shields.io/badge/Version-2.0-green.svg)

## ⚠️ ADVERTENCIA LEGAL IMPORTANTE

**ESTE SOFTWARE ES SOLO PARA USOS LEGÍTIMOS:**

- Pentesting en entornos autorizados
- Laboratorios de seguridad y Red Team
- Auditorías de seguridad profesionales
- Investigación forense digital
- Protección de privacidad en redes públicas
- Educación y formación en ciberseguridad

**NO USES ESTE SOFTWARE PARA:**
- Actividades ilegales de cualquier tipo
- Eludir medidas de seguridad sin autorización
- Atacar sistemas sin permiso explícito
- Ocultar actividades criminales

**El uso indebido de esta herramienta es responsabilidad exclusiva del usuario. Los autores no se hacen responsables del mal uso.**

---

## 📖 Descripción

`anon-setup` es un script de bash profesional diseñado para maximizar el anonimato y reducir la huella digital en máquinas virtuales durante pruebas de penetración, ejercicios de Red Team y auditorías de seguridad. Implementa múltiples capas de ofuscación y hardening siguiendo las mejores prácticas de la industria.

### 🆕 Versión 2.0 - Nuevas Características

- Sistema completo de backup y restauración
- Argumentos de línea de comandos
- Verificación de VPN opcional
- Hardening automático de navegadores
- Bloqueo de IPv6 y prevención de fugas DNS
- Configuración avanzada de kernel
- Limpieza profunda de logs y cache
- Detección inteligente de tipo de red (WiFi/Ethernet)
- Sistema de notificaciones de escritorio
- Reportes detallados de anonimización

---

## 🚀 Características Principales

### 🔐 Ofuscación de Identidad
- **MAC Address Spoofing**: Cambio inteligente con vendors OUI reales
- **Hostname Aleatorio**: Generación de nombres únicos por sesión
- **Machine-ID**: Regeneración completa del identificador del sistema
- **Timezone Rotation**: Cambio aleatorio de zona horaria

### 🌐 Seguridad de Red
- **DNS Hardening**: Forzado de DNS al gateway con reglas iptables
- **IPv6 Blocking**: Bloqueo completo para prevenir fugas
- **Firewall Rules**: Cadenas dedicadas para control granular
- **VPN Check**: Verificación opcional de túnel VPN activo
- **Port Randomization**: Aleatorización de puertos locales

### 🧹 Limpieza de Huellas
- **Logs del Sistema**: Limpieza de auth.log, syslog, kern.log
- **Historiales**: Bash, Zsh, Python, MySQL, Vim, Less
- **Browser Cache**: Firefox, Chrome, Chromium
- **Thumbnails**: Eliminación de miniaturas generadas
- **Swap Cleaning**: Limpieza de memoria swap
- **Journal**: Rotación y vacuum de systemd-journald

### 🛡️ Hardening y Protección
- **Kernel Tunning**: Parámetros optimizados anti-fingerprinting
- **Browser Hardening**: Script automático para Firefox
- **VM Tools Disable**: Desactivación de Guest Additions
- **Telemetry Blocking**: Bloqueo de endpoints de telemetría
- **WebRTC Protection**: Configuración anti-leak en navegadores

### 📊 Gestión y Monitoreo
- **Sistema de Backup**: Respaldo automático de configuraciones
- **Rollback**: Restauración completa con un comando
- **Logging Avanzado**: Logs detallados y estructurados
- **Reportes**: Generación de informes post-ejecución
- **Notificaciones**: Alertas de escritorio para el usuario

---

## 📋 Requisitos

### Sistema Operativo
- Linux (Debian/Ubuntu, RHEL/CentOS, Arch, etc.)
- Kernel 4.0+
- Systemd (recomendado)

### Privilegios
- Acceso root/sudo obligatorio

### Dependencias Base
```bash
# El script instalará automáticamente las dependencias faltantes
- bash 4.0+
- iptables
- ip (iproute2)
- macchanger (se instala automáticamente si falta)
```

### Dependencias Opcionales
```bash
# Para funcionalidades adicionales
- curl (verificación de IP pública)
- dig (test de DNS)
- nmcli (NetworkManager)
- notify-send (notificaciones de escritorio)
```

---

## 🛠️ Instalación

### Método 1: Instalación Manual

```bash
# Clonar el repositorio
git clone https://github.com/TraceVoid/Anon-Setup.git
cd anon-setup

# Hacer ejecutable
chmod +x anon-setup.sh

# Ejecutar (requiere root)
sudo ./anon-setup.sh
```

### Método 2: Instalación en el Sistema

```bash
# Copiar a directorio del sistema
sudo cp anon-setup.sh /usr/local/bin/anon-setup
sudo chmod +x /usr/local/bin/anon-setup

# Ejecutar desde cualquier ubicación
sudo anon-setup
```

### Método 3: Servicio Systemd (Ejecución Automática)

```bash
# Crear servicio
sudo nano /etc/systemd/system/anon-setup.service
```

Contenido del servicio:
```ini
[Unit]
Description=Anon-Setup Enhanced - Sistema de Anonimización
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/anon-setup -q
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

```bash
# Habilitar en el arranque
sudo systemctl enable anon-setup.service

# Ejecutar manualmente
sudo systemctl start anon-setup.service
```

---

## ⚙️ Configuración

### Archivo de Configuración Global

Crea `/etc/anon-setup.conf` para configuración persistente:

```bash
# ---------- CONFIGURACIÓN AVANZADA ----------

# Prefijo MAC (vacío = vendor OUI aleatorio)
MAC_PREFIX=""

# Tiempo de espera DHCP (segundos)
DHCP_WAIT=3

# Cambiar hostname (1=sí, 0=no)
CHANGE_HOSTNAME=1

# Cambiar timezone (1=sí, 0=no)
CHANGE_TIMEZONE=1

# Bloquear IPv6 (1=sí, 0=no)
BLOCK_IPV6=1

# Limpiar logs (1=sí, 0=no)
CLEAN_LOGS=1

# Requerir VPN activa (1=sí, 0=no)
REQUIRE_VPN=0
```

### Variables Disponibles

| Variable | Descripción | Valor por Defecto |
|----------|-------------|-------------------|
| `MAC_PREFIX` | Prefijo personalizado para MAC | Vacío (aleatorio) |
| `DHCP_WAIT` | Espera tras cambio de MAC | 3 segundos |
| `CHANGE_HOSTNAME` | Cambiar nombre del host | 1 (activado) |
| `CHANGE_TIMEZONE` | Rotar zona horaria | 1 (activado) |
| `BLOCK_IPV6` | Bloquear IPv6 completamente | 1 (activado) |
| `CLEAN_LOGS` | Limpieza profunda de logs | 1 (activado) |
| `REQUIRE_VPN` | Verificar VPN antes de ejecutar | 0 (desactivado) |

---

## 📝 Uso

### Comandos Básicos

```bash
# Ejecución estándar
sudo anon-setup.sh

# Modo verbose (información detallada)
sudo anon-setup.sh --verbose
sudo anon-setup.sh -v

# Modo silencioso (para scripts/cron)
sudo anon-setup.sh --quiet
sudo anon-setup.sh -q

# Restaurar configuración original
sudo anon-setup.sh --restore
sudo anon-setup.sh -r

# Saltar verificación de VPN
sudo anon-setup.sh --skip-vpn-check

# Ver ayuda
sudo anon-setup.sh --help
sudo anon-setup.sh -h
```

### Ejemplos de Uso

```bash
# Escenario 1: Pentesting con VPN
sudo anon-setup.sh -v

# Escenario 2: Ejecución automatizada (cron)
sudo anon-setup.sh -q

# Escenario 3: Testing sin VPN
sudo anon-setup.sh --skip-vpn-check

# Escenario 4: Volver al estado original
sudo anon-setup.sh --restore
```

### Monitoreo en Tiempo Real

```bash
# Ver logs en tiempo real
sudo tail -f /var/log/anon-setup.log

# Ver reporte generado
cat /var/log/anon-setup-report.txt

# Verificar cambios aplicados
ip link show              # Ver MAC actual
ip addr show              # Ver configuración de red
sudo iptables -L -n -v    # Ver reglas de firewall
sudo ip6tables -L -n -v   # Ver reglas IPv6
cat /etc/resolv.conf      # Ver DNS configurado
hostname                  # Ver hostname actual
cat /etc/timezone         # Ver timezone actual
```

---

## 🔧 Funcionalidades Detalladas

### 1. Sistema de Backup y Restauración

#### Backup Automático
El script crea automáticamente un backup completo en `/var/backups/anon-setup/`:
- Hostname original
- Configuración DNS
- Machine-ID
- Timezone
- MAC address original
- Reglas iptables

#### Restauración
```bash
sudo anon-setup.sh --restore
```

Restaura todo el sistema al estado previo a la ejecución.

### 2. Ofuscación de MAC Address

**Características:**
- Uso de vendor OUI reales (flag `-e` de macchanger)
- Soporte para prefijos personalizados
- Verificación de cambio exitoso
- Detección de tipo de interfaz (WiFi/Ethernet)
- Reconexión inteligente según tipo de red

**Ejemplo de MAC con vendor real:**
```
Antes:  08:00:27:4a:bc:de (VirtualBox)
Después: 00:1a:2b:3c:4d:5e (Dell Inc.)
```

### 3. Hardening de DNS y Firewall

**Cadena iptables ANON_DNS:**
- Permite DNS solo al gateway
- Bloquea consultas DNS externas
- Previene fugas de DNS
- Compatible con NetworkManager

**Cadena iptables ANON_IPV6:**
- Bloquea todo tráfico IPv6
- Previene fugas por dual-stack
- Configura sysctl para deshabilitar IPv6

### 4. Parámetros del Kernel

**Modificaciones aplicadas:**
```bash
net.ipv4.tcp_timestamps=0           # Anti-fingerprinting
net.ipv4.ip_local_port_range=15000 65000  # Ports aleatorios
net.ipv4.tcp_syncookies=1           # Protección SYN flood
net.ipv4.conf.all.accept_redirects=0     # Sin redirects
net.ipv4.conf.all.send_redirects=0       # Sin redirects
net.ipv4.conf.all.accept_source_route=0  # Sin source routing
net.ipv6.conf.all.disable_ipv6=1         # IPv6 deshabilitado
```

### 5. Hardening de Navegadores

**Script Firefox (`/usr/local/bin/firefox-anon.sh`):**
- Deshabilita WebRTC (previene fugas de IP)
- Activa resistencia a fingerprinting
- Bloquea telemetría
- Configura DNS sobre HTTPS
- Deshabilita geolocalización
- Configura política de cookies

**Ejecutar manualmente:**
```bash
/usr/local/bin/firefox-anon.sh
```

### 6. Limpieza Profunda

**Historiales eliminados:**
- `.bash_history`, `.zsh_history`
- `.python_history`, `.mysql_history`
- `.lesshst`, `.viminfo`

**Cache limpiado:**
- Thumbnails de escritorio
- Cache de navegadores (Firefox, Chrome, Chromium)
- Cache de APT
- Archivos temporales antiguos

**Logs rotados:**
- systemd-journald
- auth.log, syslog, kern.log

### 7. Desactivación de VM Tools

**Servicios deshabilitados:**
- VirtualBox Guest Additions
- VMware Tools
- QEMU Guest Agent
- Open VM Tools

### 8. Verificación y Reportes

**El script genera un reporte detallado** en `/var/log/anon-setup-report.txt`:
- Configuración aplicada
- MAC addresses (antes/después)
- Verificación de cambios
- IP pública (si curl disponible)
- Estado de servicios
- Ubicación del backup

---

## 📁 Estructura del Proyecto

```
anon-setup/
├── anon-setup.sh     # Script principal v2.0
├── README.md                  # Este archivo
├── LICENSE                    # Licencia GPL v3
├── config/
│   ├── anon-setup.conf        # Configuración de ejemplo
│   └── anon-setup.service     # Servicio systemd
├── scripts/
│   ├── firefox-anon.sh        # Hardening de Firefox (auto-generado)
│   └── uninstall.sh           # Script de desinstalación
├── tests/
│   ├── test-setup.sh          # Suite de tests
│   └── verify-anon.sh         # Verificación de anonimato
└── docs/
    ├── CHANGELOG.md           # Registro de cambios
    ├── CONTRIBUTING.md        # Guía de contribución
    └── SECURITY.md            # Política de seguridad
```

---

## 🔄 Revertir Cambios

### Método 1: Restauración Automática (Recomendado)

```bash
sudo anon-setup.sh --restore
```

### Método 2: Revertir Manualmente

```bash
# Eliminar reglas iptables
sudo iptables -D OUTPUT -j ANON_DNS 2>/dev/null || true
sudo iptables -F ANON_DNS 2>/dev/null || true
sudo iptables -X ANON_DNS 2>/dev/null || true

sudo ip6tables -D OUTPUT -j ANON_IPV6 2>/dev/null || true
sudo ip6tables -F ANON_IPV6 2>/dev/null || true
sudo ip6tables -X ANON_IPV6 2>/dev/null || true

# Restaurar servicios de VM
sudo systemctl enable --now vboxservice 2>/dev/null || true
sudo systemctl enable --now open-vm-tools 2>/dev/null || true

# Restaurar hostname (reemplazar con el original)
sudo hostnamectl set-hostname mi-hostname-original

# Re-habilitar IPv6
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=0

# Reiniciar NetworkManager
sudo systemctl restart NetworkManager
```

**⚠️ Se recomienda reiniciar después de revertir cambios.**

---

## 🛠️ Solución de Problemas

### Error: "Interfaz no detectada"

**Causa:** No se puede determinar la interfaz de red principal.

**Solución:**
```bash
# Listar interfaces disponibles
ip addr show

# Si conoces tu interfaz (ej: eth0), edita el script
# y fuerza la variable OUT_IF al inicio:
OUT_IF="eth0"  # Añadir después de la línea 40
```

### Error: "MAC no cambió"

**Causa:** Algunas interfaces o drivers no permiten cambiar la MAC.

**Solución:**
```bash
# Verificar si el driver soporta cambio de MAC
sudo ethtool -i eth0

# Si estás en VM, asegúrate de que el modo promiscuo esté habilitado
# VirtualBox: Settings → Network → Advanced → Promiscuous Mode: Allow All
```

### Error: "DNS no funciona después del script"

**Causa:** NetworkManager puede estar sobrescribiendo `/etc/resolv.conf`.

**Solución:**
```bash
# Verificar el gestor de DNS
systemd-resolve --status

# Si usa systemd-resolved, editar el servicio NetworkManager
sudo nano /etc/NetworkManager/NetworkManager.conf

# Añadir:
[main]
dns=none

# Reiniciar NetworkManager
sudo systemctl restart NetworkManager
```

### Error: "Permission denied" al escribir /etc/resolv.conf

**Causa:** El archivo puede estar protegido por `chattr` o ser un symlink.

**Solución:**
```bash
# Verificar atributos
lsattr /etc/resolv.conf

# Si está inmutable, quitar protección
sudo chattr -i /etc/resolv.conf

# Si es symlink a systemd-resolved
ls -la /etc/resolv.conf
sudo rm /etc/resolv.conf
sudo touch /etc/resolv.conf
```

### VPN Check falla pero VPN está activa

**Causa:** El script busca interfaces VPN estándar (tun0, wg0, etc).

**Solución:**
```bash
# Ejecutar sin verificación de VPN
sudo anon-setup.sh --skip-vpn-check

# O editar el script y añadir tu interfaz VPN personalizada
# Línea ~100, añadir a la lista:
for vpn_if in tun0 tap0 wg0 ppp0 tu_interfaz_vpn; do
```

### IPv6 sigue activo después del script

**Causa:** Algunos sistemas requieren deshabilitar IPv6 en GRUB.

**Solución:**
```bash
# Editar GRUB
sudo nano /etc/default/grub

# Añadir a GRUB_CMDLINE_LINUX:
ipv6.disable=1

# Actualizar GRUB
sudo update-grub

# Reiniciar
sudo reboot
```

### Notificaciones no aparecen

**Causa:** `notify-send` no está instalado o DISPLAY no está configurado.

**Solución:**
```bash
# Instalar libnotify
sudo apt install libnotify-bin

# Verificar DISPLAY
echo $DISPLAY

# Si ejecutas desde SSH, las notificaciones no funcionarán
# (esto es normal y no afecta la funcionalidad del script)
```

---

## 🧪 Testing y Verificación

### Script de Verificación Manual

```bash
#!/bin/bash
echo "=== VERIFICACIÓN DE ANONIMIZACIÓN ==="

echo -e "\n[1] MAC Address:"
ip link show | grep -A1 "state UP"

echo -e "\n[2] DNS Configuration:"
cat /etc/resolv.conf

echo -e "\n[3] Hostname:"
hostname

echo -e "\n[4] Timezone:"
cat /etc/timezone

echo -e "\n[5] Machine-ID:"
head -c 16 /etc/machine-id && echo "..."

echo -e "\n[6] Reglas iptables DNS:"
sudo iptables -L ANON_DNS -n -v

echo -e "\n[7] IPv6 Status:"
sysctl net.ipv6.conf.all.disable_ipv6

echo -e "\n[8] Test DNS:"
dig +short google.com

echo -e "\n[9] IP Pública:"
curl -s https://api.ipify.org

echo -e "\n[10] WebRTC Leak Test:"
echo "Visita: https://browserleaks.com/webrtc"

echo -e "\n=== FIN VERIFICACIÓN ==="
```

Guarda como `verify-anon.sh` y ejecuta:
```bash
chmod +x verify-anon.sh
./verify-anon.sh
```

### Tests de Anonimato Online

Visita estos sitios después de ejecutar el script:

1. **IP y DNS:**
   - https://ipleak.net
   - https://dnsleaktest.com

2. **Fingerprinting:**
   - https://coveryourtracks.eff.org
   - https://amiunique.org

3. **WebRTC:**
   - https://browserleaks.com/webrtc

4. **Headers:**
   - https://whatismybrowser.com

---

## 🤝 Contribuciones

¡Las contribuciones son bienvenidas y apreciadas! 

### Cómo Contribuir

1. **Fork** el proyecto
2. Crea una **rama** para tu feature:
   ```bash
   git checkout -b feature/AmazingFeature
   ```
3. **Commit** tus cambios:
   ```bash
   git commit -m 'Add: Descripción clara del cambio'
   ```
4. **Push** a la rama:
   ```bash
   git push origin feature/AmazingFeature
   ```
5. Abre un **Pull Request**

### Directrices de Contribución

- Código limpio y comentado
- Seguir el estilo del script existente
- Probar en múltiples distribuciones si es posible
- Actualizar documentación relevante
- Añadir entrada en CHANGELOG.md

### Áreas de Mejora Deseadas

- [ ] Soporte para más distribuciones (Alpine, Gentoo)
- [ ] Integración con Tor
- [ ] GUI opcional (Zenity/whiptail)
- [ ] Perfiles pre-configurados (paranoid, balanced, basic)
- [ ] Integración con proxychains
- [ ] Modo "stealth" vs "performance"
- [ ] Tests automatizados
- [ ] Internacionalización (i18n)

---

## 📄 Licencia

Este proyecto está licenciado bajo **GNU General Public License v3.0**.

Ver el archivo [LICENSE](LICENSE) para más detalles.

### Resumen de la Licencia

✅ **Permitido:**
- Uso comercial
- Modificación
- Distribución
- Uso privado

❌ **Prohibido:**
- Responsabilidad
- Garantía

⚠️ **Requerido:**
- Mismo license para derivados
- Divulgación del código fuente
- Notificación de cambios
- Copyleft

---

## ⚠️ Limitaciones y Advertencias

### Limitaciones Técnicas

- **No es anonimato completo**: Es una capa básica de ofuscación
- **Depende del entorno**: Algunas redes bloquean MACs aleatorias
- **No protege contra:**
  - Análisis de tráfico profundo
  - Fingerprinting avanzado de aplicaciones
  - Ataques de timing
  - Correlación de comportamiento

### Advertencias de Uso

⚠️ **Conectividad:**
- Algunas redes corporativas pueden bloquear MACs desconocidas
- Hotspots con autenticación pueden requerir MAC persistente
- Puede causar desconexiones temporales

⚠️ **Compatibilidad:**
- Principalmente diseñado para Debian/Ubuntu con systemd
- Puede requerir ajustes en otras distribuciones
- No funciona en contenedores Docker (requiere acceso a hardware)

⚠️ **Persistencia:**
- Los cambios se pierden al reiniciar (por diseño)
- Para persistencia, configura como servicio systemd
- El backup permite restaurar configuración original

⚠️ **Rendimiento:**
- Puede añadir latencia mínima por reglas iptables
- La limpieza de logs puede tardar en sistemas con mucho historial

---

## 🆘 Soporte

### Obtener Ayuda

1. **Revisa la documentación** (este README)
2. **Consulta los logs:**
   ```bash
   sudo tail -100 /var/log/anon-setup.log
   cat /var/log/anon-setup-report.txt
   ```
3. **Busca en Issues existentes** en GitHub
4. **Abre un nuevo Issue** con:
   - Versión del script (`grep VERSION anon-setup.sh`)
   - Distribución Linux (`cat /etc/os-release`)
   - Logs completos
   - Comportamiento esperado vs real


## 📊 Estado del Proyecto

![GitHub Issues](https://img.shields.io/github/issues/TraceVoid/Anon-Setup)
![GitHub Pull Requests](https://img.shields.io/github/issues-pr/TraceVoid/Anon-Setup)
![GitHub Stars](https://img.shields.io/github/stars/TraceVoid/Anon-Setup?style=social)
![GitHub Forks](https://img.shields.io/github/forks/TraceVoid/Anon-Setup?style=social)

**Última actualización:** Octubre 2025  
**Versión estable:** 2.0  
**Estado:** Poco Mantenimiento

---

## 🗺️ Roadmap

### v2.1 (Próximo Release)
- [ ] Perfiles de configuración (paranoid/balanced/basic)
- [ ] Integración con Tor
- [ ] GUI con Zenity
- [ ] Soporte para Alpine Linux

### v2.5 (Futuro)
- [ ] Tests automatizados
- [ ] Proxychains integration
- [ ] Browser profiles automáticos
- [ ] Cloud metadata spoofing

### v3.0 (Visión)
- [ ] Reescritura modular
- [ ] Plugin system
- [ ] Multi-idioma
- [ ] API REST opcional

---

## 📚 Referencias y Recursos

### Herramientas Relacionadas
- [Whonix](https://www.whonix.org/) - OS enfocado en anonimato
- [Tails](https://tails.boum.org/) - Live OS anónimo
- [Qubes OS](https://www.qubes-os.org/) - Security by compartmentalization

### Documentación Técnica
- [iptables Manual](https://netfilter.org/documentation/)
- [macchanger GitHub](https://github.com/alobbs/macchanger)
- [Linux Networking](https://www.kernel.org/doc/Documentation/networking/)

### Guías de Anonimato
- [EFF - Surveillance Self-Defense](https://ssd.eff.org/)
- [OWASP Testing Guide](https://owasp.org/www-project-web-security-testing-guide/)
- [PrivacyTools.io](https://www.privacytools.io/)

---

## ❓ FAQ

<details>
<summary><strong>¿Esto me hace 100% anónimo?</strong></summary>

No. Este script es una capa de ofuscación básica. El anonimato real requiere múltiples capas (VPN/Tor, comportamiento, OPSEC, etc.)
</details>

<details>
<summary><strong>¿Puedo usar esto en mi sistema principal?</strong></summary>

No recomendado. Está diseñado para VMs desechables. En un sistema principal puede causar problemas de conectividad y pérdida de datos en logs.
</details>

<details>
<summary><strong>¿Funciona con todas las VPN?</strong></summary>

El script es agnóstico a VPN. Solo verifica si existe una interfaz VPN activa (tun0, wg0, etc.). Funciona con cualquier VPN que cree estas interfaces.
</details>

<details>
<summary><strong>¿Por qué se recomienda reiniciar después?</strong></summary>

Para asegurar que todos los cambios (especialmente kernel parameters y servicios) se apliquen completamente y no haya procesos usando configuraciones antiguas.
</details>

<details>
<summary><strong>¿Puedo ejecutar esto múltiples veces?</strong></summary>

Sí, es idempotente. Cada ejecución sobrescribe la configuración anterior. Se recomienda restaurar antes de re-ejecutar para evitar múltiples backups.
</details>

<details>
<summary><strong>¿Afecta al rendimiento de red?</strong></summary>

Impacto mínimo. Las reglas iptables son eficientes. Puede haber latencia adicional de <5ms en DNS por el filtrado.
</details>

---

## ⭐ Si te gustó este proyecto

- Dale una ⭐ en GitHub
- Comparte con la comunidad
- Contribuye con código o documentación
- Report
