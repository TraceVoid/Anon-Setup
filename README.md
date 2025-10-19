Anon-Setup# Anon-Setup - Script de Anonimato para Máquinas Virtuales

![Shell Script](https://img.shields.io/badge/Shell_Script-121011?style=for-the-badge&logo=gnu-bash&logoColor=white)
![License](https://img.shields.io/badge/License-GPLv3-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Linux-lightgrey.svg)

## ⚠️ ADVERTENCIA LEGAL IMPORTANTE

**ESTE SOFTWARE ES SOLO PARA USOS LEGÍTIMOS:**

- Pentesting en entornos autorizados
- Laboratorios de seguridad
- Auditorías de seguridad
- Investigación forense
- Protección de privacidad en redes públicas

**NO USES ESTE SOFTWARE PARA:**
- Actividades ilegales
- Eludir medidas de seguridad sin autorización
- Atacar sistemas sin permiso

**El uso indebido de esta herramienta es responsabilidad exclusiva del usuario.**

## 📖 Descripción

`anon-setup` es un script de bash diseñado para aumentar el anonimato en máquinas virtuales durante pruebas de penetración y ejercicios de seguridad. Automatiza la configuración de varias capas de ofuscación.

## 🚀 Características

- **🔒 Ofuscación de MAC Address**: Cambio automático de dirección MAC
- **🌐 Configuración DNS Segura**: Fuerza el uso del gateway como DNS
- **🛡️ Reglas Firewall**: Bloquea fugas de DNS con iptables
- **🧹 Limpieza de Huellas**: Elimina historiales y regenera machine-id
- **⚡ Fácil Configuración**: Configuración modular y flexible

## 📋 Requisitos

- Sistema operativo Linux
- Acceso root/sudo
- Bash 4.0+
- Interfaces de red estándar

### Paquetes recomendados:
```bash
# Debian/Ubuntu
sudo apt update && sudo apt install macchanger iptables

# Red Hat/CentOS
sudo yum install macchanger iptables
```

## 🛠️ Instalación

```bash
# Descargar el script
https://github.com/TraceVoid/Anon-Setup.git
cd anon-setup

# Hacer ejecutable
chmod +x anon-setup.sh

# Ejecutar (requiere root)
sudo ./anon-setup.sh
```

## ⚙️ Configuración

Edita las variables en la sección de configuración del script:

```bash
# ---------- CONFIGURACION ----------
# Prefijo MAC personalizado (dejar vacío para MAC totalmente aleatoria)
MAC_PREFIX="02:00:00"

# Tiempo de espera para renovación DHCP (segundos)
DHCP_WAIT=3
# ------------------------------------
```

### Configuraciones disponibles:

| Variable | Descripción | Valor por defecto |
|----------|-------------|-------------------|
| `MAC_PREFIX` | Prefijo para dirección MAC | Vacío (aleatorio) |
| `DHCP_WAIT` | Espera tras cambio MAC | 3 segundos |
| `LOGFILE` | Archivo de log | `/var/log/anon-setup.log` |

## 📝 Uso

### Ejecución básica:
```bash
sudo ./anon-setup.sh
```

### Ver logs en tiempo real:
```bash
sudo tail -f /var/log/anon-setup.log
```

### Verificar cambios aplicados:
```bash
# Ver MAC address
ip link show

# Ver reglas iptables
sudo iptables -L ANON_DNS -n

# Ver configuración DNS
cat /etc/resolv.conf
```

## 🔧 Funcionalidades Detalladas

### 1. Ofuscación de MAC Address
- Cambio completo o parcial de dirección MAC
- Soporte para prefijos personalizados
- Compatible con `macchanger` o método nativo

### 2. Configuración DNS
- Fuerza el uso del gateway como servidor DNS
- Configura timeout y rotación de DNS
- Compatible con NetworkManager y config manual

### 3. Reglas de Firewall (iptables)
- Bloquea todo tráfico DNS no autorizado
- Permite solo DNS hacia el gateway
- Cadena dedicada `ANON_DNS` para fácil gestión

### 4. Limpieza de Huellas Digitales
- Regenera `/etc/machine-id`
- Limpia historiales de bash
- Limpia logs del journal systemd

### 5. Gestión de Servicios
- Deshabilita Guest Additions de VM
- Reconexión automática de red
- Renovación DHCP automática

## Estructura del Proyecto

```
anon-setup/
├── anon-setup.sh          # Script principal
├── README.md              # Este archivo
├── config/                # Configuraciones de ejemplo
│   └── anon-setup.conf
├── tests/                 # Scripts de prueba
│   └── test-setup.sh
└── uninstall.sh           # Script para revertir cambios
```

## 🔄 Revertir Cambios

Para revertir los cambios aplicados:

```bash
# Eliminar reglas iptables
sudo iptables -D OUTPUT -j ANON_DNS 2>/dev/null || true
sudo iptables -F ANON_DNS 2>/dev/null || true
sudo iptables -X ANON_DNS 2>/dev/null || true

# Restaurar servicios de VM (ejemplo para VirtualBox)
sudo systemctl enable vboxservice --now
```

**Se recomienda reiniciar la máquina después de usar el script.**

## 🐛 Solución de Problemas

### Error común: Interfaz no detectada
```bash
# Verificar interfaces disponibles
ip addr show

# Ejecutar con interfaz específica
# (Editar el script para forzar OUT_IF)
```

### Error: Permisos insuficientes
```bash
# Asegurarse de ejecutar como root
sudo ./anon-setup.sh
```

### Error: macchanger no disponible
```bash
# Instalar manualmente
sudo apt install macchanger
```

## 🤝 Contribuciones

Las contribuciones son bienvenidas. Por favor:

1. Fork el proyecto
2. Crea una rama para tu feature (`git checkout -b feature/AmazingFeature`)
3. Commit tus cambios (`git commit -m 'Add some AmazingFeature'`)
4. Push a la rama (`git push origin feature/AmazingFeature`)
5. Abre un Pull Request

## 📄 Licencia

Este proyecto está bajo la Licencia GPL v3. Ver el archivo `LICENSE` para más detalles.

## ⚠️ Limitaciones y Advertencias

- **No garantiza anonimato completo**: Esto es una herramienta básica
- **Puede afectar conectividad**: Algunas redes bloquean MAC aleatorias
- **Logs del sistema**: Algunos sistemas pueden mantener registros adicionales
- **Compatible principalmente con systemd**: Puede no funcionar en todas las distribuciones

## 🆘 Soporte

Si encuentras algún problema:
1. Revisa los logs en `/var/log/anon-setup.log`
2. Verifica que cumples los requisitos
3. Abre un issue en GitHub con la información del error

---

**¿Te fue útil este proyecto? ¡Dale una ⭐ en GitHub!**

---


¿Quieres que agregue alguna sección específica o modifique algo del README?
