# Finbot — Guía de despliegue en DigitalOcean

Versión simple: un solo droplet que corre el bot y MySQL juntos.
Costo fijo con tope mensual (sin sorpresas). Con $200 de crédito gratis los
primeros 60 días.

Archivos: bot.py, schema.sql, migracion_v3.sql, requirements.txt, finbot.service,
autorizar_drive.py.

> **¿Ya tienes el bot corriendo (v2)?** Salta a
> [Actualizar a v3](#actualizar-a-v3-desde-v2).

Tiempo estimado: ~45-60 min la primera vez.

---

## PARTE 0 — Ten listo tu respaldo

Ya tienes el respaldo de tu base (el .sql que exportaste de AWS). Tenlo a la
mano; lo restaurarás en la Parte 4.

---

## PARTE 1 — Crea el droplet en DigitalOcean

1. Crea cuenta en digitalocean.com (te dan $200 de crédito por 60 días).
2. Botón **Create** → **Droplets**.
3. Configura:
   - **Region**: New York o San Francisco (buena latencia desde México).
   - **Image**: Ubuntu 24.04 LTS
   - **Droplet type**: Basic
   - **CPU**: Regular → elige el de **$6/mes (1 GB RAM / 1 vCPU / 25 GB)**.
     (No el de $4: 512 MB queda justo para bot + MySQL juntos.)
   - **Authentication**: SSH Key (recomendado) o Password.
   - **Hostname**: `finbot`
4. **Create Droplet**. En un minuto tienes la IP pública.

---

## PARTE 2 — Conéctate e instala lo básico

Desde tu Mac:
```bash
ssh root@LA_IP_DEL_DROPLET
```

Ya dentro:
```bash
apt update && apt upgrade -y
apt install -y python3-venv python3-pip mysql-server git
useradd -m -s /bin/bash finbot
mkdir -p /opt/finbot
```

---

## PARTE 3 — Configura MySQL

```bash
mysql_secure_installation
# contraseña root fuerte, "Y" a casi todo
```

---

## PARTE 4 — Sube el proyecto y restaura tus datos

Desde tu **Mac** (otra terminal), en la carpeta del proyecto:
```bash
cd ruta/donde/tengas/finbot-vps
scp bot.py schema.sql requirements.txt finbot.service root@LA_IP:/opt/finbot/
scp tu-respaldo.sql root@LA_IP:/opt/finbot/
```

De vuelta en el **droplet**:
```bash
mysql -u root -p < /opt/finbot/schema.sql
mysql -u root -p finbot < /opt/finbot/tu-respaldo.sql

mysql -u root -p -e "
CREATE USER 'finbot'@'localhost' IDENTIFIED BY 'PON_UNA_CONTRASEÑA';
GRANT ALL PRIVILEGES ON finbot.* TO 'finbot'@'localhost';
FLUSH PRIVILEGES;"
```

> Nota: si tu respaldo ya incluye los CREATE TABLE, quizás no necesites correr
> schema.sql aparte. Si el respaldo da error de "tabla ya existe", ignóralo o
> restaura solo el respaldo. Lo importante es que al final existan las 7 tablas
> con tus datos.

---

## PARTE 5 — Autoriza Google Drive (una vez)

Solo se suben las fotos de tickets **>= $2,000**.

1. console.cloud.google.com → nuevo proyecto → activa **Google Drive API**.
2. **APIs & Services → OAuth consent screen** (o "Google Auth Platform →
   Audience"): tipo **External** y en **Publishing status** presiona
   **PUBLISH APP** para que quede **In production**.
   > ⚠️ **Este paso es el que evita que se rompa.** Si la app se queda en
   > "Testing", Google invalida el token **cada 7 días** y la subida de
   > fotos deja de funcionar (error `invalid_grant` en los logs). Como solo
   > pedimos el permiso `drive.file` (el bot solo ve los archivos que él
   > mismo crea), no necesitas que Google verifique la app.
3. Crea credenciales **OAuth Client ID** (Desktop app) → descarga
   `credentials.json`.
4. Crea una carpeta en tu Drive para los tickets; copia su **ID** de la URL.
5. En tu Mac (en la carpeta del proyecto):
   ```bash
   source venv-drive/bin/activate
   python3 autorizar_drive.py
   ```
   Autoriza en el navegador. Como la app no está verificada, Google muestra
   "Google no verificó esta app": da clic en **Configuración avanzada → Ir a
   (nombre de tu app)**. Es tu propia app, es seguro. Se genera `token.json`.
6. Súbelo al droplet:
   ```bash
   scp token.json root@LA_IP:/opt/finbot/
   ```

### Si la subida a Drive vuelve a fallar

1. Revisa el error:
   ```bash
   journalctl -u finbot --since "3 days ago" | grep -i -A5 drive
   ```
2. Si dice `invalid_grant` o `Token has been expired or revoked`:
   - Confirma que la app esté **In production** (paso 2). Si estaba en
     Testing, publícala.
   - Regenera el token (pasos 5 y 6) y reinicia: `systemctl restart finbot`.
   - El token también se invalida si cambias tu contraseña de Google o si
     quitas el acceso en myaccount.google.com → Seguridad → Apps de terceros.
3. Si dice `File not found` con el ID de la carpeta: revisa
   `GDRIVE_FOLDER_ID` en el `.env`.

---

## PARTE 6 — Variables de entorno

En el droplet, crea `/opt/finbot/.env`:
```bash
nano /opt/finbot/.env
```
```
TELEGRAM_TOKEN=tu-token
MI_CHAT_ID=tu-chat-id
ANTHROPIC_API_KEY=tu-api-key
GDRIVE_FOLDER_ID=id-de-la-carpeta-drive
MYSQL_HOST=127.0.0.1
MYSQL_USER=finbot
MYSQL_PASSWORD=la-contraseña-del-paso-4
MYSQL_DB=finbot
```

> La API key: console.anthropic.com → API Keys. Agrega ~$5 de saldo (dura
> meses). Es SEPARADA de tu suscripción Claude Pro.

---

## PARTE 7 — Instala dependencias y arranca

```bash
cd /opt/finbot
python3 -m venv venv
venv/bin/pip install -r requirements.txt
chown -R finbot:finbot /opt/finbot

cp /opt/finbot/finbot.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable finbot
systemctl start finbot
systemctl status finbot   # debe decir "active (running)"
```

---

## PARTE 8 — Pruébalo

En Telegram:
- `GASTO` → Personal / Pareja / Vacaciones → foto del ticket → ✓
  (si es >= $2,000 debe decir "📎 Foto guardada")
- `RESUMEN` → te manda el resumen del mes (también llega solo a las 10:00 CDMX)
- `INGRESO` → fuente → monto
- `AHORRO` → portafolio → monto

---

## Actualizar a v3 (desde v2)

Cambios: fotos a Drive solo >= $2,000, fechas en hora CDMX, solo 3 cuentas
de ahorro, categoría Vacaciones y resumen diario a las 10:00.

1. Arregla Drive: publica la app (**In production**) y regenera `token.json`
   (PARTE 5, pasos 2, 5 y 6).
2. Desde tu **Mac**:
   ```bash
   scp bot.py requirements.txt migracion_v3.sql token.json root@LA_IP:/opt/finbot/
   ```
3. En el **droplet**:
   ```bash
   mysql -u root -p < /opt/finbot/migracion_v3.sql
   cd /opt/finbot && venv/bin/pip install -r requirements.txt
   chown -R finbot:finbot /opt/finbot
   systemctl restart finbot
   journalctl -u finbot -n 30 --no-pager   # revisa que no haya errores
   ```
4. Manda `RESUMEN` en Telegram para probar.

La migración muestra los gastos cuya fecha quedó corrida por la zona horaria;
revísalos y, si quieres corregirlos, sigue el paso 3 dentro de `migracion_v3.sql`.

---

## Día a día

```bash
journalctl -u finbot -f      # ver logs en vivo
systemctl restart finbot     # reiniciar tras un cambio
systemctl status finbot      # ver estado
```

---

## Conectar DBeaver

Opción segura (túnel SSH, sin exponer MySQL):
1. DBeaver → nueva conexión MySQL.
2. Host: `127.0.0.1`, usuario `finbot`, puerto 3306.
3. Pestaña **SSH**: activa, Host = IP del droplet, usuario `root` (o tu SSH).
Así te conectas por el túnel y MySQL nunca queda expuesto a internet.

---

## Respaldo automático (muy recomendado)

En el droplet, primero guarda la contraseña en un archivo que solo root puede
leer (así no queda escrita en el cron ni visible en `ps`):
```bash
printf '[mysqldump]\nuser=finbot\npassword=LA_CONTRASEÑA_DE_MYSQL\n' > /root/.my.cnf
chmod 600 /root/.my.cnf
mkdir -p /root/backups
```
Luego `crontab -e` (abre un editor; la línea se pega **dentro** del editor,
no en la terminal) y agrega al final:
```
0 3 * * * mysqldump finbot > /root/backups/finbot-$(date +\%F).sql && find /root/backups -name 'finbot-*.sql' -mtime +30 -delete
```
Guarda y sal (en nano: Ctrl+O, Enter, Ctrl+X). Hace un respaldo diario a las
3:00 (hora del servidor) y borra los de más de 30 días. Revisa con `crontab -l`.
Opcional: activa los **backups automáticos** del droplet en el panel de
DigitalOcean (cuestan 20-30% extra, pero son a prueba de todo).

---

## Control de costos

- El droplet tiene **tope mensual**: nunca pasa de ~$6 USD aunque corra 24/7.
- Vigila el gasto en el panel: **Billing** muestra el consumo en tiempo real.
- Con el crédito de $200, los primeros ~2 meses son gratis.

| Concepto | Costo |
|---|---|
| Droplet $6/mes | ~$110 MXN (gratis con crédito al inicio) |
| Google Drive | $0 (ya lo pagas) |
| API Anthropic | ~$1-3 USD |
| **Total** | **~$130-170 MXN/mes, fijo y con tope** |
