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
| [schema.sql](schema.sql) | Toda la base de datos: creación de tablas y, al final, el historial de migraciones. |
| [requirements.txt](requirements.txt) | Dependencias de Python. |
| [finbot.service](finbot.service) | Servicio de systemd para que el bot corra siempre. |
| [deploy.sh](deploy.sh) | En el droplet: baja lo último de GitHub, instala dependencias y reinicia el bot. |
| [.github/workflows/deploy.yml](.github/workflows/deploy.yml) | Corre `deploy.sh` en el droplet en cada push a `main`. |
| [autorizar_drive.py](autorizar_drive.py) | Se corre en la Mac una vez para autorizar Google Drive. |

Los secretos (`.env`, `credentials.json`, `token.json`) **no** se suben a
GitHub; están en [.gitignore](.gitignore).

---

## Base de datos

Tablas: `gastos`, `ingresos`, `aportaciones` y los catálogos `categorias`,
`fuentes_ingreso` y `portafolios`.

[schema.sql](schema.sql) tiene dos partes:

1. **Arriba, los `CREATE TABLE`** con la estructura actual completa. Sirven
   para una instalación nueva.
2. **Abajo, `INICIO MIGRACIONES`**: el historial de cambios, uno por versión
   y separados con comentarios. Las migraciones ya aplicadas quedan
   **comentadas** como registro; solo la **última** está sin comentar.

El despliegue automático **no toca la base**: una migración solo se puede
correr una vez (borrar una columna dos veces da error), así que se aplica a
mano.

**Aplicar la migración pendiente** (una sola vez): en DBeaver, selecciona el
bloque sin comentar del final de `schema.sql` y ejecútalo como **script**
(**Option+X** en Mac, Alt+X en Windows). No uses Cmd+Enter: manda todo como
una sola sentencia y MySQL da error 1064. O desde el droplet:
```bash
sed -n '/^-- INICIO MIGRACIONES/,$p' /opt/finbot/schema.sql | mysql -u root -p
```
(El comando manda solo la parte de migraciones; las comentadas se ignoran.)
Después cambia `[PENDIENTE]` por `[APLICADA]` en su encabezado.

**Hacer un cambio nuevo a la base:**
1. Comenta la migración anterior (pon `-- ` al inicio de cada línea) y márcala `[APLICADA]`.
2. Escribe la nueva al final con su encabezado `vN (fecha) — qué cambia [PENDIENTE]`.
3. Actualiza los `CREATE TABLE` de arriba para que queden igual que la base después del cambio.
4. `git push` y aplica la migración como se explica arriba.

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

### 3. Bajar el proyecto de GitHub y crear el usuario de MySQL

El repo es privado, así que el droplet necesita una llave de **solo lectura**
(deploy key) para poder bajarlo. En el **droplet**:
```bash
ssh-keygen -t ed25519 -f /root/.ssh/github_finbot -N "" -C "droplet-finbot"
printf 'Host github.com\n  IdentityFile /root/.ssh/github_finbot\n' >> /root/.ssh/config
ssh-keyscan github.com >> /root/.ssh/known_hosts
cat /root/.ssh/github_finbot.pub
```
Copia lo que imprime la última línea y pégalo en GitHub → tu repo → **Settings
→ Deploy keys → Add deploy key** (título `droplet`, **sin** marcar "Allow write
access").

Luego, en el droplet (cambia `TU_USUARIO`):
```bash
git config --global --add safe.directory /opt/finbot
cd /opt/finbot && git init -q -b main && git remote add origin git@github.com:TU_USUARIO/finbot.git
git fetch origin main && git reset --hard origin/main
sed '/^-- INICIO MIGRACIONES/q' schema.sql | mysql -u root -p     # crea las tablas (sin migraciones)
mysql -u root -p -e "
CREATE USER 'finbot'@'localhost' IDENTIFIED BY 'PON_UNA_CONTRASEÑA';
GRANT ALL PRIVILEGES ON finbot.* TO 'finbot'@'localhost';
FLUSH PRIVILEGES;"
```
(Si `/opt/finbot` ya tenía archivos, el `reset --hard` los reemplaza por los de
GitHub; `.env`, `token.json` y `venv/` no se tocan.)

Si vienes de otro servidor con un respaldo `.sql`, restáuralo
(`mysql -u root -p finbot < respaldo.sql`) en lugar de crear las tablas y
aplica las migraciones de `schema.sql` que ese respaldo no tenga. Luego borra
el respaldo del servidor.

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
cd /opt/finbot && python3 -m venv venv
./deploy.sh
systemctl enable finbot        # que arranque solo si se reinicia el droplet
```
`deploy.sh` instala dependencias, instala el servicio y arranca el bot. Debe terminar en "Listo: finbot corriendo".

### 7. Probar

En Telegram: `GASTO` → Personal → `1 prueba` → ✅, luego `DESHACER` → Sí, y
`RESUMEN`.

---

## Despliegue automático (GitHub Actions)

Cada `git push` a `main` actualiza el droplet solo: GitHub entra por SSH y
corre [deploy.sh](deploy.sh), que hace `git pull`, instala dependencias y
reinicia el bot. Si el cambio incluye una migración de base, aplícala a mano
(ver [Base de datos](#base-de-datos)). El resultado se ve en GitHub →
pestaña **Actions** (✅ o ❌ con el error).

```bash
git add . && git commit -m "Describe el cambio" && git push
```

Para desplegar sin hacer push: GitHub → **Actions → Deploy → Run workflow**, o
desde la Mac `ssh root@LA_IP /opt/finbot/deploy.sh`.

### Configuración (una sola vez)

Requiere el paso 3 de la instalación (el droplet ya baja el repo de GitHub).

1. En la **Mac**, crea una llave solo para GitHub Actions:
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/finbot_actions -N "" -C "github-actions-finbot"
   ```
2. Autorízala en el droplet **restringida a correr solo `deploy.sh`** (aunque
   alguien la robara, no podría abrir una terminal ni hacer otra cosa). Desde
   la Mac:
   ```bash
   echo "command=\"/opt/finbot/deploy.sh\",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty $(cat ~/.ssh/finbot_actions.pub)" | ssh root@LA_IP 'cat >> /root/.ssh/authorized_keys'
   ```
3. Saca la huella del droplet para que GitHub sepa que se conecta al correcto:
   ```bash
   ssh-keyscan LA_IP 2>/dev/null
   ```
4. En GitHub → tu repo → **Settings → Secrets and variables → Actions → New
   repository secret**, crea tres:

   | Nombre | Valor |
   |---|---|
   | `DEPLOY_SSH_KEY` | Todo el contenido de `~/.ssh/finbot_actions` (la **privada**, sin `.pub`): `cat ~/.ssh/finbot_actions` |
   | `DROPLET_IP` | La IP del droplet |
   | `DROPLET_KNOWN_HOSTS` | Todo lo que imprimió el paso 3 |

5. Prueba: **Actions → Deploy → Run workflow**.

Si tienes un firewall de DigitalOcean que solo deja entrar SSH desde tu casa,
GitHub no podrá conectarse; en ese caso usa `ssh root@LA_IP /opt/finbot/deploy.sh`.

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
