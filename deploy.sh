#!/usr/bin/env bash
# Despliega en el droplet la última versión de main (código y dependencias).
# La base NO se toca: las migraciones de schema.sql se corren a mano una vez.
# Lo ejecuta GitHub Actions en cada push, o a mano: ssh root@LA_IP /opt/finbot/deploy.sh
set -euo pipefail
cd /opt/finbot

echo "==> Bajando la última versión de GitHub"
git fetch --quiet origin main
git reset --hard origin/main   # .env, token.json y venv no se tocan (están en .gitignore)
git log -1 --format="    %h %s"

echo "==> Dependencias"
venv/bin/pip install --quiet -r requirements.txt

echo "==> Reiniciando el bot"
chown -R finbot:finbot /opt/finbot
cp finbot.service /etc/systemd/system/finbot.service
systemctl daemon-reload
systemctl restart finbot
sleep 5
systemctl is-active --quiet finbot || { journalctl -u finbot -n 30 --no-pager; exit 1; }
echo "==> Listo: finbot corriendo"
