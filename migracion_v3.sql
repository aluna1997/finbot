-- ============================================================
--  FINBOT v3.0 - Migración sobre una base v2.0 existente
--  Ejecutar UNA vez con: mysql -u root -p < migracion_v3.sql
-- ============================================================
USE finbot;

-- 1) Bandera de vacaciones (las vacaciones siempre son también de pareja)
ALTER TABLE gastos
  ADD COLUMN es_vacaciones BOOLEAN NOT NULL DEFAULT FALSE AFTER es_pareja,
  ADD INDEX idx_vacaciones (es_vacaciones);

-- 2) Solo PROFUTURO, ACTIVA y MERCADO PAGO como opciones de ahorro.
--    Los portafolios viejos no se borran (pueden tener aportaciones ligadas),
--    solo se desactivan para que ya no salgan en el bot.
ALTER TABLE portafolios ADD COLUMN activo BOOLEAN NOT NULL DEFAULT TRUE;
INSERT IGNORE INTO portafolios (descripcion) VALUES
  ('PROFUTURO'),('ACTIVA'),('MERCADO PAGO');
UPDATE portafolios
  SET activo = descripcion IN ('PROFUTURO','ACTIVA','MERCADO PAGO');

-- 3) (OPCIONAL) Corregir fechas de gastos que se guardaron con el día del
--    servidor (UTC) en vez del de CDMX. creado_en guarda el momento real, así
--    que en hora CDMX su fecha es la correcta.
--    Primero REVISA qué filas cambiarían (ojo si editaste fechas a mano en DBeaver):
SET time_zone = '-06:00';
SELECT id, descripcion, monto, fecha AS fecha_actual, DATE(creado_en) AS fecha_cdmx
FROM gastos
WHERE fecha <> DATE(creado_en);
--    Si todo se ve bien, quita el comentario de la siguiente línea y vuelve a correr
--    solo esa parte (o hazlo desde DBeaver). Lo mismo aplica a ingresos y aportaciones.
-- UPDATE gastos SET fecha = DATE(creado_en) WHERE fecha <> DATE(creado_en);
