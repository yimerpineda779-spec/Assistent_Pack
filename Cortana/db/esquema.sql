-- =============================================================
--  Esquema de la base de datos de Cortana (agenda de actividades)
--  Se ejecuta en CADA arranque desde el servicio "db-migrar".
--  Todo es idempotente (IF NOT EXISTS): si algo ya existe, no se toca,
--  y si falta (por ejemplo, una columna nueva), se agrega sin perder datos.
-- =============================================================

SET client_min_messages = warning;

CREATE TABLE IF NOT EXISTS actividades (
    id            SERIAL PRIMARY KEY,
    titulo        TEXT        NOT NULL CHECK (length(trim(titulo)) BETWEEN 1 AND 200),
    descripcion   TEXT        CHECK (descripcion IS NULL OR length(descripcion) <= 1000),
    fecha_hora    TIMESTAMPTZ NOT NULL,
    -- Minutos antes de la actividad para el aviso previo (0 = solo aviso a la hora exacta)
    recordar_min  INTEGER     NOT NULL DEFAULT 30 CHECK (recordar_min BETWEEN 0 AND 10080),
    estado        TEXT        NOT NULL DEFAULT 'pendiente'
                              CHECK (estado IN ('pendiente', 'cancelada')),
    -- true cuando ya se mostró el aviso previo
    avisado       BOOLEAN     NOT NULL DEFAULT false,
    creada_en     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Versión 1.2: segundo aviso a la hora exacta de la actividad
ALTER TABLE actividades ADD COLUMN IF NOT EXISTS avisado_inicio BOOLEAN NOT NULL DEFAULT false;

-- Acelera las consultas por fecha y la búsqueda de recordatorios pendientes
CREATE INDEX IF NOT EXISTS idx_actividades_fecha
    ON actividades (fecha_hora) WHERE estado = 'pendiente';
