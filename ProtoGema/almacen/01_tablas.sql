/* =====================================================================
   ProtoGema | Almacén de datos (tablas)
   Se aplica en CADA encendido desde el servicio "estructura".
   Todo es repetible: si algo ya existe no se toca, si falta se crea.
   Esquema "gema": perfiles, agenda, bandeja de avisos, memoria y chat.
   ===================================================================== */
SET client_min_messages = warning;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS gema;

/* Ajustes compartidos por todos los perfiles de esta computadora */
CREATE TABLE IF NOT EXISTS gema.ajustes (
    clave     text PRIMARY KEY,
    valor     text NOT NULL DEFAULT '',
    cambiado  timestamptz NOT NULL DEFAULT now()
);
INSERT INTO gema.ajustes (clave, valor) VALUES
    ('modelo',          'gemini-flash-latest'),
    ('modelo_respaldo', 'gemini-flash-lite-latest'),
    ('clave_gemini',    ''),
    ('telegram_bot',    '')
ON CONFLICT (clave) DO NOTHING;

/* Perfiles: cada persona que usa ProtoGema tiene el suyo */
CREATE TABLE IF NOT EXISTS gema.usuarios (
    id              serial PRIMARY KEY,
    nombre          text NOT NULL CHECK (char_length(trim(nombre)) BETWEEN 1 AND 40),
    -- La "gema" es el color con el que ProtoGema se viste para esa persona
    gema            text NOT NULL DEFAULT 'rubi'
                    CHECK (gema IN ('rubi','zafiro','esmeralda','ambar','amatista','opalo')),
    tono            text NOT NULL DEFAULT 'cercano'
                    CHECK (tono IN ('cercano','profesional','motivador','directo','divertido')),
    intereses       text[] NOT NULL DEFAULT '{}',
    sobre_mi        text NOT NULL DEFAULT '' CHECK (char_length(sobre_mi) <= 600),
    pin_hash        text,
    clave_gemini    text NOT NULL DEFAULT '',
    telegram_chat   text NOT NULL DEFAULT '',
    avisos_defecto  integer[] NOT NULL DEFAULT '{60,10}',
    franja_inicio   time NOT NULL DEFAULT '07:00',
    franja_fin      time NOT NULL DEFAULT '22:00',
    destello        boolean NOT NULL DEFAULT true,   -- resumen de la mañana
    creado          timestamptz NOT NULL DEFAULT now()
);

/* Sesiones abiertas en el navegador (una ficha secreta por perfil) */
CREATE TABLE IF NOT EXISTS gema.sesiones (
    token       text PRIMARY KEY,
    usuario_id  integer NOT NULL REFERENCES gema.usuarios(id) ON DELETE CASCADE,
    creada      timestamptz NOT NULL DEFAULT now(),
    usada       timestamptz NOT NULL DEFAULT now()
);

/* Agenda: cada actividad pertenece a un solo perfil */
CREATE TABLE IF NOT EXISTS gema.eventos (
    id           serial PRIMARY KEY,
    usuario_id   integer NOT NULL REFERENCES gema.usuarios(id) ON DELETE CASCADE,
    titulo       text NOT NULL CHECK (char_length(trim(titulo)) BETWEEN 1 AND 160),
    notas        text NOT NULL DEFAULT '' CHECK (char_length(notas) <= 600),
    lugar        text NOT NULL DEFAULT '' CHECK (char_length(lugar) <= 120),
    tipo         text NOT NULL DEFAULT 'otro'
                 CHECK (tipo IN ('clase','examen','entrega','reunion','personal','salud','otro')),
    importancia  smallint NOT NULL DEFAULT 2 CHECK (importancia BETWEEN 1 AND 3),  -- 3 = muy importante
    inicio       timestamptz NOT NULL,
    fin          timestamptz NOT NULL,
    -- Avisos escalonados: minutos antes del inicio (además del aviso a la hora exacta)
    avisos       integer[] NOT NULL DEFAULT '{60,10}',
    estado       text NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente','hecho','cancelado')),
    creado       timestamptz NOT NULL DEFAULT now(),
    cambiado     timestamptz NOT NULL DEFAULT now(),
    CHECK (fin > inicio)
);
CREATE INDEX IF NOT EXISTS gema_eventos_usuario_inicio
    ON gema.eventos (usuario_id, inicio) WHERE estado = 'pendiente';

/* Bandeja de avisos: lo que ve la persona en la campana, en el navegador y en Telegram */
CREATE TABLE IF NOT EXISTS gema.notificaciones (
    id          bigserial PRIMARY KEY,
    usuario_id  integer NOT NULL REFERENCES gema.usuarios(id) ON DELETE CASCADE,
    evento_id   integer REFERENCES gema.eventos(id) ON DELETE CASCADE,
    clave       text NOT NULL,                 -- evita que un aviso se repita
    clase       text NOT NULL DEFAULT 'aviso'
                CHECK (clase IN ('aviso','ahora','pospuesto','destello','sistema')),
    titulo      text NOT NULL,
    cuerpo      text NOT NULL DEFAULT '',
    para        timestamptz NOT NULL DEFAULT now(),   -- cuándo debe aparecer
    mostrada    boolean NOT NULL DEFAULT false,
    leida       boolean NOT NULL DEFAULT false,
    telegram    text NOT NULL DEFAULT 'no' CHECK (telegram IN ('no','pendiente','enviado','fallo')),
    creada      timestamptz NOT NULL DEFAULT now(),
    UNIQUE (usuario_id, clave)
);
CREATE INDEX IF NOT EXISTS gema_notif_usuario_para ON gema.notificaciones (usuario_id, para DESC);

/* Historial del chat (por perfil) */
CREATE TABLE IF NOT EXISTS gema.mensajes (
    id          bigserial PRIMARY KEY,
    usuario_id  integer NOT NULL REFERENCES gema.usuarios(id) ON DELETE CASCADE,
    rol         text NOT NULL CHECK (rol IN ('yo','gema')),
    texto       text NOT NULL,
    creado      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS gema_mensajes_usuario ON gema.mensajes (usuario_id, id DESC);

/* Cosas que ProtoGema aprende de cada persona ("Lo que sé de ti") */
CREATE TABLE IF NOT EXISTS gema.recuerdos (
    id          serial PRIMARY KEY,
    usuario_id  integer NOT NULL REFERENCES gema.usuarios(id) ON DELETE CASCADE,
    dato        text NOT NULL CHECK (char_length(trim(dato)) BETWEEN 2 AND 240),
    creado      timestamptz NOT NULL DEFAULT now(),
    UNIQUE (usuario_id, dato)
);

/* Dirección de la API de Gemini (se puede cambiar para pruebas) */
INSERT INTO gema.ajustes (clave, valor) VALUES ('api_gemini', 'https://generativelanguage.googleapis.com/v1beta')
ON CONFLICT (clave) DO NOTHING;
