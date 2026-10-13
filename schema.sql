-- ============================================================
--  FINBOT v3.0 - Esquema MySQL
--  Ejecutar con: mysql -u root -p < schema.sql
-- ============================================================

CREATE DATABASE IF NOT EXISTS finbot
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE finbot;

-- -------------------- Catálogos --------------------

CREATE TABLE IF NOT EXISTS categorias (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  descripcion VARCHAR(60) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS formas_pago (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  descripcion VARCHAR(60) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS fuentes_ingreso (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  descripcion VARCHAR(60) NOT NULL UNIQUE
);

-- -------------------- Tabla principal: gastos --------------------

CREATE TABLE IF NOT EXISTS gastos (
  id                    INT AUTO_INCREMENT PRIMARY KEY,
  descripcion           VARCHAR(255) NOT NULL,          -- forzada a MAYÚSCULAS desde el código
  monto                 DECIMAL(12,2) NOT NULL,         -- MXN, dos decimales
  fecha                 DATE NOT NULL DEFAULT (CURRENT_DATE),
  categoria_id          INT NULL,
  forma_pago_id         INT NULL,
  es_pareja             BOOLEAN NOT NULL DEFAULT FALSE,
  es_vacaciones         BOOLEAN NOT NULL DEFAULT FALSE, -- vacaciones: siempre también es_pareja
  conciliado            BOOLEAN NOT NULL DEFAULT FALSE,
  facturado             BOOLEAN NOT NULL DEFAULT FALSE,
  se_sugiere_facturar   BOOLEAN NOT NULL DEFAULT FALSE,
  url_foto              VARCHAR(512) NULL,              -- liga de Drive; NULL si monto < 2000
  status                ENUM('pendiente','procesado','error') NOT NULL DEFAULT 'pendiente',
  creado_en             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_gasto_categoria  FOREIGN KEY (categoria_id)  REFERENCES categorias(id),
  CONSTRAINT fk_gasto_formapago  FOREIGN KEY (forma_pago_id) REFERENCES formas_pago(id),
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

-- -------------------- Catálogo: portafolios --------------------

CREATE TABLE IF NOT EXISTS portafolios (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  descripcion VARCHAR(60) NOT NULL UNIQUE,
  activo      BOOLEAN NOT NULL DEFAULT TRUE   -- solo los activos salen como opción en el bot
);

-- -------------------- Tabla: aportaciones (inversiones/ahorro) --------------------

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

INSERT IGNORE INTO formas_pago (descripcion) VALUES
  ('EFECTIVO'),('BANREGIO PLATINUM'),('BBVA ORO'),
  ('LIVERPOOL'),('KLAR'),('TRANSFERENCIA');

INSERT IGNORE INTO fuentes_ingreso (descripcion) VALUES
  ('TCS');

INSERT IGNORE INTO portafolios (descripcion) VALUES
  ('PROFUTURO'),('ACTIVA'),('MERCADO PAGO');
