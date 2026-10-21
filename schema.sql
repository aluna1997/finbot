-- ============================================================
--  FINBOT - Base de datos (MySQL 8)
--
--  Un solo archivo para instalar Y para actualizar:
--    mysql -u root -p < schema.sql
--
--  Se puede correr las veces que quieras: en una base nueva crea todo,
--  en una base existente solo aplica los cambios que le falten.
-- ============================================================

CREATE DATABASE IF NOT EXISTS finbot
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE finbot;

-- ============================================================
--  1) TABLAS (estado actual)
-- ============================================================

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

CREATE TABLE IF NOT EXISTS ingresos (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  fuente_id   INT NOT NULL,
  monto       DECIMAL(12,2) NOT NULL,   -- negativos = retiros
  fecha       DATE NOT NULL DEFAULT (CURRENT_DATE),
  creado_en   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_ingreso_fuente FOREIGN KEY (fuente_id) REFERENCES fuentes_ingreso(id),
  INDEX idx_fecha_ing (fecha)
);

CREATE TABLE IF NOT EXISTS aportaciones (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  portafolio_id INT NOT NULL,
  monto         DECIMAL(12,2) NOT NULL,   -- positivo = aportas, negativo = retiras
  fecha         DATE NOT NULL DEFAULT (CURRENT_DATE),
  creado_en     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_aportacion_portafolio FOREIGN KEY (portafolio_id) REFERENCES portafolios(id),
  INDEX idx_fecha_ap (fecha)
);

-- ============================================================
--  2) MIGRACIONES (para bases creadas con versiones anteriores)
--     Cada paso revisa primero si hace falta; si no, no hace nada.
-- ============================================================

DROP PROCEDURE IF EXISTS ejecutar_si;
DELIMITER //
CREATE PROCEDURE ejecutar_si(condicion BOOLEAN, sentencia TEXT)
BEGIN
  IF condicion THEN
    SET @sql = sentencia;
    PREPARE st FROM @sql;
    EXECUTE st;
    DEALLOCATE PREPARE st;
  END IF;
END//
DELIMITER ;

-- ¿Qué existe hoy en la base? (1 = sí, 0 = no)
SET @hay_vacaciones = (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = 'finbot'
                       AND table_name = 'gastos' AND column_name = 'es_vacaciones');
SET @hay_activo     = (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = 'finbot'
                       AND table_name = 'portafolios' AND column_name = 'activo');
SET @hay_fk_forma   = (SELECT COUNT(*) FROM information_schema.table_constraints WHERE table_schema = 'finbot'
                       AND table_name = 'gastos' AND constraint_name = 'fk_gasto_formapago');
SET @hay_forma      = (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = 'finbot'
                       AND table_name = 'gastos' AND column_name = 'forma_pago_id');
SET @hay_conciliado = (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = 'finbot'
                       AND table_name = 'gastos' AND column_name = 'conciliado');

-- v3: bandera de vacaciones
CALL ejecutar_si(@hay_vacaciones = 0,
  'ALTER TABLE gastos ADD COLUMN es_vacaciones BOOLEAN NOT NULL DEFAULT FALSE AFTER es_pareja,
                      ADD INDEX idx_vacaciones (es_vacaciones)');

-- v3: solo PROFUTURO, ACTIVA y MERCADO PAGO como opciones de ahorro.
--     Los portafolios viejos no se borran (tienen aportaciones ligadas), se desactivan.
CALL ejecutar_si(@hay_activo = 0,
  'ALTER TABLE portafolios ADD COLUMN activo BOOLEAN NOT NULL DEFAULT TRUE');
CALL ejecutar_si(@hay_activo = 0,
  'UPDATE portafolios SET activo = descripcion IN (''PROFUTURO'',''ACTIVA'',''MERCADO PAGO'')');

-- v4: se eliminan forma de pago y conciliado
CALL ejecutar_si(@hay_fk_forma > 0, 'ALTER TABLE gastos DROP FOREIGN KEY fk_gasto_formapago');
CALL ejecutar_si(@hay_forma > 0,    'ALTER TABLE gastos DROP COLUMN forma_pago_id');
CALL ejecutar_si(@hay_conciliado > 0, 'ALTER TABLE gastos DROP COLUMN conciliado');
DROP TABLE IF EXISTS formas_pago;

DROP PROCEDURE ejecutar_si;

-- ============================================================
--  3) CATÁLOGOS INICIALES (no duplica si ya existen)
-- ============================================================

INSERT IGNORE INTO categorias (descripcion) VALUES
  ('SUBSCRIPCIONES'),('DONACIONES'),('CUIDADO PERSONAL'),
  ('VIAJES / VACACIONES'),('ROPA Y CALZADO'),('ENTRETENIMIENTO'),
  ('EDUCACION'),('SALUD'),('SERVICIOS'),('TRANSPORTE'),
  ('ALIMENTACION'),('OTROS'),('HOGAR');

INSERT IGNORE INTO fuentes_ingreso (descripcion) VALUES
  ('TCS');

INSERT IGNORE INTO portafolios (descripcion) VALUES
  ('PROFUTURO'),('ACTIVA'),('MERCADO PAGO');
