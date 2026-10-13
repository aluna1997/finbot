"""
Finbot (VPS) — un solo proceso que hace todo.
Sin Lambda, sin SQS, sin Bedrock, sin S3.

Flujos:
  - GASTO           -> Personal / Pareja / Vacaciones -> foto o "120 uber"
  - Foto de ticket  -> gasto; IA lee el ticket
  - Texto "120 uber" -> gasto rápido
  - INGRESO         -> elige fuente -> monto
  - AHORRO          -> elige portafolio -> monto
  - RESUMEN         -> resumen del mes (también llega solo a las 10:00 CDMX)
  (La conciliación se hace a mano en DBeaver.)

Arquitectura simple: como es un solo usuario, procesamos el ticket con la IA
en el momento. Toma un par de segundos; para un uso personal está bien.
Las fotos de tickets >= $2,000 se suben a Google Drive (carpeta que tú indiques).
"""
import io
import os
import json
import base64
import logging
import datetime as dt
from decimal import Decimal, InvalidOperation
from zoneinfo import ZoneInfo

import httpx
import mysql.connector
from PIL import Image
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application, MessageHandler, CallbackQueryHandler, filters,
)

# Google Drive
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
from googleapiclient.http import MediaIoBaseUpload

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("finbot")

# ---------------- Configuración (de variables de entorno) ----------------
TG_TOKEN = os.environ["TELEGRAM_TOKEN"]
MI_CHAT_ID = int(os.environ["MI_CHAT_ID"])
ANTHROPIC_KEY = os.environ["ANTHROPIC_API_KEY"]
GDRIVE_FOLDER_ID = os.environ["GDRIVE_FOLDER_ID"]  # carpeta destino en Drive

# Hora local de CDMX (sin horario de verano desde 2022, por eso offset fijo en MySQL)
TZ = ZoneInfo("America/Mexico_City")

DB = dict(
    host=os.environ.get("MYSQL_HOST", "127.0.0.1"),
    user=os.environ["MYSQL_USER"],
    password=os.environ["MYSQL_PASSWORD"],
    database=os.environ.get("MYSQL_DB", "finbot"),
    time_zone="-06:00",  # CURRENT_DATE / NOW() en hora CDMX, no del servidor
)

MONTO_MIN_FOTO = Decimal("2000")  # solo se guarda la foto de tickets >= a esto

# Proporción de los gastos de pareja según ingresos
INGRESO_YO = Decimal("60000")
INGRESO_PAREJA = Decimal("50000")

DEDUCIBLES_SAT = [
    "honorarios médicos, dentales y psicológicos", "gastos hospitalarios",
    "lentes ópticos graduados (con tope)", "gastos funerarios",
    "primas de seguros de gastos médicos", "colegiaturas (con tope por nivel)",
    "transporte escolar obligatorio", "intereses reales de crédito hipotecario",
    "aportaciones voluntarias al retiro (Afore)",
    "donativos a donatarias autorizadas",
]

# ---------------- Utilidades de base de datos ----------------

def db_run(sql, params=(), fetch=None):
    cn = mysql.connector.connect(**DB)
    try:
        cur = cn.cursor()
        cur.execute(sql, params)
        if fetch == "one":
            row = cur.fetchone()
        elif fetch == "all":
            row = cur.fetchall()
        else:
            row = cur.lastrowid
        cn.commit()
        return row
    finally:
        cn.close()


def cat_id(desc):
    r = db_run("SELECT id FROM categorias WHERE descripcion=%s", (desc.upper(),), "one")
    return r[0] if r else None


def forma_id(desc):
    if not desc:
        return None
    r = db_run("SELECT id FROM formas_pago WHERE descripcion=%s", (desc.upper(),), "one")
    return r[0] if r else None


# ---------------- Google Drive ----------------

def subir_foto(data: bytes) -> str:
    """Sube la foto a la carpeta de Drive y devuelve su liga."""
    # token.json se genera una vez con autorizar_drive.py (ver GUIA, PARTE 5)
    creds = Credentials.from_authorized_user_file("/opt/finbot/token.json")
    svc = build("drive", "v3", credentials=creds)
    meta = {"name": f"ticket-{dt.datetime.now(TZ):%Y%m%d-%H%M%S}.jpg",
            "parents": [GDRIVE_FOLDER_ID]}
    media = MediaIoBaseUpload(io.BytesIO(data), mimetype="image/jpeg")
    archivo = svc.files().create(body=meta, media_body=media, fields="id,webViewLink").execute()
    return archivo.get("webViewLink", archivo.get("id"))


# ---------------- IA: leer ticket con la API de Anthropic ----------------

def leer_ticket(imagen_b64=None, texto=None):
    cats = [c[0] for c in db_run("SELECT descripcion FROM categorias", fetch="all")]
    formas = [f[0] for f in db_run("SELECT descripcion FROM formas_pago", fetch="all")]
    sistema = (
        "Eres un asistente de gastos personales en México. Devuelve SOLO un JSON "
        '{"descripcion","monto","categoria","forma_pago","se_sugiere_facturar"}. '
        f"Categorías válidas: {', '.join(cats)}. Formas de pago: {', '.join(formas)}. "
        "descripcion en MAYÚSCULAS. se_sugiere_facturar=true SOLO si el gasto encaja "
        f"en deducciones del SAT para sueldos y salarios: {'; '.join(DEDUCIBLES_SAT)}. "
        "Es orientativo, no asesoría fiscal."
    )
    if imagen_b64:
        contenido = [
            {"type": "image", "source": {"type": "base64",
             "media_type": "image/jpeg", "data": imagen_b64}},
            {"type": "text", "text": "Extrae los datos de este ticket."}]
    else:
        contenido = [{"type": "text", "text": f"Gasto: {texto}"}]

    r = httpx.post(
        "https://api.anthropic.com/v1/messages",
        headers={"x-api-key": ANTHROPIC_KEY, "anthropic-version": "2023-06-01",
                 "content-type": "application/json"},
        json={"model": "claude-haiku-4-5-20251001", "max_tokens": 400,
              "system": sistema,
              "messages": [{"role": "user", "content": contenido}]},
        timeout=60)
    r.raise_for_status()
    txt = r.json()["content"][0]["text"].replace("```json", "").replace("```", "").strip()
    return json.loads(txt)


def comprimir(raw, max_lado=1600, calidad=70):
    img = Image.open(io.BytesIO(raw)).convert("RGB")
    img.thumbnail((max_lado, max_lado))
    out = io.BytesIO()
    img.save(out, format="JPEG", quality=calidad, optimize=True)
    return out.getvalue()


# ---------------- Handlers de Telegram ----------------

def solo_yo(update: Update) -> bool:
    return update.effective_chat and update.effective_chat.id == MI_CHAT_ID


async def cmd_gasto(update, context):
    if not solo_yo(update):
        return
    botones = [[InlineKeyboardButton("Personal", callback_data="tipo_personal"),
                InlineKeyboardButton("Pareja", callback_data="tipo_pareja"),
                InlineKeyboardButton("Vacaciones", callback_data="tipo_vacaciones")]]
    await update.message.reply_text("¿De qué tipo es el gasto?",
                                    reply_markup=InlineKeyboardMarkup(botones))


async def cmd_ingreso(update, context):
    if not solo_yo(update):
        return
    fuentes = db_run("SELECT id, descripcion FROM fuentes_ingreso ORDER BY descripcion", fetch="all")
    botones = [[InlineKeyboardButton(d, callback_data=f"fuente_{i}")] for i, d in fuentes]
    await update.message.reply_text("¿A qué fuente?",
                                    reply_markup=InlineKeyboardMarkup(botones))


async def cmd_ahorro(update, context):
    if not solo_yo(update):
        return
    ports = db_run("SELECT id, descripcion FROM portafolios WHERE activo ORDER BY descripcion",
                   fetch="all")
    botones = [[InlineKeyboardButton(d, callback_data=f"port_{i}")] for i, d in ports]
    await update.message.reply_text("¿A qué portafolio?",
                                    reply_markup=InlineKeyboardMarkup(botones))


async def on_callback(update, context):
    if not solo_yo(update):
        return
    q = update.callback_query
    await q.answer()
    data = q.data
    if data.startswith("tipo_"):
        context.user_data["tipo"] = data.split("_")[1]
        await q.edit_message_text("Ok. Manda la foto del ticket (o: monto descripción).")
    elif data.startswith("fuente_"):
        context.user_data["esperando"] = "monto_ingreso"
        context.user_data["fuente_id"] = int(data.split("_")[1])
        await q.edit_message_text("¿Cuánto? (número, negativo = retiro)")
    elif data.startswith("port_"):
        context.user_data["esperando"] = "monto_ahorro"
        context.user_data["portafolio_id"] = int(data.split("_")[1])
        await q.edit_message_text("¿Cuánto? (número, negativo = retiro)")


def parse_monto(texto):
    try:
        return Decimal(texto.replace(",", "").replace("$", "").strip()).quantize(Decimal("0.01"))
    except InvalidOperation:
        return None


async def on_text(update, context):
    if not solo_yo(update):
        return
    texto = (update.message.text or "").strip()

    # ¿esperando un monto de ingreso o ahorro?
    esperando = context.user_data.get("esperando")
    if esperando == "monto_ingreso":
        monto = parse_monto(texto)
        if monto is None:
            await update.message.reply_text("Monto inválido.")
            return
        try:
            db_run("INSERT INTO ingresos (fuente_id, monto) VALUES (%s,%s)",
                   (context.user_data["fuente_id"], monto))
            context.user_data.clear()
            await update.message.reply_text(
                f"✅ *Ingreso registrado*\n💵 ${monto:,.2f}", parse_mode="Markdown")
        except Exception as e:
            log.exception("Error guardando ingreso")
            await update.message.reply_text(
                f"❌ *Error al guardar el ingreso.*\n`{e}`", parse_mode="Markdown")
        return
    if esperando == "monto_ahorro":
        monto = parse_monto(texto)
        if monto is None:
            await update.message.reply_text("Monto inválido.")
            return
        try:
            db_run("INSERT INTO aportaciones (portafolio_id, monto) VALUES (%s,%s)",
                   (context.user_data["portafolio_id"], monto))
            context.user_data.clear()
            tipo = "Retiro" if monto < 0 else "Ahorro"
            await update.message.reply_text(
                f"✅ *{tipo} registrado*\n💵 ${monto:,.2f}", parse_mode="Markdown")
        except Exception as e:
            log.exception("Error guardando aportación")
            await update.message.reply_text(
                f"❌ *Error al guardar el ahorro.*\n`{e}`", parse_mode="Markdown")
        return

    # gasto rápido por texto: "120 uber"
    try:
        datos = leer_ticket(texto=texto.upper())
    except Exception:
        log.exception("Error interpretando el gasto por texto")
        await update.message.reply_text(
            "⚠️ *No entendí el gasto.*\nIntenta con: `120 uber`",
            parse_mode="Markdown")
        return
    try:
        msg = _guardar_gasto(datos, context.user_data.pop("tipo", "personal"), None)
        await update.message.reply_text(msg, parse_mode="Markdown")
    except Exception as e:
        log.exception("Error guardando gasto por texto")
        await update.message.reply_text(
            f"❌ *Error al guardar en la base de datos.*\n`{e}`",
            parse_mode="Markdown")


async def on_photo(update, context):
    if not solo_yo(update):
        return
    await update.message.reply_text("🔍 Procesando ticket…")
    try:
        foto = await update.message.photo[-1].get_file()
        raw = bytes(await foto.download_as_bytearray())
        comprimida = comprimir(raw)
    except Exception as e:
        log.exception("Error descargando/comprimiendo foto")
        await update.message.reply_text(
            f"❌ *Error al procesar la imagen.*\n`{e}`", parse_mode="Markdown")
        return

    # Leer el ticket con la IA
    try:
        datos = leer_ticket(imagen_b64=base64.b64encode(comprimida).decode())
        monto = Decimal(str(datos["monto"]))
    except Exception as e:
        log.exception("Error leyendo el ticket con la IA")
        await update.message.reply_text(
            "⚠️ *No pude leer bien el ticket.*\n"
            "Intenta con mejor luz, o escríbelo manual: `704 rest amates`",
            parse_mode="Markdown")
        return

    # Guardar la foto solo de tickets grandes (si falla, seguimos sin foto)
    url = None
    guardar_foto = monto >= MONTO_MIN_FOTO
    if guardar_foto:
        try:
            url = subir_foto(comprimida)
        except Exception:
            log.exception("Error subiendo a Drive (se guarda el gasto igual)")

    # Guardar en la base
    try:
        msg = _guardar_gasto(datos, context.user_data.pop("tipo", "personal"), url)
        if guardar_foto and url is None:
            msg += "\n⚠️ _No se pudo subir la foto, pero el gasto sí quedó._"
        await update.message.reply_text(msg, parse_mode="Markdown")
    except Exception as e:
        log.exception("Error guardando en la base")
        await update.message.reply_text(
            f"❌ *Error al guardar en la base de datos.*\n`{e}`\n"
            "Revisa el servidor.", parse_mode="Markdown")


def _guardar_gasto(datos, tipo, url_foto):
    """Inserta el gasto y devuelve un mensaje de confirmación con los datos.

    tipo: "personal", "pareja" o "vacaciones" (vacaciones también es de pareja).
    """
    monto = Decimal(str(datos["monto"])).quantize(Decimal("0.01"))
    categoria = datos.get("categoria", "OTROS")
    forma = datos.get("forma_pago")
    es_vacaciones = tipo == "vacaciones"
    es_pareja = tipo == "pareja" or es_vacaciones
    db_run(
        "INSERT INTO gastos (descripcion, monto, categoria_id, forma_pago_id, "
        "es_pareja, es_vacaciones, se_sugiere_facturar, url_foto, status) "
        "VALUES (%s,%s,%s,%s,%s,%s,%s,%s,'procesado')",
        (datos["descripcion"].upper(), monto,
         cat_id(categoria), forma_id(forma),
         es_pareja, es_vacaciones, bool(datos.get("se_sugiere_facturar")), url_foto))
    # armar mensaje de confirmación
    lineas = [
        "✅ *Gasto registrado*",
        f"📝 {datos['descripcion'].upper()}",
        f"💵 ${monto:,.2f}",
        f"🏷️ {categoria.title()}",
    ]
    if forma:
        lineas.append(f"💳 {forma.title()}")
    if es_vacaciones:
        lineas.append("🏖️ Vacaciones (de pareja)")
    elif es_pareja:
        lineas.append("👥 De pareja")
    if datos.get("se_sugiere_facturar"):
        lineas.append("🧾 _Considera facturar (posible deducción SAT)_")
    if url_foto:
        lineas.append("📎 Foto guardada")
    return "\n".join(lineas)


# ---------------- Resumen diario ----------------

MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
         "agosto", "septiembre", "octubre", "noviembre", "diciembre"]


def _dinero(x: Decimal) -> str:
    return f"${x.quantize(Decimal('0.01')):,.2f}"


def armar_resumen(hoy: dt.date) -> str:
    """Resumen del mes en curso: personal vs pareja y cuánto le toca a cada quien."""
    inicio = hoy.replace(day=1)
    filas = db_run(
        "SELECT es_pareja, es_vacaciones, COUNT(*), SUM(monto) FROM gastos "
        "WHERE fecha BETWEEN %s AND %s GROUP BY es_pareja, es_vacaciones",
        (inicio, hoy), "all")

    # [número de movimientos, monto]
    personal, pareja, vacaciones = [0, Decimal(0)], [0, Decimal(0)], [0, Decimal(0)]
    for es_pareja, es_vac, n, total in filas:
        destino = pareja if es_pareja else personal
        destino[0] += n
        destino[1] += total
        if es_vac:
            vacaciones[0] += n
            vacaciones[1] += total

    ingreso_total = INGRESO_YO + INGRESO_PAREJA
    pago_pareja = pareja[1] * INGRESO_PAREJA / ingreso_total
    pago_yo = personal[1] + pareja[1] * INGRESO_YO / ingreso_total

    lineas = [
        f"📊 *Resumen de {MESES[hoy.month - 1]}* ({inicio:%d}–{hoy:%d})",
        "",
        f"👤 Personales: {personal[0]} mov · {_dinero(personal[1])}",
        f"👥 Pareja: {pareja[0]} mov · {_dinero(pareja[1])}",
    ]
    if vacaciones[0]:
        lineas.append(f"    🏖️ de ellos Vacaciones: {vacaciones[0]} mov · {_dinero(vacaciones[1])}")
    lineas += [
        "",
        f"💰 Total: {personal[0] + pareja[0]} mov · {_dinero(personal[1] + pareja[1])}",
        f"🙋 Pago yo: *{_dinero(pago_yo)}*",
        f"💑 Pago pareja: *{_dinero(pago_pareja)}*",
    ]
    return "\n".join(lineas)


async def enviar_resumen(context):
    try:
        msg = armar_resumen(dt.datetime.now(TZ).date())
    except Exception as e:
        log.exception("Error armando el resumen")
        msg = f"❌ *Error al armar el resumen.*\n`{e}`"
    await context.bot.send_message(MI_CHAT_ID, msg, parse_mode="Markdown")


async def cmd_resumen(update, context):
    if not solo_yo(update):
        return
    await enviar_resumen(context)


def main():
    app = Application.builder().token(TG_TOKEN).build()
    # palabras clave (aceptan mayúscula/minúscula por regex)
    app.add_handler(MessageHandler(filters.Regex(r"(?i)^gasto$"), cmd_gasto))
    app.add_handler(MessageHandler(filters.Regex(r"(?i)^ingreso$"), cmd_ingreso))
    app.add_handler(MessageHandler(filters.Regex(r"(?i)^ahorro$"), cmd_ahorro))
    app.add_handler(MessageHandler(filters.Regex(r"(?i)^resumen$"), cmd_resumen))
    app.add_handler(CallbackQueryHandler(on_callback))
    app.add_handler(MessageHandler(filters.PHOTO, on_photo))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, on_text))
    app.job_queue.run_daily(enviar_resumen, time=dt.time(10, 0, tzinfo=TZ))
    log.info("Finbot corriendo (polling)…")
    app.run_polling()


if __name__ == "__main__":
    main()
