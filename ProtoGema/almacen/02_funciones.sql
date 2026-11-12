/* =====================================================================
   ProtoGema | Lógica de la agenda inteligente (funciones)
   n8n nunca escribe SQL libre: solo llama a estas funciones con
   parámetros, así que la IA no puede dañar la base de datos.
   ===================================================================== */
SET client_min_messages = warning;

/* ---------- Utilidades de fechas ---------- */

CREATE OR REPLACE FUNCTION gema.dia_nombre(t timestamptz) RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT (ARRAY['domingo','lunes','martes','miércoles','jueves','viernes','sábado'])[extract(dow FROM t)::int + 1];
$$;

CREATE OR REPLACE FUNCTION gema.mes_nombre(t timestamptz) RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT (ARRAY['enero','febrero','marzo','abril','mayo','junio','julio','agosto',
                'septiembre','octubre','noviembre','diciembre'])[extract(month FROM t)::int];
$$;

-- "2026-11-12T15:30" (hora local) -> timestamptz. Devuelve NULL si no se entiende.
CREATE OR REPLACE FUNCTION gema.a_momento(t text) RETURNS timestamptz
LANGUAGE plpgsql STABLE AS $$
BEGIN
  IF t IS NULL OR btrim(t) = '' THEN RETURN NULL; END IF;
  RETURN (left(replace(btrim(t), ' ', 'T'), 16))::timestamp AT TIME ZONE current_setting('TimeZone');
EXCEPTION WHEN others THEN
  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION gema.iso(t timestamptz) RETURNS text
LANGUAGE sql STABLE AS $$ SELECT to_char(t, 'YYYY-MM-DD"T"HH24:MI'); $$;

-- 15:30 -> "3:30 p. m."
CREATE OR REPLACE FUNCTION gema.hora(t timestamptz) RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT ltrim(to_char(t, 'HH12:MI'), '0') || CASE WHEN extract(hour FROM t) < 12 THEN ' a. m.' ELSE ' p. m.' END;
$$;

-- "hoy", "mañana" o "jueves 12 de noviembre"
CREATE OR REPLACE FUNCTION gema.cuando(t timestamptz) RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT CASE (t::date - current_date)
           WHEN 0 THEN 'hoy'
           WHEN 1 THEN 'mañana'
           WHEN -1 THEN 'ayer'
           ELSE gema.dia_nombre(t) || ' ' || extract(day FROM t)::int || ' de ' || gema.mes_nombre(t)
         END;
$$;

-- Lista de minutos de aviso limpia: enteros entre 1 y 10080, sin repetir, máximo 4
CREATE OR REPLACE FUNCTION gema.limpiar_avisos(a jsonb, defecto integer[]) RETURNS integer[]
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE r integer[];
BEGIN
  IF a IS NULL OR jsonb_typeof(a) <> 'array' THEN RETURN defecto; END IF;
  SELECT coalesce(array_agg(DISTINCT m ORDER BY m DESC), '{}') INTO r
  FROM (SELECT (x #>> '{}')::numeric::int AS m
          FROM jsonb_array_elements(a) x
         WHERE jsonb_typeof(x) = 'number' OR (x #>> '{}') ~ '^\d+$') s
  WHERE m BETWEEN 1 AND 10080;
  RETURN r[1:4];
EXCEPTION WHEN others THEN
  RETURN defecto;
END $$;

CREATE OR REPLACE FUNCTION gema.texto_avisos(a integer[]) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(string_agg(CASE WHEN m % 1440 = 0 THEN (m / 1440) || ' d'
                                  WHEN m % 60 = 0 THEN (m / 60) || ' h'
                                  ELSE m || ' min' END, ', ' ORDER BY m DESC), 'solo a la hora')
  FROM unnest(a) m;
$$;

/* ---------- Fichas JSON ---------- */

CREATE OR REPLACE FUNCTION gema.ficha(e gema.eventos) RETURNS jsonb
LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'id', e.id, 'titulo', e.titulo, 'tipo', e.tipo, 'importancia', e.importancia,
    'lugar', e.lugar, 'notas', e.notas, 'estado', e.estado,
    'inicio', gema.iso(e.inicio), 'fin', gema.iso(e.fin),
    'cuando', gema.cuando(e.inicio), 'hora', gema.hora(e.inicio), 'hora_fin', gema.hora(e.fin),
    'minutos', (extract(epoch FROM e.fin - e.inicio) / 60)::int,
    'avisos', to_jsonb(e.avisos), 'avisos_texto', gema.texto_avisos(e.avisos));
$$;

CREATE OR REPLACE FUNCTION gema.perfil(uid integer) RETURNS jsonb
LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'id', u.id, 'nombre', u.nombre, 'gema', u.gema, 'tono', u.tono,
    'intereses', to_jsonb(u.intereses), 'sobre_mi', u.sobre_mi,
    'tiene_pin', u.pin_hash IS NOT NULL,
    'clave_propia', u.clave_gemini <> '',
    'telegram_chat', u.telegram_chat,
    'avisos_defecto', to_jsonb(u.avisos_defecto),
    'franja_inicio', to_char(u.franja_inicio, 'HH24:MI'),
    'franja_fin', to_char(u.franja_fin, 'HH24:MI'),
    'destello', u.destello)
  FROM gema.usuarios u WHERE u.id = uid;
$$;

/* ---------- Sesiones ---------- */

CREATE OR REPLACE FUNCTION gema.usuario_de(tok text) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE uid integer;
BEGIN
  IF tok IS NULL OR length(tok) < 20 THEN RETURN NULL; END IF;
  UPDATE gema.sesiones SET usada = now()
   WHERE token = tok AND usada > now() - interval '60 days'
  RETURNING usuario_id INTO uid;
  RETURN uid;
END $$;

CREATE OR REPLACE FUNCTION gema.abrir_sesion(uid integer) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE tok text := encode(gen_random_bytes(24), 'hex');
BEGIN
  DELETE FROM gema.sesiones WHERE usada < now() - interval '60 days';
  INSERT INTO gema.sesiones (token, usuario_id) VALUES (tok, uid);
  RETURN tok;
END $$;

/* ---------- Inteligencia de la agenda ---------- */

-- Actividades pendientes que se cruzan con un intervalo
CREATE OR REPLACE FUNCTION gema.choques(uid integer, ini timestamptz, fin_ timestamptz, excluir integer DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT coalesce(jsonb_agg(gema.ficha(e) ORDER BY e.inicio), '[]'::jsonb)
  FROM gema.eventos e
  WHERE e.usuario_id = uid AND e.estado = 'pendiente'
    AND e.inicio < fin_ AND e.fin > ini
    AND (excluir IS NULL OR e.id <> excluir);
$$;

-- Primer hueco libre del mismo día (dentro de la franja de la persona) para algo que dura "minutos"
CREATE OR REPLACE FUNCTION gema.hueco(uid integer, desde timestamptz, minutos integer, excluir integer DEFAULT NULL)
RETURNS timestamptz LANGUAGE plpgsql STABLE AS $$
DECLARE
  u gema.usuarios;
  dia date := desde::date;
  dur interval := make_interval(mins => greatest(minutos, 15));
  cursor_t timestamptz;
  tope timestamptz;
  e record;
BEGIN
  SELECT * INTO u FROM gema.usuarios WHERE id = uid;
  cursor_t := greatest(desde, (dia + u.franja_inicio)::timestamp AT TIME ZONE current_setting('TimeZone'), now());
  -- se redondea a la siguiente media hora para proponer horas "limpias"
  cursor_t := date_trunc('hour', cursor_t) + CASE WHEN extract(minute FROM cursor_t) = 0 THEN interval '0'
                                                  WHEN extract(minute FROM cursor_t) <= 30 THEN interval '30 min'
                                                  ELSE interval '60 min' END;
  tope := (dia + u.franja_fin)::timestamp AT TIME ZONE current_setting('TimeZone');
  FOR e IN SELECT inicio, fin FROM gema.eventos
            WHERE usuario_id = uid AND estado = 'pendiente' AND fin > cursor_t AND inicio < tope
              AND (excluir IS NULL OR id <> excluir)
            ORDER BY inicio LOOP
    IF cursor_t + dur <= e.inicio THEN EXIT; END IF;
    IF e.fin > cursor_t THEN cursor_t := e.fin; END IF;
  END LOOP;
  IF cursor_t + dur <= tope THEN RETURN cursor_t; END IF;
  RETURN NULL;
END $$;

-- Crea una actividad. Devuelve la ficha, los choques y una sugerencia de hueco si choca.
CREATE OR REPLACE FUNCTION gema.crear_evento(uid integer, d jsonb) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE
  u gema.usuarios;
  ini timestamptz := gema.a_momento(d->>'inicio');
  fin_ timestamptz := gema.a_momento(d->>'fin');
  dur integer := coalesce(nullif(d->>'minutos', '')::numeric::int, 60);
  tipo_ text := lower(coalesce(d->>'tipo', 'otro'));
  imp smallint := least(3, greatest(1, coalesce(nullif(d->>'importancia', '')::numeric::int, 2)));
  cruces jsonb;
  sug timestamptz;
  ev gema.eventos;
BEGIN
  SELECT * INTO u FROM gema.usuarios WHERE id = uid;
  IF ini IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'No entendí la fecha u hora de la actividad.'); END IF;
  IF coalesce(btrim(d->>'titulo'), '') = '' THEN RETURN jsonb_build_object('ok', false, 'error', 'Falta el nombre de la actividad.'); END IF;
  IF fin_ IS NULL OR fin_ <= ini THEN fin_ := ini + make_interval(mins => least(greatest(dur, 5), 1440)); END IF;
  IF tipo_ NOT IN ('clase','examen','entrega','reunion','personal','salud','otro') THEN tipo_ := 'otro'; END IF;

  cruces := gema.choques(uid, ini, fin_);
  IF jsonb_array_length(cruces) > 0 THEN
    sug := gema.hueco(uid, ini, (extract(epoch FROM fin_ - ini) / 60)::int);
  END IF;

  INSERT INTO gema.eventos (usuario_id, titulo, notas, lugar, tipo, importancia, inicio, fin, avisos)
  VALUES (uid, left(btrim(d->>'titulo'), 160), left(coalesce(d->>'notas', ''), 600), left(coalesce(d->>'lugar', ''), 120),
          tipo_, imp, ini, fin_, gema.limpiar_avisos(d->'avisos', u.avisos_defecto))
  RETURNING * INTO ev;

  RETURN jsonb_build_object('ok', true, 'evento', gema.ficha(ev), 'choques', cruces,
                            'sugerencia', CASE WHEN sug IS NULL THEN NULL ELSE gema.hora(sug) END,
                            'pasado', ini < now());
END $$;

-- Cambia una actividad existente (solo los campos que vengan)
CREATE OR REPLACE FUNCTION gema.editar_evento(uid integer, d jsonb) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE
  ev gema.eventos;
  ini timestamptz;
  fin_ timestamptz;
  dur interval;
  cruces jsonb := '[]';
  sug timestamptz;
BEGIN
  SELECT * INTO ev FROM gema.eventos WHERE id = nullif(d->>'id', '')::numeric::int AND usuario_id = uid;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'No encontré esa actividad en tu agenda.'); END IF;

  dur := ev.fin - ev.inicio;
  ini := coalesce(gema.a_momento(d->>'inicio'), ev.inicio);
  IF nullif(d->>'minutos', '') IS NOT NULL THEN dur := make_interval(mins => least(greatest((d->>'minutos')::numeric::int, 5), 1440)); END IF;
  fin_ := gema.a_momento(d->>'fin');
  IF fin_ IS NULL OR fin_ <= ini THEN fin_ := ini + dur; END IF;

  UPDATE gema.eventos SET
    titulo      = coalesce(nullif(left(btrim(d->>'titulo'), 160), ''), titulo),
    notas       = coalesce(left(d->>'notas', 600), notas),
    lugar       = coalesce(left(d->>'lugar', 120), lugar),
    tipo        = CASE WHEN lower(d->>'tipo') IN ('clase','examen','entrega','reunion','personal','salud','otro') THEN lower(d->>'tipo') ELSE tipo END,
    importancia = coalesce(least(3, greatest(1, nullif(d->>'importancia', '')::numeric::int))::smallint, importancia),
    avisos      = CASE WHEN d ? 'avisos' THEN gema.limpiar_avisos(d->'avisos', avisos) ELSE avisos END,
    inicio      = ini,
    fin         = fin_,
    estado      = 'pendiente',
    cambiado    = now()
  WHERE id = ev.id
  RETURNING * INTO ev;

  IF d ? 'inicio' OR d ? 'fin' OR d ? 'minutos' THEN
    cruces := gema.choques(uid, ev.inicio, ev.fin, ev.id);
    IF jsonb_array_length(cruces) > 0 THEN
      sug := gema.hueco(uid, ev.inicio, (extract(epoch FROM ev.fin - ev.inicio) / 60)::int, ev.id);
    END IF;
  END IF;
  RETURN jsonb_build_object('ok', true, 'evento', gema.ficha(ev), 'choques', cruces,
                            'sugerencia', CASE WHEN sug IS NULL THEN NULL ELSE gema.hora(sug) END);
END $$;

CREATE OR REPLACE FUNCTION gema.estado_evento(uid integer, eid integer, nuevo text) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE ev gema.eventos;
BEGIN
  IF nuevo NOT IN ('pendiente','hecho','cancelado') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Estado no válido.');
  END IF;
  UPDATE gema.eventos SET estado = nuevo, cambiado = now()
   WHERE id = eid AND usuario_id = uid RETURNING * INTO ev;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'No encontré esa actividad en tu agenda.'); END IF;
  -- Si ya no está pendiente, sus avisos pospuestos dejan de tener sentido
  IF nuevo <> 'pendiente' THEN
    DELETE FROM gema.notificaciones WHERE evento_id = eid AND para > now();
  END IF;
  RETURN jsonb_build_object('ok', true, 'evento', gema.ficha(ev));
END $$;

-- Texto amable para avisar de un choque
CREATE OR REPLACE FUNCTION gema.nota_choque(titulo text, r jsonb) RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN jsonb_array_length(coalesce(r->'choques', '[]')) = 0 THEN NULL
    ELSE '◆ Ojo: «' || titulo || '» se cruza con '
         || (SELECT string_agg('«' || (c->>'titulo') || '» (' || (c->>'hora') || ')', ' y ')
               FROM jsonb_array_elements(r->'choques') c)
         || '.' || coalesce(' Tengo libre ese día a las ' || (r->>'sugerencia') || ', por si prefieres moverla.', '')
  END;
$$;

/* ---------- Conversación ---------- */

-- Reúne todo lo que la IA necesita saber para responder a esta persona
CREATE OR REPLACE FUNCTION gema.contexto(entrada jsonb) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE
  uid integer := gema.usuario_de(entrada->>'token');
  texto text := left(btrim(coalesce(entrada->>'texto', '')), 3000);
  clave_ia text;
BEGIN
  IF uid IS NULL THEN RETURN jsonb_build_object('ok', false, 'motivo', 'sesion'); END IF;
  IF texto = '' THEN RETURN jsonb_build_object('ok', false, 'motivo', 'vacio'); END IF;

  SELECT coalesce(nullif(u.clave_gemini, ''), (SELECT valor FROM gema.ajustes WHERE clave = 'clave_gemini'))
    INTO clave_ia FROM gema.usuarios u WHERE u.id = uid;
  IF coalesce(clave_ia, '') = '' THEN RETURN jsonb_build_object('ok', false, 'motivo', 'sin_clave'); END IF;

  INSERT INTO gema.mensajes (usuario_id, rol, texto) VALUES (uid, 'yo', texto);

  RETURN jsonb_build_object(
    'ok', true,
    'uid', uid,
    'texto', texto,
    'clave', clave_ia,
    'modelo', (SELECT valor FROM gema.ajustes WHERE clave = 'modelo'),
    'respaldo', (SELECT valor FROM gema.ajustes WHERE clave = 'modelo_respaldo'),
    'api', (SELECT valor FROM gema.ajustes WHERE clave = 'api_gemini'),
    'zona', current_setting('TimeZone'),
    'ahora', gema.dia_nombre(now()) || ' ' || to_char(now(), 'DD/MM/YYYY HH24:MI'),
    'ahora_iso', gema.iso(now()),
    'perfil', gema.perfil(uid),
    'agenda', (SELECT coalesce(jsonb_agg(f ORDER BY f->>'inicio'), '[]'::jsonb) FROM (
                 SELECT gema.ficha(e) f FROM gema.eventos e
                  WHERE e.usuario_id = uid AND e.estado = 'pendiente'
                    AND e.fin > date_trunc('day', now()) - interval '1 day'
                  ORDER BY e.inicio LIMIT 80) s),
    'recientes', (SELECT coalesce(jsonb_agg(f), '[]'::jsonb) FROM (
                 SELECT gema.ficha(e) f FROM gema.eventos e
                  WHERE e.usuario_id = uid AND e.estado <> 'pendiente'
                  ORDER BY e.cambiado DESC LIMIT 8) s),
    'recuerdos', (SELECT coalesce(jsonb_agg(r.dato ORDER BY r.id), '[]'::jsonb)
                    FROM (SELECT * FROM gema.recuerdos WHERE usuario_id = uid ORDER BY id DESC LIMIT 40) r),
    'historial', (SELECT coalesce(jsonb_agg(jsonb_build_object('rol', m.rol, 'texto', left(m.texto, 1200)) ORDER BY m.id), '[]'::jsonb)
                    FROM (SELECT * FROM gema.mensajes WHERE usuario_id = uid ORDER BY id DESC LIMIT 13 OFFSET 1) m)
  );
END $$;

-- Aplica el plan que devolvió la IA, guarda la respuesta y arma el texto final
CREATE OR REPLACE FUNCTION gema.cerrar_turno(p jsonb) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE
  uid integer := (p->>'uid')::int;
  respuesta text := coalesce(nullif(btrim(p->>'respuesta'), ''), 'Listo.');
  a jsonb;
  r jsonb;
  notas text[] := '{}';
  cambios integer := 0;
  nota text;
BEGIN
  IF uid IS NULL OR NOT EXISTS (SELECT 1 FROM gema.usuarios WHERE id = uid) THEN
    RETURN jsonb_build_object('respuesta', 'Tu sesión terminó. Vuelve a entrar a tu perfil.', 'cambios', 0);
  END IF;

  FOR a IN SELECT * FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p->'acciones') = 'array' THEN p->'acciones' ELSE '[]' END) LOOP
    BEGIN
      CASE a->>'accion'
        WHEN 'crear' THEN
          r := gema.crear_evento(uid, a);
          IF (r->>'ok')::boolean THEN
            cambios := cambios + 1;
            nota := gema.nota_choque(r#>>'{evento,titulo}', r);
            IF nota IS NOT NULL THEN notas := notas || nota; END IF;
            IF (r->>'pasado')::boolean THEN
              notas := notas || ('◆ «' || (r#>>'{evento,titulo}') || '» quedó en una fecha que ya pasó. Si fue un error, dime la fecha correcta.');
            END IF;
          ELSE notas := notas || ('◆ ' || (r->>'error')); END IF;
        WHEN 'editar' THEN
          r := gema.editar_evento(uid, a);
          IF (r->>'ok')::boolean THEN
            cambios := cambios + 1;
            nota := gema.nota_choque(r#>>'{evento,titulo}', r);
            IF nota IS NOT NULL THEN notas := notas || nota; END IF;
          ELSE notas := notas || ('◆ ' || (r->>'error')); END IF;
        WHEN 'cancelar', 'completar' THEN
          r := gema.estado_evento(uid, nullif(a->>'id', '')::numeric::int,
                                  CASE a->>'accion' WHEN 'cancelar' THEN 'cancelado' ELSE 'hecho' END);
          IF (r->>'ok')::boolean THEN cambios := cambios + 1;
          ELSE notas := notas || ('◆ ' || (r->>'error')); END IF;
        WHEN 'recordar' THEN
          IF char_length(btrim(coalesce(a->>'dato', ''))) BETWEEN 2 AND 240 THEN
            INSERT INTO gema.recuerdos (usuario_id, dato) VALUES (uid, btrim(a->>'dato')) ON CONFLICT DO NOTHING;
          END IF;
        ELSE NULL;
      END CASE;
    EXCEPTION WHEN others THEN
      notas := notas || '◆ Una de las acciones no se pudo completar. Revisa la agenda.'::text;
    END;
  END LOOP;

  IF array_length(notas, 1) > 0 THEN
    respuesta := respuesta || E'\n\n' || array_to_string(notas, E'\n');
  END IF;
  INSERT INTO gema.mensajes (usuario_id, rol, texto) VALUES (uid, 'gema', respuesta);
  RETURN jsonb_build_object('respuesta', respuesta, 'cambios', cambios);
END $$;

/* ---------- Vigía de avisos (lo llama n8n cada minuto) ---------- */

-- Crea los avisos que ya tocan y devuelve los que deben salir por Telegram
CREATE OR REPLACE FUNCTION gema.vigilar()
RETURNS TABLE (id bigint, chat text, bot text, texto text)
LANGUAGE plpgsql AS $$
DECLARE
  bot_ text := (SELECT valor FROM gema.ajustes WHERE clave = 'telegram_bot');
BEGIN
  -- 1) Avisos escalonados y aviso a la hora exacta (m = 0)
  INSERT INTO gema.notificaciones (usuario_id, evento_id, clave, clase, titulo, cuerpo, para, telegram)
  SELECT e.usuario_id, e.id,
         'e' || e.id || '-' || m || '-' || extract(epoch FROM e.inicio)::bigint,
         CASE WHEN m = 0 THEN 'ahora' ELSE 'aviso' END,
         CASE WHEN m = 0 THEN 'Es la hora: ' || e.titulo ELSE e.titulo END,
         CASE WHEN m = 0 THEN 'Empieza ahora' ELSE 'Empieza ' || gema.cuando(e.inicio) || ' a las ' || gema.hora(e.inicio)
                                                  || ' (faltan ' || gema.texto_avisos(ARRAY[m]) || ')' END
           || CASE WHEN e.lugar <> '' THEN ' · ' || e.lugar ELSE '' END,
         e.inicio - make_interval(mins => m),
         CASE WHEN u.telegram_chat <> '' AND coalesce(bot_, '') <> '' THEN 'pendiente' ELSE 'no' END
    FROM gema.eventos e
    JOIN gema.usuarios u ON u.id = e.usuario_id
    CROSS JOIN LATERAL unnest(e.avisos || 0) AS m
   WHERE e.estado = 'pendiente'
     AND e.inicio - make_interval(mins => m) <= now()
     AND e.inicio - make_interval(mins => m) > now() - interval '30 min'   -- si la PC estuvo apagada, no se acumulan avisos viejos
     AND e.inicio > now() - interval '5 min'
  ON CONFLICT (usuario_id, clave) DO NOTHING;

  -- 2) Destello: resumen de la mañana (entre 6:30 y 12:00, una vez al día)
  IF localtime BETWEEN time '06:30' AND time '12:00' THEN
    INSERT INTO gema.notificaciones (usuario_id, clave, clase, titulo, cuerpo, telegram)
    SELECT u.id, 'destello-' || current_date, 'destello',
           'Buenos días, ' || u.nombre,
           coalesce((SELECT 'Hoy tienes ' || count(*) || CASE WHEN count(*) = 1 THEN ' actividad: ' ELSE ' actividades: ' END
                            || string_agg(gema.hora(e.inicio) || ' ' || e.titulo, ' · ' ORDER BY e.inicio)
                       FROM gema.eventos e
                      WHERE e.usuario_id = u.id AND e.estado = 'pendiente'
                        AND e.inicio::date = current_date AND e.inicio > now()),
                    'Hoy no tienes nada agendado. Buen día para adelantar pendientes.'),
           CASE WHEN u.telegram_chat <> '' AND coalesce(bot_, '') <> '' THEN 'pendiente' ELSE 'no' END
      FROM gema.usuarios u
     WHERE u.destello
    ON CONFLICT (usuario_id, clave) DO NOTHING;
  END IF;

  -- 3) Lo que falta enviar por Telegram
  RETURN QUERY
  SELECT n.id, u.telegram_chat, bot_,
         '💎 ' || n.titulo || E'\n' || n.cuerpo
    FROM gema.notificaciones n
    JOIN gema.usuarios u ON u.id = n.usuario_id
   WHERE n.telegram = 'pendiente' AND n.para <= now()
     AND u.telegram_chat <> '' AND coalesce(bot_, '') <> ''
   ORDER BY n.para
   LIMIT 25;
END $$;

-- Recibe {"id": 12, "ok": true} después de intentar el envío por Telegram
CREATE OR REPLACE FUNCTION gema.marcar_telegram(j jsonb) RETURNS jsonb
LANGUAGE sql AS $$
  UPDATE gema.notificaciones SET telegram = CASE WHEN coalesce((j->>'ok')::boolean, false) THEN 'enviado' ELSE 'fallo' END
   WHERE id = (j->>'id')::bigint
  RETURNING jsonb_build_object('id', id, 'telegram', telegram);
$$;

/* ---------- Puerta única del panel ---------- */

-- Todas las acciones del panel pasan por aquí: ruta + ficha de sesión + datos
CREATE OR REPLACE FUNCTION gema.api(e jsonb) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE
  ruta text := coalesce(e->>'ruta', '');
  d jsonb := CASE WHEN jsonb_typeof(e->'datos') = 'object' THEN e->'datos' ELSE '{}'::jsonb END;
  uid integer;
  nuevo integer;
  r jsonb;
  desde timestamptz;
  hasta timestamptz;
  ints integer[];
BEGIN
  /* --- Rutas públicas (antes de entrar a un perfil) --- */
  IF ruta = 'inicio' THEN
    RETURN jsonb_build_object('ok', true,
      'perfiles', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'nombre', nombre, 'gema', gema,
                                                                'tiene_pin', pin_hash IS NOT NULL) ORDER BY id), '[]'::jsonb)
                     FROM gema.usuarios),
      'clave_comun', (SELECT valor <> '' FROM gema.ajustes WHERE clave = 'clave_gemini'));

  ELSIF ruta = 'crear-perfil' THEN
    IF coalesce(btrim(d->>'nombre'), '') = '' THEN RETURN jsonb_build_object('ok', false, 'error', 'Escribe tu nombre.'); END IF;
    IF (SELECT count(*) FROM gema.usuarios) >= 12 THEN RETURN jsonb_build_object('ok', false, 'error', 'Ya hay 12 perfiles en esta computadora.'); END IF;
    IF coalesce(d->>'pin', '') <> '' AND (d->>'pin') !~ '^\d{4}$' THEN RETURN jsonb_build_object('ok', false, 'error', 'El PIN debe tener 4 números.'); END IF;
    INSERT INTO gema.usuarios (nombre, gema, tono, intereses, sobre_mi, pin_hash, clave_gemini, telegram_chat)
    VALUES (left(btrim(d->>'nombre'), 40),
            CASE WHEN d->>'gema' IN ('rubi','zafiro','esmeralda','ambar','amatista','opalo') THEN d->>'gema' ELSE 'rubi' END,
            CASE WHEN d->>'tono' IN ('cercano','profesional','motivador','directo','divertido') THEN d->>'tono' ELSE 'cercano' END,
            coalesce((SELECT array_agg(left(btrim(x), 30)) FROM jsonb_array_elements_text(coalesce(d->'intereses', '[]')) x WHERE btrim(x) <> ''), '{}'),
            left(coalesce(d->>'sobre_mi', ''), 600),
            CASE WHEN coalesce(d->>'pin', '') <> '' THEN crypt(d->>'pin', gen_salt('bf')) END,
            btrim(coalesce(d->>'clave_propia', '')),
            btrim(coalesce(d->>'telegram_chat', '')))
    RETURNING id INTO nuevo;
    IF btrim(coalesce(d->>'clave_comun', '')) <> '' THEN
      UPDATE gema.ajustes SET valor = btrim(d->>'clave_comun'), cambiado = now() WHERE clave = 'clave_gemini';
    END IF;
    INSERT INTO gema.notificaciones (usuario_id, clave, clase, titulo, cuerpo)
    VALUES (nuevo, 'bienvenida', 'sistema', 'Tu gema está lista',
            'Pídeme cosas como: "agéndame el examen de Física el jueves a las 8 y avísame un día antes".');
    RETURN jsonb_build_object('ok', true, 'token', gema.abrir_sesion(nuevo), 'perfil', gema.perfil(nuevo));

  ELSIF ruta = 'entrar' THEN
    SELECT id INTO uid FROM gema.usuarios
     WHERE id = nullif(d->>'id', '')::numeric::int
       AND (pin_hash IS NULL OR pin_hash = crypt(coalesce(d->>'pin', ''), pin_hash));
    IF uid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'PIN incorrecto.'); END IF;
    RETURN jsonb_build_object('ok', true, 'token', gema.abrir_sesion(uid), 'perfil', gema.perfil(uid));
  END IF;

  /* --- Rutas privadas: necesitan una sesión válida --- */
  uid := gema.usuario_de(e->>'token');
  IF uid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'sesion'); END IF;

  IF ruta = 'panel' THEN
    RETURN jsonb_build_object('ok', true,
      'perfil', gema.perfil(uid),
      'ahora', gema.iso(now()),
      'clave_comun', (SELECT valor <> '' FROM gema.ajustes WHERE clave = 'clave_gemini'),
      'telegram_bot', (SELECT valor <> '' FROM gema.ajustes WHERE clave = 'telegram_bot'),
      'siguiente', (SELECT gema.ficha(ev) FROM gema.eventos ev
                     WHERE ev.usuario_id = uid AND ev.estado = 'pendiente' AND ev.fin > now()
                     ORDER BY ev.inicio LIMIT 1),
      'hoy', (SELECT coalesce(jsonb_agg(gema.ficha(ev) ORDER BY ev.inicio), '[]'::jsonb) FROM gema.eventos ev
               WHERE ev.usuario_id = uid AND ev.estado <> 'cancelado' AND ev.inicio::date = current_date),
      'pulso', (SELECT jsonb_agg(jsonb_build_object(
                         'fecha', to_char(g, 'YYYY-MM-DD'), 'dia', left(gema.dia_nombre(g), 3), 'num', extract(day FROM g)::int,
                         'cantidad', (SELECT count(*) FROM gema.eventos ev WHERE ev.usuario_id = uid AND ev.estado = 'pendiente' AND ev.inicio::date = g::date),
                         'horas', (SELECT round(coalesce(sum(extract(epoch FROM ev.fin - ev.inicio)) / 3600, 0)::numeric, 1)
                                     FROM gema.eventos ev WHERE ev.usuario_id = uid AND ev.estado = 'pendiente' AND ev.inicio::date = g::date),
                         'clave', (SELECT bool_or(ev.importancia = 3) FROM gema.eventos ev WHERE ev.usuario_id = uid AND ev.estado = 'pendiente' AND ev.inicio::date = g::date))
                         ORDER BY g)
                  FROM generate_series(current_date::timestamptz, current_date::timestamptz + interval '13 days', interval '1 day') g),
      'sin_leer', (SELECT count(*) FROM gema.notificaciones n WHERE n.usuario_id = uid AND NOT n.leida AND n.para <= now()));

  ELSIF ruta = 'agenda' THEN
    desde := coalesce(gema.a_momento(d->>'desde'), date_trunc('week', now()));
    hasta := coalesce(gema.a_momento(d->>'hasta'), desde + interval '7 days');
    IF hasta - desde > interval '62 days' THEN hasta := desde + interval '62 days'; END IF;
    RETURN jsonb_build_object('ok', true, 'eventos',
      (SELECT coalesce(jsonb_agg(gema.ficha(ev) ORDER BY ev.inicio), '[]'::jsonb) FROM gema.eventos ev
        WHERE ev.usuario_id = uid AND ev.estado <> 'cancelado' AND ev.inicio < hasta AND ev.fin > desde));

  ELSIF ruta = 'evento-guardar' THEN
    IF nullif(d->>'id', '') IS NULL THEN r := gema.crear_evento(uid, d); ELSE r := gema.editar_evento(uid, d); END IF;
    IF (r->>'ok')::boolean THEN r := r || jsonb_build_object('nota', gema.nota_choque(r#>>'{evento,titulo}', r)); END IF;
    RETURN r;

  ELSIF ruta = 'evento-estado' THEN
    RETURN gema.estado_evento(uid, nullif(d->>'id', '')::numeric::int, coalesce(d->>'estado', ''));

  ELSIF ruta = 'bandeja' THEN
    -- Primero se entregan las nuevas (para mostrarlas como aviso emergente) y se marcan como mostradas
    WITH nuevas AS (
      UPDATE gema.notificaciones n SET mostrada = true
       WHERE n.usuario_id = uid AND NOT n.mostrada AND n.para <= now() AND n.para > now() - interval '12 hours'
      RETURNING n.*)
    SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'evento_id', evento_id, 'clase', clase,
                                                  'titulo', titulo, 'cuerpo', cuerpo) ORDER BY para), '[]'::jsonb)
      INTO r FROM nuevas;
    UPDATE gema.notificaciones SET mostrada = true WHERE usuario_id = uid AND NOT mostrada AND para <= now() - interval '12 hours';
    RETURN jsonb_build_object('ok', true, 'nuevas', r,
      'lista', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', n.id, 'evento_id', n.evento_id, 'clase', n.clase,
                                  'titulo', n.titulo, 'cuerpo', n.cuerpo, 'leida', n.leida,
                                  'cuando', gema.cuando(n.para) || ' ' || gema.hora(n.para),
                                  'evento_pendiente', (SELECT ev.estado = 'pendiente' AND ev.fin > now() FROM gema.eventos ev WHERE ev.id = n.evento_id))
                                  ORDER BY n.para DESC), '[]'::jsonb)
                  FROM (SELECT * FROM gema.notificaciones WHERE usuario_id = uid AND para <= now() ORDER BY para DESC LIMIT 40) n),
      'sin_leer', (SELECT count(*) FROM gema.notificaciones WHERE usuario_id = uid AND NOT leida AND para <= now()));

  ELSIF ruta = 'bandeja-leer' THEN
    UPDATE gema.notificaciones SET leida = true, mostrada = true
     WHERE usuario_id = uid AND para <= now() AND (nullif(d->>'id', '') IS NULL OR id = (d->>'id')::bigint);
    RETURN jsonb_build_object('ok', true);

  ELSIF ruta = 'posponer' THEN
    -- "Recuérdamelo en X minutos": crea un aviso nuevo a partir de otro
    SELECT jsonb_build_object('evento_id', n.evento_id, 'titulo', n.titulo, 'cuerpo', n.cuerpo) INTO r
      FROM gema.notificaciones n WHERE n.id = nullif(d->>'id', '')::bigint AND n.usuario_id = uid;
    IF r IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Aviso no encontrado.'); END IF;
    nuevo := least(greatest(coalesce(nullif(d->>'minutos', '')::numeric::int, 10), 1), 1440);
    UPDATE gema.notificaciones SET leida = true WHERE id = (d->>'id')::bigint;
    INSERT INTO gema.notificaciones (usuario_id, evento_id, clave, clase, titulo, cuerpo, para, telegram)
    VALUES (uid, nullif(r->>'evento_id', '')::int, 'pos-' || (d->>'id') || '-' || extract(epoch FROM clock_timestamp())::bigint,
            'pospuesto', regexp_replace(r->>'titulo', '^Es la hora: ', ''), 'Te lo recuerdo de nuevo, como pediste.',
            now() + make_interval(mins => nuevo),
            CASE WHEN (SELECT telegram_chat <> '' FROM gema.usuarios WHERE id = uid)
                  AND (SELECT valor <> '' FROM gema.ajustes WHERE clave = 'telegram_bot') THEN 'pendiente' ELSE 'no' END);
    RETURN jsonb_build_object('ok', true, 'minutos', nuevo);

  ELSIF ruta = 'historial' THEN
    RETURN jsonb_build_object('ok', true, 'mensajes',
      (SELECT coalesce(jsonb_agg(jsonb_build_object('rol', m.rol, 'texto', m.texto) ORDER BY m.id), '[]'::jsonb)
         FROM (SELECT * FROM gema.mensajes WHERE usuario_id = uid ORDER BY id DESC LIMIT 40) m));

  ELSIF ruta = 'historial-borrar' THEN
    DELETE FROM gema.mensajes WHERE usuario_id = uid;
    RETURN jsonb_build_object('ok', true);

  ELSIF ruta = 'recuerdos' THEN
    RETURN jsonb_build_object('ok', true, 'recuerdos',
      (SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'dato', dato) ORDER BY id DESC), '[]'::jsonb)
         FROM gema.recuerdos WHERE usuario_id = uid));

  ELSIF ruta = 'recuerdo-borrar' THEN
    DELETE FROM gema.recuerdos WHERE usuario_id = uid AND id = nullif(d->>'id', '')::numeric::int;
    RETURN jsonb_build_object('ok', true);

  ELSIF ruta = 'perfil-guardar' THEN
    IF d ? 'pin' AND coalesce(d->>'pin', '') <> '' AND (d->>'pin') !~ '^\d{4}$' THEN
      RETURN jsonb_build_object('ok', false, 'error', 'El PIN debe tener 4 números.');
    END IF;
    IF d ? 'avisos_defecto' THEN ints := gema.limpiar_avisos(d->'avisos_defecto', '{60,10}'); END IF;
    UPDATE gema.usuarios SET
      nombre        = coalesce(nullif(left(btrim(d->>'nombre'), 40), ''), nombre),
      gema          = CASE WHEN d->>'gema' IN ('rubi','zafiro','esmeralda','ambar','amatista','opalo') THEN d->>'gema' ELSE gema END,
      tono          = CASE WHEN d->>'tono' IN ('cercano','profesional','motivador','directo','divertido') THEN d->>'tono' ELSE tono END,
      intereses     = CASE WHEN jsonb_typeof(d->'intereses') = 'array'
                           THEN coalesce((SELECT array_agg(left(btrim(x), 30)) FROM jsonb_array_elements_text(d->'intereses') x WHERE btrim(x) <> ''), '{}')
                           ELSE intereses END,
      sobre_mi      = coalesce(left(d->>'sobre_mi', 600), sobre_mi),
      telegram_chat = coalesce(btrim(d->>'telegram_chat'), telegram_chat),
      clave_gemini  = CASE WHEN d ? 'clave_propia' THEN btrim(coalesce(d->>'clave_propia', '')) ELSE clave_gemini END,
      avisos_defecto = coalesce(ints, avisos_defecto),
      franja_inicio = coalesce(CASE WHEN d->>'franja_inicio' ~ '^\d{2}:\d{2}$' THEN (d->>'franja_inicio')::time END, franja_inicio),
      franja_fin    = coalesce(CASE WHEN d->>'franja_fin' ~ '^\d{2}:\d{2}$' THEN (d->>'franja_fin')::time END, franja_fin),
      destello      = coalesce((d->>'destello')::boolean, destello),
      pin_hash      = CASE WHEN NOT d ? 'pin' THEN pin_hash
                           WHEN coalesce(d->>'pin', '') = '' THEN NULL
                           ELSE crypt(d->>'pin', gen_salt('bf')) END
    WHERE id = uid;
    RETURN jsonb_build_object('ok', true, 'perfil', gema.perfil(uid));

  ELSIF ruta = 'ajustes-comunes' THEN
    IF d ? 'clave_comun' AND btrim(coalesce(d->>'clave_comun', '')) <> '' THEN
      UPDATE gema.ajustes SET valor = btrim(d->>'clave_comun'), cambiado = now() WHERE clave = 'clave_gemini';
    END IF;
    IF d ? 'telegram_bot' THEN
      UPDATE gema.ajustes SET valor = btrim(coalesce(d->>'telegram_bot', '')), cambiado = now() WHERE clave = 'telegram_bot';
    END IF;
    RETURN jsonb_build_object('ok', true);

  ELSIF ruta = 'perfil-borrar' THEN
    IF NOT EXISTS (SELECT 1 FROM gema.usuarios WHERE id = uid
                    AND (pin_hash IS NULL OR pin_hash = crypt(coalesce(d->>'pin', ''), pin_hash))) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'PIN incorrecto.');
    END IF;
    DELETE FROM gema.usuarios WHERE id = uid;
    RETURN jsonb_build_object('ok', true);

  ELSIF ruta = 'salir' THEN
    DELETE FROM gema.sesiones WHERE token = e->>'token';
    RETURN jsonb_build_object('ok', true);
  END IF;

  RETURN jsonb_build_object('ok', false, 'error', 'Ruta desconocida: ' || ruta);
END $$;
