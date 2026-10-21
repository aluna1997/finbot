-- ============================================================
--  FINBOT - Esquema MySQL
--
--  Instalación nueva (solo crea las tablas, sin migraciones):
--    sed '/^-- INICIO MIGRACIONES/q' schema.sql | mysql -u root -p
--
--  Base existente: corre UNA vez la última migración (la única sin
--  comentar, al final del archivo), por ejemplo desde DBeaver.
-- ============================================================

CREATE DATABASE IF NOT EXISTS finbot
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE finbot;

-- -------------------- Catálogos --------------------

CREATE TABLE IF NOT EXISTS categorias (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  descripcion VARCHAR(60) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS fuentes_ingreso (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  descripcion VARCHAR(60) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS portafolios (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  descripcion VARCHAR(60) NOT NULL UNIQUE,
  activo      BOOLEAN NOT NULL DEFAULT TRUE   -- solo los activos salen como opción en el bot
);

-- -------------------- Tabla principal: gastos --------------------

CREATE TABLE IF NOT EXISTS gastos (
  id                    INT AUTO_INCREMENT PRIMARY KEY,
  descripcion           VARCHAR(255) NOT NULL,          -- forzada a MAYÚSCULAS desde el código
  monto                 DECIMAL(12,2) NOT NULL,         -- MXN, dos decimales
  fecha                 DATE NOT NULL DEFAULT (CURRENT_DATE),  -- el bot conecta en hora CDMX
  categoria_id          INT NULL,
  es_pareja             BOOLEAN NOT NULL DEFAULT FALSE,
  es_vacaciones         BOOLEAN NOT NULL DEFAULT FALSE, -- vacaciones: siempre también es_pareja
  facturado             BOOLEAN NOT NULL DEFAULT FALSE,
  se_sugiere_facturar   BOOLEAN NOT NULL DEFAULT FALSE,
  url_foto              VARCHAR(512) NULL,              -- liga de Drive; NULL si monto < 2000
  status                ENUM('pendiente','procesado','error') NOT NULL DEFAULT 'pendiente',
  creado_en             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_gasto_categoria FOREIGN KEY (categoria_id) REFERENCES categorias(id),
  INDEX idx_fecha (fecha),
  INDEX idx_status (status),
  INDEX idx_pareja (es_pareja),
  INDEX idx_vacaciones (es_vacaciones)
);

-- -------------------- Tabla: ingresos --------------------

CREATE TABLE IF NOT EXISTS ingresos (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  fuente_id   INT NOT NULL,
  monto       DECIMAL(12,2) NOT NULL,   -- negativos = retiros
  fecha       DATE NOT NULL DEFAULT (CURRENT_DATE),
  creado_en   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_ingreso_fuente FOREIGN KEY (fuente_id) REFERENCES fuentes_ingreso(id),
  INDEX idx_fecha_ing (fecha)
);

-- -------------------- Tabla: aportaciones (ahorro) --------------------

CREATE TABLE IF NOT EXISTS aportaciones (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  portafolio_id INT NOT NULL,
  monto         DECIMAL(12,2) NOT NULL,   -- positivo = aportas, negativo = retiras
  fecha         DATE NOT NULL DEFAULT (CURRENT_DATE),
  creado_en     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_aportacion_portafolio FOREIGN KEY (portafolio_id) REFERENCES portafolios(id),
  INDEX idx_fecha_ap (fecha)
);

-- -------------------- Datos iniciales --------------------

INSERT IGNORE INTO categorias (descripcion) VALUES
  ('SUBSCRIPCIONES'),('DONACIONES'),('CUIDADO PERSONAL'),
  ('VIAJES / VACACIONES'),('ROPA Y CALZADO'),('ENTRETENIMIENTO'),
  ('EDUCACION'),('SALUD'),('SERVICIOS'),('TRANSPORTE'),
  ('ALIMENTACION'),('OTROS'),('HOGAR');

INSERT IGNORE INTO fuentes_ingreso (descripcion) VALUES
  ('TCS');

INSERT IGNORE INTO portafolios (descripcion) VALUES
  ('PROFUTURO'),('ACTIVA'),('MERCADO PAGO');


-- ############################################################
-- INICIO MIGRACIONES
--  Historial de cambios a una base existente, de la más vieja a la
--  más nueva. Las ya aplicadas quedan comentadas como registro; solo
--  la última está sin comentar. Al agregar una nueva: comenta la
--  anterior, escribe la nueva al final y actualiza los CREATE TABLE
--  de arriba para que reflejen el estado final.
-- ############################################################

-- ------------------------------------------------------------
--  v3 (2026-10-12) — Vacaciones y solo 3 cuentas de ahorro   [APLICADA]
-- ------------------------------------------------------------
-- ALTER TABLE gastos
--   ADD COLUMN es_vacaciones BOOLEAN NOT NULL DEFAULT FALSE AFTER es_pareja,
--   ADD INDEX idx_vacaciones (es_vacaciones);
--
-- ALTER TABLE portafolios ADD COLUMN activo BOOLEAN NOT NULL DEFAULT TRUE;
-- INSERT IGNORE INTO portafolios (descripcion) VALUES
--   ('PROFUTURO'),('ACTIVA'),('MERCADO PAGO');
-- UPDATE portafolios
--   SET activo = descripcion IN ('PROFUTURO','ACTIVA','MERCADO PAGO');

-- ------------------------------------------------------------
--  v4 (2026-10-20) — Se eliminan forma de pago y conciliado   [PENDIENTE]
-- ------------------------------------------------------------
--  Si el primer ALTER marca error, revisa el nombre real de la llave con
--  SHOW CREATE TABLE gastos;  (la línea CONSTRAINT ... REFERENCES formas_pago)
--  y cámbialo abajo.
USE finbot;
ALTER TABLE gastos DROP FOREIGN KEY fk_gasto_formapago;
ALTER TABLE gastos DROP COLUMN forma_pago_id, DROP COLUMN conciliado;
DROP TABLE formas_pago;
