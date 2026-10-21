# Finbot

Bot de Telegram para llevar mis finanzas personales: registra gastos (con foto
del ticket o por texto), ingresos y ahorro en MySQL, y todos los días a las
10:00 (hora CDMX) me manda un resumen del mes con cuánto le toca pagar a cada
quien de los gastos en pareja.

Todo corre en un solo proceso de Python ([bot.py](bot.py)), en un droplet de
DigitalOcean con MySQL en el mismo servidor.

---

## Cómo funciona

### Comandos (en Telegram, mayúsculas o minúsculas)

| Comando | Qué hace |
|---|---|
| `GASTO` | Pregunta el tipo (**Personal / Pareja / Vacaciones**) y luego esperas la foto del ticket o un texto como `120 uber`. |
| *(foto)* | La IA lee el ticket (descripción, monto, categoría) y guarda el gasto. |
| *(texto)* `120 uber` | Gasto rápido: la IA interpreta el texto y lo guarda. |
| `INGRESO` | Elige la fuente → escribe el monto (negativo = retiro). |
| `AHORRO` | Elige la cuenta (PROFUTURO, ACTIVA, MERCADO PAGO) → escribe el monto (negativo = retiro). |
| `RESUMEN` | Manda el resumen del mes en ese momento. |
| `DESHACER` | Muestra el último gasto y pregunta si lo borras (botones Sí / No). |

Si mandas una foto o un texto sin escribir `GASTO` antes, el gasto se guarda
como **Personal**.

### Mensajes automáticos (10:00 hora CDMX)

- **Resumen diario:** todos los días. Cubre del día 1 del mes a hoy:
  ```
  📊 Resumen de octubre (01–12)

  👤 Personales: 3 mov · $1,000.00
  👥 Pareja: 3 mov · $3,300.00
      🏖️ de ellos Vacaciones: 1 mov · $2,200.00

  💰 Total: 6 mov · $4,300.00
  🙋 Pago yo: $2,800.00
  💑 Pago pareja: $1,500.00
  ```
- **Quincena:** los días **15 y último de cada mes**, justo después del
  resumen. Es el recordatorio de cómo repartir la quincena (apartados,
  disponible y checklist). El renglón de los vales solo sale a fin de mes. No
  hay comando para pedirlo; solo llega solo.

### Reglas de negocio

- **Pareja:** los gastos de pareja se reparten según los ingresos de cada uno,
  `INGRESO_YO` (60,000) e `INGRESO_PAREJA` (50,000). Es decir, yo pago 54.55 %
  y mi pareja 45.45 %. Los gastos personales los pago yo al 100 %.
- **Vacaciones:** funcionan exactamente igual que pareja (`es_pareja = 1`) y
  además se marcan con `es_vacaciones = 1`, para poder separarlos y ver cuánto
  llevamos del viaje.
- **Fotos:** solo se suben a Google Drive las de tickets de **$2,000 o más**
  (`MONTO_MIN_FOTO`). Si la subida falla, el gasto se guarda igual y el bot
  avisa.
- **Fechas:** todo se registra en **hora de CDMX**, no en la del servidor, para
  que los gastos de la noche no caigan en el día (o el mes) siguiente.
- **Facturación:** la IA marca `se_sugiere_facturar` si el gasto parece
  deducible ante el SAT (orientativo, no es asesoría fiscal).
- **Seguridad:** el bot solo responde a mi chat (`MI_CHAT_ID`); ignora a
  cualquier otra persona.

### Dónde cambiar las cosas

Todo está en [bot.py](bot.py), en constantes al inicio de cada sección:

| Qué | Constante |
|---|---|
| Ingresos para el reparto de pareja | `INGRESO_YO`, `INGRESO_PAREJA` |
| Monto mínimo para guardar la foto | `MONTO_MIN_FOTO` |
| Texto del recordatorio de quincena | `QUINCENA`, `QUINCENA_FIN_DE_MES`, `QUINCENA_CIERRE` |
| Hora de los mensajes automáticos | `run_daily(...)` dentro de `main()` |

Las cuentas de ahorro se controlan en la base: solo aparecen las de la tabla
`portafolios` con `activo = 1`.

---

## Archivos

| Archivo | Para qué |
|---|---|
| [bot.py](bot.py) | Todo el bot. |
| [schema.sql](schema.sql) | Toda la base de datos: creación **y** migraciones. |
| [requirements.txt](requirements.txt) | Dependencias de Python. |
| [finbot.service](finbot.service) | Servicio de systemd para que el bot corra siempre. |
| [autorizar_drive.py](autorizar_drive.py) | Se corre en la Mac una vez para autorizar Google Drive. |

Los secretos (`.env`, `credentials.json`, `token.json`) **no** se suben a
GitHub; están en [.gitignore](.gitignore).

---

## Base de datos

Tablas: `gastos`, `ingresos`, `aportaciones` y los catálogos `categorias`,
`fuentes_ingreso` y `portafolios`.

[schema.sql](schema.sql) se puede correr **siempre** y las veces que sea:

- En una base nueva crea todas las tablas y los catálogos.
- En una base existente solo aplica los cambios que le falten (por ejemplo,
  agregar `es_vacaciones` o quitar columnas viejas) y no toca tus datos.

```bash
mysql -u root -p < /opt/finbot/schema.sql
```

Para cambiar la estructura en el futuro: actualiza el `CREATE TABLE` (sección 1)
**y** agrega el paso equivalente en la sección 2 (migraciones), con su
condición para que solo corra si hace falta.

---

## Instalación desde cero (DigitalOcean)

Tiempo estimado: 45–60 min la primera vez.

### 1. Crear el droplet

1. digitalocean.com → **Create** → **Droplets**.
2. Region: New York o San Francisco · Image: **Ubuntu 24.04 LTS** · Basic →
   Regular → **$6/mes (1 GB RAM)** (el de $4 queda justo para bot + MySQL) ·
   Authentication: **SSH Key** · Hostname: `finbot`.
3. **Create Droplet** y anota la IP.

### 2. Instalar lo básico

```bash
ssh root@LA_IP
apt update && apt upgrade -y
apt install -y python3-venv python3-pip mysql-server git
useradd -m -s /bin/bash finbot
mkdir -p /opt/finbot
mysql_secure_installation      # contraseña root fuerte, "Y" a casi todo
```

### 3. Subir el proyecto y crear la base

Desde la **Mac**, en la carpeta del proyecto:
```bash
scp bot.py schema.sql requirements.txt finbot.service root@LA_IP:/opt/finbot/
```

En el **droplet**:
```bash
mysql -u root -p < /opt/finbot/schema.sql
mysql -u root -p -e "
CREATE USER 'finbot'@'localhost' IDENTIFIED BY 'PON_UNA_CONTRASEÑA';
GRANT ALL PRIVILEGES ON finbot.* TO 'finbot'@'localhost';
FLUSH PRIVILEGES;"
```

Si vienes de otro servidor con un respaldo `.sql`, restáuralo
(`mysql -u root -p finbot < respaldo.sql`) y **después** vuelve a correr
`schema.sql` para que quede actualizado. Luego borra el respaldo del servidor.

### 4. Autorizar Google Drive (una vez)

1. console.cloud.google.com → nuevo proyecto → activa **Google Drive API**.
2. **Google Auth Platform → Branding:** llena App name (`Finbot`; no uses
   "Google" ni "Drive"), tu correo de soporte y de contacto, y una página
   pública para Home page y Privacy policy (puede ser la misma: una página de
   Notion publicada o de GitHub Pages diciendo que es una app personal que solo
   sube fotos a tu Drive). No subas logo: eso obliga a una revisión de Google.
3. **Google Auth Platform → Audience:** tipo **External** → **PUBLISH APP**
   para que quede **In production**.
   > ⚠️ **Este paso evita que se rompa.** En modo "Testing", Google invalida el
   > token **cada 7 días** y las fotos dejan de subirse (`invalid_grant`).
   > Como el bot solo usa el permiso `drive.file` (solo ve los archivos que él
   > mismo sube), Google no necesita verificar la app.
4. **Clients → Create client → Desktop app** → descarga `credentials.json` a
   la carpeta del proyecto.
5. Crea una carpeta en Drive para los tickets y copia su **ID** (lo que va
   después de `/folders/` en la URL).
6. En la **Mac**:
   ```bash
   python3 -m venv venv-drive
   venv-drive/bin/pip install google-auth-oauthlib google-api-python-client
   venv-drive/bin/python autorizar_drive.py
   ```
   Autoriza en el navegador. Si sale "Google no verificó esta app", da clic en
   **Configuración avanzada → Ir a Finbot** (es tu propia app). Se genera
   `token.json`.
7. Súbelo: `scp token.json root@LA_IP:/opt/finbot/`

### 5. Variables de entorno

En el droplet, `nano /opt/finbot/.env`:
```
TELEGRAM_TOKEN=tu-token-de-botfather
MI_CHAT_ID=tu-chat-id
ANTHROPIC_API_KEY=tu-api-key
GDRIVE_FOLDER_ID=id-de-la-carpeta-drive
MYSQL_HOST=127.0.0.1
MYSQL_USER=finbot
MYSQL_PASSWORD=la-contraseña-del-paso-3
MYSQL_DB=finbot
```
La API key sale de console.anthropic.com → API Keys (con ~$5 USD de saldo
alcanza para meses; es independiente de la suscripción de Claude).

### 6. Instalar y arrancar

```bash
cd /opt/finbot
python3 -m venv venv
venv/bin/pip install -r requirements.txt
chown -R finbot:finbot /opt/finbot
cp finbot.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now finbot
systemctl status finbot        # debe decir "active (running)"
```

### 7. Probar

En Telegram: `GASTO` → Personal → `1 prueba` → ✅, luego `DESHACER` → Sí, y
`RESUMEN`.

---

## Actualizar el servidor

Cada vez que cambie algo:

Desde la **Mac**:
```bash
scp bot.py schema.sql requirements.txt root@LA_IP:/opt/finbot/
```

En el **droplet**:
```bash
mysql -u root -p < /opt/finbot/schema.sql
cd /opt/finbot && venv/bin/pip install -r requirements.txt
chown -R finbot:finbot /opt/finbot
systemctl restart finbot
journalctl -u finbot -n 30 --no-pager      # revisar que no haya errores
```

Y guardar el cambio en GitHub:
```bash
git add . && git commit -m "Describe el cambio" && git push
```

---

## Operación y problemas comunes

```bash
journalctl -u finbot -f        # logs en vivo
systemctl restart finbot       # reiniciar
systemctl status finbot        # estado
```

**Las fotos dejaron de subirse a Drive.** Revisa el error:
```bash
journalctl -u finbot --since "3 days ago" | grep -i -A5 drive
```
- `invalid_grant` / `Token has been expired or revoked`: confirma que la app
  esté **In production** (paso 4.3), regenera `token.json` (pasos 4.6 y 4.7) y
  reinicia. El token también se invalida si cambias la contraseña de Google o
  quitas el acceso en myaccount.google.com → Seguridad.
- `File not found` con el ID de la carpeta: revisa `GDRIVE_FOLDER_ID`.

**No llega la confirmación de un gasto.** Revisa los logs. Si la IA puso `*` o
`_` en la descripción, Telegram puede rechazar el mensaje aunque el gasto sí
se haya guardado.

### Conectar DBeaver (sin exponer MySQL a internet)

Nueva conexión MySQL → Host `127.0.0.1`, puerto 3306, usuario `finbot`. En la
pestaña **SSH**: actívala con Host = IP del droplet y tu usuario SSH.

---

## Costos

| Concepto | Costo aprox. |
|---|---|
| Droplet $6 USD/mes (con tope) | ~$110 MXN |
| Google Drive | $0 |
| API de Anthropic | ~$1–3 USD |
| **Total** | **~$130–170 MXN/mes** |
