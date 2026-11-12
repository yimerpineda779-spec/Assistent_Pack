/* =====================================================================
   ProtoGema | lógica de la interfaz
   Escenas: despertar -> perfiles -> (forja) -> taller
   Todo lo que se guarda pasa por /api/... (portal -> n8n -> PostgreSQL)
   ===================================================================== */
'use strict';

const $ = (s, raiz = document) => raiz.querySelector(s);
const $$ = (s, raiz = document) => [...raiz.querySelectorAll(s)];

const GEMAS = [
  ['rubi', 'Rubí'], ['zafiro', 'Zafiro'], ['esmeralda', 'Esmeralda'],
  ['ambar', 'Ámbar'], ['amatista', 'Amatista'], ['opalo', 'Ópalo'],
];
const TONOS = [
  ['cercano', 'Cercano', 'Cálido, me tuteas y me llamas por mi nombre.'],
  ['profesional', 'Profesional', 'Formal y preciso, de usted.'],
  ['motivador', 'Motivador', 'Con energía, me empujas a cumplir.'],
  ['directo', 'Directo', 'Frases cortas, sin rodeos.'],
  ['divertido', 'Divertido', 'Relajado, con humor y algún emoji.'],
];
const INTERESES = ['Programación', 'Ciberseguridad', 'Redes', 'Bases de datos', 'Matemáticas', 'Física',
  'Música', 'Deportes', 'Videojuegos', 'Cine y series', 'Lectura', 'Idiomas', 'Emprendimiento'];
const OPCIONES_AVISO = [[10080, '1 semana'], [1440, '1 día'], [180, '3 h'], [60, '1 h'], [30, '30 min'], [10, '10 min']];
const SUGERENCIAS = ['¿Qué tengo hoy?', '¿Qué tengo esta semana?', 'Agéndame estudiar mañana a las 7 pm',
  'Busca un hueco libre de 2 horas el viernes', '¿Cuál es mi próximo examen?'];
const ICONOS_AVISO = { aviso: '◆', ahora: '⏰', pospuesto: '↻', destello: '☀', sistema: '✦' };

const estado = {
  ficha: guardado('protogema.ficha'),
  perfil: null,
  panel: null,
  inicio: null,
  semana: 0,
  forja: { gema: 'rubi', tono: 'cercano', intereses: new Set(), claveProbada: false },
  relojes: [],
  enviando: false,
};

/* ---------- utilidades ---------- */
function guardado(clave) { try { return localStorage.getItem(clave) || ''; } catch { return ''; } }
function guardar(clave, valor) { try { valor ? localStorage.setItem(clave, valor) : localStorage.removeItem(clave); } catch { /* sin almacenamiento */ } }
function esc(t) { return String(t ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }
function inicial(n) { return (String(n || '?').trim()[0] || '?').toUpperCase(); }
function dosDigitos(n) { return String(n).padStart(2, '0'); }
function isoLocal(f) { return `${f.getFullYear()}-${dosDigitos(f.getMonth() + 1)}-${dosDigitos(f.getDate())}T${dosDigitos(f.getHours())}:${dosDigitos(f.getMinutes())}`; }
function deIso(t) { const [d, h = '00:00'] = String(t).split('T'); const [a, m, dd] = d.split('-').map(Number); const [hh, mi] = h.split(':').map(Number); return new Date(a, m - 1, dd, hh, mi); }
const dormir = (ms) => new Promise((r) => setTimeout(r, ms));

// Markdown mínimo y seguro: **negritas**, listas con guiones y párrafos
function md(texto) {
  const lineas = esc(texto).split('\n');
  let html = '', enLista = false;
  for (const l of lineas) {
    const item = l.match(/^\s*[-*•]\s+(.*)/);
    if (item) { if (!enLista) { html += '<ul>'; enLista = true; } html += `<li>${item[1]}</li>`; continue; }
    if (enLista) { html += '</ul>'; enLista = false; }
    if (l.trim()) html += `<p>${l}</p>`;
  }
  if (enLista) html += '</ul>';
  return html.replace(/\*\*(.+?)\*\*/g, '<b>$1</b>');
}

async function api(ruta, datos = {}) {
  let r;
  try {
    r = await fetch('/api/' + ruta, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Gema-Token': estado.ficha || '' },
      body: JSON.stringify(datos),
    });
  } catch { return { ok: false, error: 'red' }; }
  let j;
  try { j = await r.json(); } catch { j = { ok: false, error: 'respuesta' }; }
  if (j && j.error === 'sesion') { salirLocal(); mostrarPerfiles(); }
  return j || { ok: false };
}

function escena(id) {
  $$('.escena').forEach((e) => e.classList.toggle('activa', e.id === 'escena-' + id));
}

function aplicarGema(g) { document.documentElement.dataset.gema = g || 'rubi'; }

function destello(titulo, cuerpo, opciones = {}) {
  const d = document.createElement('div');
  d.className = 'destello' + (opciones.id ? '' : ' simple');
  d.innerHTML = `<b>${esc(titulo)}</b>${cuerpo ? `<p>${esc(cuerpo)}</p>` : ''}`;
  if (opciones.id) {
    const fila = document.createElement('div');
    fila.className = 'fila';
    fila.innerHTML = '<button class="boton chico" data-p="10">Posponer 10 min</button>'
      + '<button class="boton chico" data-p="60">1 h</button>'
      + '<button class="boton brillante chico" data-listo>Entendido</button>';
    fila.addEventListener('click', async (ev) => {
      const b = ev.target.closest('button');
      if (!b) return;
      if (b.dataset.p) {
        const r = await api('posponer', { id: opciones.id, minutos: Number(b.dataset.p) });
        if (r.ok) destello('Listo', `Te lo recuerdo en ${b.dataset.p === '60' ? '1 hora' : '10 minutos'}.`);
      } else {
        await api('bandeja-leer', { id: opciones.id });
      }
      d.remove();
      revisarBandeja();
    });
    d.appendChild(fila);
  }
  $('#destellos').prepend(d);
  setTimeout(() => d.remove(), opciones.id ? 90000 : 6000);
}

/* ---------- sonido: dos notas suaves, como un cristal ---------- */
let audio;
function campanita() {
  try {
    audio = audio || new (window.AudioContext || window.webkitAudioContext)();
    [880, 1318.5].forEach((f, i) => {
      const o = audio.createOscillator(), g = audio.createGain();
      o.type = 'sine'; o.frequency.value = f;
      const t = audio.currentTime + i * 0.13;
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(0.18, t + 0.02);
      g.gain.exponentialRampToValueAtTime(0.0001, t + 0.9);
      o.connect(g).connect(audio.destination);
      o.start(t); o.stop(t + 1);
    });
  } catch { /* sin audio */ }
}

/* =====================================================================
   1. Despertar
   ===================================================================== */
async function despertar() {
  const frases = ['Puliendo tu gema…', 'Encendiendo el cerebro (n8n)…', 'Ordenando tu agenda…', 'Casi lista…'];
  for (let i = 0; i < 300; i++) {
    $('#texto-despertar').textContent = i > 25 ? 'La primera vez tarda un poco más. Sigo despertando…' : frases[Math.floor(i / 3) % frases.length];
    try {
      const r = await fetch('/api/latido', { cache: 'no-store' });
      if (r.ok && (await r.json()).vivo) return true;
    } catch { /* sigue esperando */ }
    await dormir(2000);
  }
  $('#texto-despertar').textContent = 'El cerebro no responde. Cierra ProtoGema y vuelve a abrirla.';
  return false;
}

/* =====================================================================
   2. Perfiles
   ===================================================================== */
async function mostrarPerfiles() {
  detenerRelojes();
  aplicarGema('rubi');
  escena('perfiles');
  const r = await api('inicio');
  estado.inicio = r;
  const rejilla = $('#rejilla-perfiles');
  rejilla.innerHTML = '';
  for (const p of r.perfiles || []) {
    const b = document.createElement('button');
    b.className = 'tarjeta-perfil';
    b.dataset.gema = p.gema;
    b.innerHTML = `<span class="avatar">${esc(inicial(p.nombre))}</span><b>${esc(p.nombre)}</b>
                   <span class="candado">${p.tiene_pin ? '◆ con PIN' : '&nbsp;'}</span>`;
    b.addEventListener('click', () => (p.tiene_pin ? pedirPin(p) : entrar(p.id, '')));
    rejilla.appendChild(b);
  }
  const nuevo = document.createElement('button');
  nuevo.className = 'tarjeta-perfil';
  nuevo.innerHTML = '<span class="avatar nuevo">+</span><b>Nuevo perfil</b><span class="candado">&nbsp;</span>';
  nuevo.addEventListener('click', abrirForja);
  rejilla.appendChild(nuevo);
  if (!(r.perfiles || []).length && r.ok) abrirForja();
}

async function entrar(id, pin) {
  const r = await api('entrar', { id, pin });
  if (!r.ok) return false;
  estado.ficha = r.token;
  guardar('protogema.ficha', r.token);
  $('#velo-pin').classList.add('oculto');
  await abrirTaller();
  return true;
}

function pedirPin(p) {
  let pin = '';
  const velo = $('#velo-pin');
  velo.dataset.gema = p.gema;
  $('#pin-avatar').textContent = inicial(p.nombre);
  $('#pin-nombre').textContent = p.nombre;
  const puntos = $$('#pin-puntos i');
  const pintar = () => puntos.forEach((i, n) => i.classList.toggle('lleno', n < pin.length));
  const teclado = $('#teclado');
  teclado.innerHTML = '';
  ['1', '2', '3', '4', '5', '6', '7', '8', '9', '⌫', '0', '✓'].forEach((k) => {
    const b = document.createElement('button');
    b.className = 'boton' + (k === '✓' ? ' brillante' : '');
    b.type = 'button';
    b.textContent = k;
    b.addEventListener('click', () => tecla(k));
    teclado.appendChild(b);
  });
  async function tecla(k) {
    if (k === '⌫') pin = pin.slice(0, -1);
    else if (k === '✓' || pin.length >= 4) { /* se envía abajo */ } else pin += k;
    pintar();
    if (pin.length === 4 || k === '✓') {
      const ok = await entrar(p.id, pin);
      if (!ok) {
        $('#pin-puntos').classList.add('error');
        setTimeout(() => { $('#pin-puntos').classList.remove('error'); pin = ''; pintar(); }, 450);
      }
    }
  }
  velo.onkeydown = (e) => {
    if (/^\d$/.test(e.key)) tecla(e.key);
    else if (e.key === 'Backspace') tecla('⌫');
    else if (e.key === 'Escape') velo.classList.add('oculto');
  };
  pintar();
  velo.classList.remove('oculto');
  velo.tabIndex = -1;
  velo.focus();
}

/* =====================================================================
   3. Forja (crear perfil)
   ===================================================================== */
function pintarGemas(contenedor, actual, alElegir) {
  contenedor.innerHTML = '';
  for (const [id, nombre] of GEMAS) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'muestra';
    b.dataset.gema = id;
    b.setAttribute('aria-pressed', String(id === actual));
    b.innerHTML = `<i></i>${nombre}`;
    b.addEventListener('click', () => {
      $$('.muestra', contenedor).forEach((x) => x.setAttribute('aria-pressed', String(x === b)));
      alElegir(id);
    });
    contenedor.appendChild(b);
  }
}

function pintarTonos(contenedor, actual, alElegir) {
  contenedor.innerHTML = '';
  for (const [id, nombre, texto] of TONOS) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'tono';
    b.setAttribute('aria-pressed', String(id === actual));
    b.innerHTML = `<b>${nombre}</b><small>${texto}</small>`;
    b.addEventListener('click', () => {
      $$('.tono', contenedor).forEach((x) => x.setAttribute('aria-pressed', String(x === b)));
      alElegir(id);
    });
    contenedor.appendChild(b);
  }
}

function pintarIntereses(contenedor, elegidos) {
  contenedor.innerHTML = '';
  const todos = [...new Set([...INTERESES, ...elegidos])];
  for (const t of todos) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'chip';
    b.textContent = t;
    b.setAttribute('aria-pressed', String(elegidos.has(t)));
    b.addEventListener('click', () => {
      elegidos.has(t) ? elegidos.delete(t) : elegidos.add(t);
      b.setAttribute('aria-pressed', String(elegidos.has(t)));
    });
    contenedor.appendChild(b);
  }
  const otro = document.createElement('input');
  otro.className = 'chip';
  otro.placeholder = '+ otro tema';
  otro.maxLength = 30;
  otro.style.width = '130px';
  otro.addEventListener('keydown', (e) => {
    if (e.key !== 'Enter') return;
    e.preventDefault();
    const v = otro.value.trim();
    if (v) { elegidos.add(v); pintarIntereses(contenedor, elegidos); }
  });
  contenedor.appendChild(otro);
}

function pasoForja(n) {
  $$('#escena-forja .paso').forEach((p) => p.classList.toggle('activo', p.dataset.paso === String(n)));
  $$('#facetas-progreso li').forEach((li, i) => {
    li.classList.toggle('hecho', i < n - 1);
    li.classList.toggle('actual', i === n - 1);
  });
  const enfocar = $(`#escena-forja .paso[data-paso="${n}"] input`);
  if (enfocar) setTimeout(() => enfocar.focus(), 60);
}

function abrirForja() {
  const f = estado.forja;
  f.gema = 'rubi'; f.tono = 'cercano'; f.intereses = new Set(); f.claveProbada = false;
  $$('#escena-forja input, #escena-forja textarea').forEach((i) => { if (i.type !== 'checkbox') i.value = ''; });
  $('#f-clave-estado').textContent = '';
  $('#f-error').textContent = '';
  aplicarGema(f.gema);
  $('#forja-avatar').textContent = '?';
  pintarGemas($('#f-gemas'), f.gema, (g) => { f.gema = g; aplicarGema(g); });
  pintarTonos($('#f-tonos'), f.tono, (t) => { f.tono = t; });
  pintarIntereses($('#f-intereses'), f.intereses);
  const hayClave = !!(estado.inicio && estado.inicio.clave_comun);
  $('#f-bloque-clave').classList.toggle('oculto', hayClave);
  $('#f-clave-lista').classList.toggle('oculto', !hayClave);
  pasoForja(1);
  escena('forja');
}

async function probarClave(clave, linea) {
  linea.className = 'estado-linea';
  linea.textContent = 'Probando la clave con Google…';
  const r = await api('probar-clave', { clave });
  linea.className = 'estado-linea ' + (r.ok ? 'bien' : 'mal');
  linea.textContent = r.ok ? '◆ ¡Funciona! La clave es válida.' : (r.error || 'La clave no funcionó.');
  return !!r.ok;
}

function prepararForja() {
  $('#f-nombre').addEventListener('input', (e) => { $('#forja-avatar').textContent = inicial(e.target.value || '?'); });
  $('#f-probar').addEventListener('click', async () => {
    const clave = $('#f-clave').value.trim();
    if (!clave) return;
    estado.forja.claveProbada = await probarClave(clave, $('#f-clave-estado'));
  });
  $('#f-clave').addEventListener('input', () => { estado.forja.claveProbada = false; });
  $$('#escena-forja [data-atras]').forEach((b) => b.addEventListener('click', () => pasoForja(Number(b.dataset.atras))));

  $$('#escena-forja .paso').forEach((form) => form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const n = Number(form.dataset.paso);
    if (n === 1 && !$('#f-nombre').value.trim()) return;
    if (n === 3) {
      const hayClave = !!(estado.inicio && estado.inicio.clave_comun);
      if (!hayClave && !estado.forja.claveProbada) {
        const clave = $('#f-clave').value.trim();
        if (!clave) { $('#f-clave-estado').className = 'estado-linea mal'; $('#f-clave-estado').textContent = 'Pega tu clave de Gemini para continuar.'; return; }
        estado.forja.claveProbada = await probarClave(clave, $('#f-clave-estado'));
        if (!estado.forja.claveProbada) return;
      }
    }
    if (n < 4) return pasoForja(n + 1);

    const pin = $('#f-pin').value.trim();
    if (pin && !/^\d{4}$/.test(pin)) { $('#f-error').textContent = 'El PIN debe tener exactamente 4 números.'; return; }
    const clave = $('#f-clave').value.trim();
    const compartir = $('#f-clave-compartir').checked;
    const r = await api('crear-perfil', {
      nombre: $('#f-nombre').value.trim(),
      gema: estado.forja.gema,
      tono: estado.forja.tono,
      intereses: [...estado.forja.intereses],
      sobre_mi: $('#f-sobre').value.trim(),
      telegram_chat: $('#f-telegram').value.trim(),
      pin,
      clave_comun: clave && compartir ? clave : '',
      clave_propia: clave && !compartir ? clave : '',
    });
    if (!r.ok) { $('#f-error').textContent = r.error || 'No pude crear el perfil.'; return; }
    estado.ficha = r.token;
    guardar('protogema.ficha', r.token);
    await abrirTaller(true);
  }));
}

/* =====================================================================
   4. Taller
   ===================================================================== */
function detenerRelojes() { estado.relojes.forEach(clearInterval); estado.relojes = []; }

function salirLocal() {
  estado.ficha = '';
  estado.perfil = null;
  guardar('protogema.ficha', '');
  detenerRelojes();
}

async function abrirTaller(recienCreado = false) {
  const r = await api('panel');
  if (!r.ok) return mostrarPerfiles();
  pintarPanel(r);
  escena('taller');
  irA('conversar');
  $('#hilo').innerHTML = '';
  const h = await api('historial');
  for (const m of h.mensajes || []) burbuja(m.rol, m.texto);
  if (!(h.mensajes || []).length || recienCreado) {
    burbuja('gema', `¡Hola, **${estado.perfil.nombre}**! Soy tu ProtoGema. Puedo llevar tu agenda y avisarte antes de cada cosa.\n`
      + '- Dime por ejemplo: "agéndame el examen de Física el jueves a las 8 am, avísame un día antes"\n'
      + '- O pregúntame: "¿qué tengo esta semana?"');
  }
  pintarSugerencias();
  detenerRelojes();
  estado.relojes.push(setInterval(revisarBandeja, 20000));
  estado.relojes.push(setInterval(recargarPanel, 60000));
  estado.relojes.push(setInterval(pintarCuenta, 1000));
  revisarBandeja();
  if ('Notification' in window && Notification.permission === 'default') {
    document.addEventListener('click', () => Notification.requestPermission().then(pintarPermiso), { once: true });
  }
  pintarPermiso();
  $('#mensaje').focus();
}

function pintarPanel(r) {
  estado.panel = r;
  estado.perfil = r.perfil;
  const p = r.perfil;
  aplicarGema(p.gema);
  guardar('protogema.gema', p.gema);
  $('#riel-avatar').textContent = inicial(p.nombre);
  $('#ajustes-nombre').textContent = p.nombre;
  const h = new Date().getHours();
  $('#saludo').textContent = `${h >= 5 && h < 12 ? 'Buenos días' : h >= 12 && h < 19 ? 'Buenas tardes' : 'Buenas noches'}, ${p.nombre}`;
  pintarCuenta();
  pintarLineaDia(r.hoy || []);
  pintarPulso(r.pulso || []);
  pintarGlobo(r.sin_leer);
}

async function recargarPanel() {
  const r = await api('panel');
  if (r.ok) pintarPanel(r);
}

function pintarCuenta() {
  const caja = $('#proximo');
  const s = estado.panel && estado.panel.siguiente;
  if (!s) {
    caja.innerHTML = '<span class="rotulo">Lo próximo</span><h3>Agenda despejada</h3><p class="suave" style="margin:0">Pídeme que agende algo y aparecerá aquí.</p>';
    return;
  }
  const ini = deIso(s.inicio), fin = deIso(s.fin), ahora = new Date();
  let resto = Math.max(0, ini - ahora);
  const enCurso = ini <= ahora && ahora < fin;
  const dd = Math.floor(resto / 864e5); resto -= dd * 864e5;
  const hh = Math.floor(resto / 36e5); resto -= hh * 36e5;
  const mm = Math.floor(resto / 6e4); const ss = Math.floor((resto - mm * 6e4) / 1000);
  caja.innerHTML = `<span class="rotulo">${enCurso ? 'En curso ahora' : 'Lo próximo'}</span>
    <h3>${esc(s.titulo)}</h3>
    <span class="suave">${esc(s.cuando)} · ${esc(s.hora)}${s.lugar ? ' · ' + esc(s.lugar) : ''}</span>
    ${enCurso ? '' : `<div class="cuenta"><div><b>${dd}</b><small>días</small></div><div><b>${dosDigitos(hh)}</b><small>horas</small></div>
      <div><b>${dosDigitos(mm)}</b><small>min</small></div><div><b>${dosDigitos(ss)}</b><small>seg</small></div></div>`}`;
  if (!enCurso && ini - ahora <= 0) recargarPanel();
}

function pintarLineaDia(hoy) {
  const ul = $('#linea-dia');
  if (!hoy.length) { ul.innerHTML = '<li class="pasado" style="cursor:default"><span class="hora">hoy</span><b>Sin actividades</b></li>'; return; }
  const ahora = new Date();
  ul.innerHTML = '';
  for (const e of hoy) {
    const li = document.createElement('li');
    const ini = deIso(e.inicio), fin = deIso(e.fin);
    li.className = (fin < ahora ? 'pasado ' : '') + (ini <= ahora && ahora < fin ? 'ahora ' : '') + (e.estado === 'hecho' ? 'hecho' : '');
    li.innerHTML = `<span class="hora">${esc(e.hora)} – ${esc(e.hora_fin)}</span><b>${esc(e.titulo)}</b>`;
    li.addEventListener('click', () => abrirCajon(e));
    ul.appendChild(li);
  }
}

function pintarPulso(pulso) {
  const caja = $('#pulso');
  caja.innerHTML = '';
  pulso.forEach((d, i) => {
    const nivel = d.horas >= 6 || d.cantidad >= 4 ? 3 : d.horas >= 3 || d.cantidad >= 2 ? 2 : d.cantidad >= 1 ? 1 : 0;
    const c = document.createElement('div');
    c.className = 'celda' + (d.clave ? ' clave' : '') + (i === 0 ? ' hoy' : '');
    c.dataset.nivel = nivel;
    c.title = `${d.dia} ${d.num}: ${d.cantidad} actividad(es), ${d.horas} h`;
    c.innerHTML = `<i>${d.num}</i>${esc(d.dia)}`;
    caja.appendChild(c);
  });
}

function pintarGlobo(n) {
  const g = $('#globo-avisos');
  g.textContent = n > 9 ? '9+' : String(n || 0);
  g.classList.toggle('oculto', !n);
}

function irA(vista) {
  $$('.vista').forEach((v) => v.classList.toggle('activa', v.id === 'vista-' + vista));
  $$('.riel-boton[data-ir]').forEach((b) => (b.dataset.ir === vista ? b.setAttribute('aria-current', 'page') : b.removeAttribute('aria-current')));
  if (vista === 'agenda') pintarSemana();
  if (vista === 'avisos') revisarBandeja(true);
  if (vista === 'ajustes') pintarAjustes();
}

/* ---------- Chat ---------- */
function burbuja(rol, texto, extra = '') {
  const b = document.createElement('div');
  b.className = 'burbuja ' + (rol === 'yo' ? 'yo' : 'gema');
  b.innerHTML = rol === 'yo' ? esc(texto).replace(/\n/g, '<br>') : md(texto) + extra;
  $('#hilo').appendChild(b);
  $('#hilo').scrollTop = $('#hilo').scrollHeight;
  return b;
}

function pintarSugerencias() {
  const caja = $('#sugerencias');
  caja.innerHTML = '';
  for (const s of SUGERENCIAS) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'chip';
    b.textContent = s;
    b.addEventListener('click', () => { $('#mensaje').value = s; enviar(); });
    caja.appendChild(b);
  }
}

async function enviar() {
  const campo = $('#mensaje');
  const texto = campo.value.trim();
  if (!texto || estado.enviando) return;
  estado.enviando = true;
  campo.value = '';
  campo.style.height = '';
  $('#sugerencias').classList.add('oculto');
  burbuja('yo', texto);
  const pensando = document.createElement('div');
  pensando.className = 'burbuja gema pensando';
  pensando.innerHTML = '<i></i><i></i><i></i> Pensando…';
  $('#hilo').appendChild(pensando);
  $('#hilo').scrollTop = $('#hilo').scrollHeight;
  const r = await api('hablar', { texto });
  pensando.remove();
  estado.enviando = false;
  if (r.error === 'despertando') burbuja('gema', 'Todavía estoy despertando. Inténtalo de nuevo en unos segundos.');
  else if (r.error === 'red') burbuja('gema', 'No pude comunicarme con ProtoGema. ¿Sigue encendida?');
  else if (r.respuesta) {
    burbuja('gema', r.respuesta, r.cambios > 0 ? `<span class="marca-cambio">◆ Agenda actualizada (${r.cambios})</span>` : '');
    if (r.cambios > 0) { recargarPanel(); if ($('#vista-agenda').classList.contains('activa')) pintarSemana(); }
  } else if (r.error !== 'sesion') burbuja('gema', 'Algo salió mal. Inténtalo otra vez.');
  campo.focus();
}

/* ---------- Agenda semanal ---------- */
const HORA_INICIO = 6, HORA_FIN = 24, ALTO_HORA = 52;

function lunesDe(desplazamiento) {
  const h = new Date(); h.setHours(0, 0, 0, 0);
  const dia = (h.getDay() + 6) % 7;
  h.setDate(h.getDate() - dia + desplazamiento * 7);
  return h;
}

async function pintarSemana() {
  const lunes = lunesDe(estado.semana);
  const domingo = new Date(lunes); domingo.setDate(lunes.getDate() + 7);
  const meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  const fin = new Date(domingo); fin.setDate(fin.getDate() - 1);
  $('#titulo-semana').innerHTML = estado.semana === 0 ? 'Esta <em>semana</em>'
    : `${lunes.getDate()} ${meses[lunes.getMonth()]} – ${fin.getDate()} ${meses[fin.getMonth()]}`;

  const r = await api('agenda', { desde: isoLocal(lunes), hasta: isoLocal(domingo) });
  const eventos = r.eventos || [];
  const rejilla = $('#semana');
  rejilla.innerHTML = '';
  const hoy = new Date(); hoy.setHours(0, 0, 0, 0);
  const nombres = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

  rejilla.appendChild(Object.assign(document.createElement('div'), { className: 'dia-cab' }));
  for (let i = 0; i < 7; i++) {
    const d = new Date(lunes); d.setDate(lunes.getDate() + i);
    const c = document.createElement('div');
    c.className = 'dia-cab' + (d.getTime() === hoy.getTime() ? ' hoy' : '');
    c.innerHTML = `<span class="rotulo">${nombres[i]}</span><b>${d.getDate()}</b>`;
    rejilla.appendChild(c);
  }
  const horas = document.createElement('div');
  horas.className = 'horas';
  for (let h = HORA_INICIO; h < HORA_FIN; h++) horas.innerHTML += `<span>${h === HORA_INICIO ? '' : (h % 12 || 12) + (h < 12 ? ' am' : ' pm')}</span>`;
  rejilla.appendChild(horas);

  for (let i = 0; i < 7; i++) {
    const d = new Date(lunes); d.setDate(lunes.getDate() + i);
    const col = document.createElement('div');
    col.className = 'columna' + (d.getTime() === hoy.getTime() ? ' hoy' : '');
    col.style.height = (HORA_FIN - HORA_INICIO) * ALTO_HORA + 'px';
    col.addEventListener('click', (ev) => {
      if (ev.target !== col) return;
      const minutos = Math.floor(ev.offsetY / ALTO_HORA * 2) * 30 + HORA_INICIO * 60;
      const f = new Date(d); f.setMinutes(minutos);
      abrirCajon(null, f);
    });

    // Actividades del día, repartidas en carriles si se cruzan
    const delDia = eventos.filter((e) => deIso(e.inicio).toDateString() === d.toDateString())
      .sort((a, b) => a.inicio.localeCompare(b.inicio));
    const carriles = [];
    delDia.forEach((e) => {
      let c = carriles.findIndex((finCarril) => finCarril <= e.inicio);
      if (c === -1) { c = carriles.length; carriles.push(''); }
      carriles[c] = e.fin; e._carril = c;
    });
    const total = Math.max(1, carriles.length);
    for (const e of delDia) {
      const ini = deIso(e.inicio);
      const minIni = Math.max(ini.getHours() * 60 + ini.getMinutes(), HORA_INICIO * 60);
      const alto = Math.max(22, Math.min(e.minutos, HORA_FIN * 60 - minIni) / 60 * ALTO_HORA - 2);
      const b = document.createElement('div');
      b.className = 'bloque' + (e.estado === 'hecho' ? ' hecho' : '');
      b.dataset.tipo = e.tipo;
      b.style.top = (minIni - HORA_INICIO * 60) / 60 * ALTO_HORA + 'px';
      b.style.height = alto + 'px';
      b.style.left = `calc(${(e._carril / total) * 100}% + 3px)`;
      b.style.width = `calc(${100 / total}% - 6px)`;
      b.style.right = 'auto';
      b.title = `${e.titulo} · ${e.hora} – ${e.hora_fin}`;
      b.innerHTML = `<span class="facetas">${'◆'.repeat(e.importancia)}</span><b>${esc(e.titulo)}</b><span class="mono">${esc(e.hora)}</span>`;
      b.addEventListener('click', () => abrirCajon(e));
      col.appendChild(b);
    }
    if (d.getTime() === hoy.getTime()) {
      const ahora = new Date();
      const m = ahora.getHours() * 60 + ahora.getMinutes();
      if (m >= HORA_INICIO * 60) {
        const linea = document.createElement('div');
        linea.className = 'linea-ahora';
        linea.style.top = (m - HORA_INICIO * 60) / 60 * ALTO_HORA + 'px';
        col.appendChild(linea);
      }
    }
    rejilla.appendChild(col);
  }
  // Se muestra desde la primera actividad de la semana (o desde las 7 a. m.)
  const primera = eventos.reduce((m, e) => Math.min(m, deIso(e.inicio).getHours()), 7);
  $('.semana-envoltura').scrollTop = Math.max(0, (primera - HORA_INICIO) * ALTO_HORA);
}

/* ---------- Cajón de actividad ---------- */
function pintarAvisosChips(contenedor, elegidos) {
  contenedor.innerHTML = '';
  for (const [m, t] of OPCIONES_AVISO) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'chip';
    b.textContent = t;
    b.dataset.m = m;
    b.setAttribute('aria-pressed', String(elegidos.includes(m)));
    b.addEventListener('click', () => b.setAttribute('aria-pressed', String(b.getAttribute('aria-pressed') !== 'true')));
    contenedor.appendChild(b);
  }
}
const leerAvisosChips = (c) => $$('.chip[aria-pressed="true"]', c).map((b) => Number(b.dataset.m));

function abrirCajon(e, fecha) {
  const cajon = $('#cajon');
  const f = e ? deIso(e.inicio) : fecha || (() => { const x = new Date(); x.setMinutes(0, 0, 0); x.setHours(x.getHours() + 1); return x; })();
  $('#cajon-titulo').textContent = e ? 'Editar actividad' : 'Nueva actividad';
  $('#e-id').value = e ? e.id : '';
  $('#e-titulo').value = e ? e.titulo : '';
  $('#e-dia').value = isoLocal(f).slice(0, 10);
  $('#e-hora').value = isoLocal(f).slice(11, 16);
  const minutos = String(e ? e.minutos : 60);
  if (![...$('#e-minutos').options].some((o) => o.value === minutos)) $('#e-minutos').add(new Option(minutos + ' min', minutos));
  $('#e-minutos').value = minutos;
  $('#e-tipo').value = e ? e.tipo : 'otro';
  $$('#e-importancia button').forEach((b) => b.setAttribute('aria-pressed', String(Number(b.dataset.valor) === (e ? e.importancia : 2))));
  pintarAvisosChips($('#e-avisos'), e ? e.avisos : (estado.perfil.avisos_defecto || [60, 10]));
  $('#e-lugar').value = e ? e.lugar : '';
  $('#e-notas').value = e ? e.notas : '';
  $('#e-nota').textContent = '';
  $('#e-estado-botones').classList.toggle('oculto', !e || e.estado !== 'pendiente');
  cajon.classList.add('abierto');
  cajon.setAttribute('aria-hidden', 'false');
  setTimeout(() => $('#e-titulo').focus(), 200);
}

function cerrarCajon() {
  $('#cajon').classList.remove('abierto');
  $('#cajon').setAttribute('aria-hidden', 'true');
}

async function guardarActividad(ev) {
  ev.preventDefault();
  const importancia = Number(($('#e-importancia [aria-pressed="true"]') || {}).dataset?.valor || 2);
  const datos = {
    titulo: $('#e-titulo').value.trim(),
    inicio: `${$('#e-dia').value}T${$('#e-hora').value}`,
    minutos: Number($('#e-minutos').value),
    tipo: $('#e-tipo').value,
    importancia,
    avisos: leerAvisosChips($('#e-avisos')),
    lugar: $('#e-lugar').value.trim(),
    notas: $('#e-notas').value.trim(),
  };
  if ($('#e-id').value) datos.id = Number($('#e-id').value);
  const r = await api('evento-guardar', datos);
  if (!r.ok) { $('#e-nota').className = 'estado-linea mal'; $('#e-nota').textContent = r.error || 'No se pudo guardar.'; return; }
  cerrarCajon();
  destello(datos.id ? 'Actividad actualizada' : 'Actividad agendada', r.nota ? r.nota.replace(/^◆\s*/, '') : `${r.evento.cuando}, ${r.evento.hora}. Te avisaré: ${r.evento.avisos_texto}.`);
  recargarPanel();
  if ($('#vista-agenda').classList.contains('activa')) pintarSemana();
}

async function cambiarEstado(nuevo) {
  const id = Number($('#e-id').value);
  if (!id) return;
  if (nuevo === 'cancelado' && !confirm('¿Cancelar esta actividad?')) return;
  const r = await api('evento-estado', { id, estado: nuevo });
  if (r.ok) {
    cerrarCajon();
    destello(nuevo === 'hecho' ? '¡Bien hecho!' : 'Actividad cancelada', r.evento.titulo);
    recargarPanel();
    if ($('#vista-agenda').classList.contains('activa')) pintarSemana();
  }
}

/* ---------- Avisos ---------- */
async function revisarBandeja(pintarLista = false) {
  if (!estado.ficha) return;
  const r = await api('bandeja');
  if (!r.ok) return;
  pintarGlobo(r.sin_leer);
  const nuevas = r.nuevas || [];
  if (nuevas.length) campanita();
  for (const n of nuevas) {
    destello(n.titulo, n.cuerpo, { id: n.id });
    if ('Notification' in window && Notification.permission === 'granted' && document.hidden) {
      try { new Notification('ProtoGema · ' + n.titulo, { body: n.cuerpo, icon: 'gema.svg', tag: 'pgema-' + n.id }); } catch { /* ignorar */ }
    }
  }
  if (nuevas.some((n) => n.clase === 'ahora')) recargarPanel();
  if (pintarLista || $('#vista-avisos').classList.contains('activa')) pintarAvisos(r.lista || []);
}

function pintarAvisos(lista) {
  const caja = $('#lista-avisos');
  if (!lista.length) { caja.innerHTML = '<div class="vacio">◇ Aún no tienes avisos. Cuando se acerque una actividad aparecerán aquí.</div>'; return; }
  caja.innerHTML = '';
  for (const n of lista) {
    const d = document.createElement('div');
    d.className = 'aviso tallado' + (n.leida ? '' : ' no-leido');
    d.innerHTML = `<span class="icono">${ICONOS_AVISO[n.clase] || '◆'}</span>
      <div><b>${esc(n.titulo)}</b><p>${esc(n.cuerpo)}</p><small>${esc(n.cuando)}</small></div>
      <div class="fila">${n.evento_pendiente ? '<button class="boton chico" data-p="10">+10 min</button><button class="boton chico" data-p="60">+1 h</button>' : ''}
      ${n.leida ? '' : '<button class="boton fantasma chico" data-leer>✓</button>'}</div>`;
    d.addEventListener('click', async (ev) => {
      const b = ev.target.closest('button');
      if (!b) return;
      if (b.dataset.p) { const r = await api('posponer', { id: n.id, minutos: Number(b.dataset.p) }); if (r.ok) destello('Pospuesto', `Te aviso de nuevo en ${b.dataset.p === '60' ? '1 hora' : '10 minutos'}.`); }
      else await api('bandeja-leer', { id: n.id });
      revisarBandeja(true);
    });
    caja.appendChild(d);
  }
}

function pintarPermiso() {
  const b = $('#b-permiso');
  if (!('Notification' in window)) { b.classList.add('oculto'); return; }
  b.classList.toggle('oculto', Notification.permission === 'granted');
  b.textContent = Notification.permission === 'denied' ? 'El navegador bloqueó los avisos' : 'Activar avisos del navegador';
  b.disabled = Notification.permission === 'denied';
}

/* ---------- Ajustes ---------- */
const ajustes = { gema: 'rubi', tono: 'cercano', intereses: new Set() };

async function pintarAjustes() {
  const p = estado.perfil;
  if (!p) return;
  ajustes.gema = p.gema; ajustes.tono = p.tono; ajustes.intereses = new Set(p.intereses || []);
  $('#a-nombre').value = p.nombre;
  pintarGemas($('#a-gemas'), p.gema, (g) => { ajustes.gema = g; aplicarGema(g); });
  pintarTonos($('#a-tonos'), p.tono, (t) => { ajustes.tono = t; });
  pintarIntereses($('#a-intereses'), ajustes.intereses);
  $('#a-sobre').value = p.sobre_mi || '';
  pintarAvisosChips($('#a-avisos-defecto'), p.avisos_defecto || []);
  $('#a-franja-inicio').value = p.franja_inicio;
  $('#a-franja-fin').value = p.franja_fin;
  $('#a-destello').checked = !!p.destello;
  $('#a-telegram').value = p.telegram_chat || '';
  $('#a-bot').value = '';
  $('#a-bot-estado').textContent = estado.panel.telegram_bot
    ? '◆ Ya hay un bot configurado. Escribe uno nuevo solo si quieres cambiarlo.'
    : 'Créalo una vez con @BotFather (/newbot). Lo comparten todos los perfiles.';
  $('#a-ia-estado').textContent = p.clave_propia ? 'Estás usando tu propia clave de Gemini.'
    : estado.panel.clave_comun ? 'Estás usando la clave compartida de esta computadora.' : 'Todavía no hay clave de Gemini.';
  $('#a-clave').value = '';
  $('#a-clave-linea').textContent = '';
  $('#a-pin-estado').textContent = p.tiene_pin ? 'Tu perfil tiene PIN. Escribe uno nuevo o déjalo vacío para quitarlo.' : 'Tu perfil no tiene PIN.';
  $('#a-pin').value = '';
  const r = await api('recuerdos');
  const ul = $('#a-recuerdos');
  ul.innerHTML = (r.recuerdos || []).length ? '' : '<li class="tenue">Aún no he aprendido nada. Cuéntame de ti en el chat.</li>';
  for (const x of r.recuerdos || []) {
    const li = document.createElement('li');
    li.innerHTML = `<span>${esc(x.dato)}</span><button title="Olvidar">✕</button>`;
    $('button', li).addEventListener('click', async () => { await api('recuerdo-borrar', { id: x.id }); li.remove(); });
    ul.appendChild(li);
  }
}

async function guardarPerfil(datos, mensaje) {
  const r = await api('perfil-guardar', datos);
  if (!r.ok) { destello('No se guardó', r.error || ''); return false; }
  estado.perfil = r.perfil;
  if (estado.panel) estado.panel.perfil = r.perfil;
  aplicarGema(r.perfil.gema);
  $('#riel-avatar').textContent = inicial(r.perfil.nombre);
  $('#ajustes-nombre').textContent = r.perfil.nombre;
  destello(mensaje);
  return true;
}

function prepararAjustes() {
  $('#a-perfil').addEventListener('submit', (e) => {
    e.preventDefault();
    guardarPerfil({ nombre: $('#a-nombre').value.trim(), gema: ajustes.gema, tono: ajustes.tono,
      intereses: [...ajustes.intereses], sobre_mi: $('#a-sobre').value.trim() }, 'Personalidad guardada');
  });
  $('#a-avisos').addEventListener('submit', async (e) => {
    e.preventDefault();
    const bot = $('#a-bot').value.trim();
    if (bot) { await api('ajustes-comunes', { telegram_bot: bot }); estado.panel.telegram_bot = true; }
    await guardarPerfil({ avisos_defecto: leerAvisosChips($('#a-avisos-defecto')), franja_inicio: $('#a-franja-inicio').value,
      franja_fin: $('#a-franja-fin').value, destello: $('#a-destello').checked, telegram_chat: $('#a-telegram').value.trim() }, 'Avisos guardados');
    pintarAjustes();
  });
  $('#a-ia').addEventListener('submit', async (e) => {
    e.preventDefault();
    const clave = $('#a-clave').value.trim();
    if (!clave) return;
    if (!(await probarClave(clave, $('#a-clave-linea')))) return;
    if ($('#a-clave-propia').checked) await guardarPerfil({ clave_propia: clave }, 'Clave propia guardada');
    else { await api('ajustes-comunes', { clave_comun: clave }); estado.panel.clave_comun = true; destello('Clave compartida guardada'); }
    pintarAjustes();
  });
  $('#a-seguridad').addEventListener('submit', async (e) => {
    e.preventDefault();
    const pin = $('#a-pin').value.trim();
    if (pin && !/^\d{4}$/.test(pin)) { destello('PIN no válido', 'Debe tener exactamente 4 números.'); return; }
    await guardarPerfil({ pin }, pin ? 'PIN actualizado' : 'PIN eliminado');
    pintarAjustes();
  });
}

/* =====================================================================
   Acciones generales (botones con data-accion)
   ===================================================================== */
const acciones = {
  'volver-perfiles': mostrarPerfiles,
  'cerrar-pin': () => $('#velo-pin').classList.add('oculto'),
  'cambiar-perfil': async () => { await api('salir'); salirLocal(); mostrarPerfiles(); },
  luz: () => {
    const clara = document.documentElement.dataset.luz !== 'clara';
    document.documentElement.dataset.luz = clara ? 'clara' : '';
    guardar('protogema.luz', clara ? 'clara' : '');
  },
  'nueva-actividad': () => abrirCajon(null),
  'cerrar-cajon': cerrarCajon,
  'marcar-hecho': () => cambiarEstado('hecho'),
  'cancelar-actividad': () => cambiarEstado('cancelado'),
  permiso: () => Notification.requestPermission().then(pintarPermiso),
  'leer-todo': async () => { await api('bandeja-leer', {}); revisarBandeja(true); },
  'quitar-clave-propia': async () => { await guardarPerfil({ clave_propia: '' }, 'Ahora usas la clave compartida'); pintarAjustes(); },
  'borrar-chat': async () => {
    if (!confirm('¿Borrar todo el historial del chat? Tu agenda no se toca.')) return;
    await api('historial-borrar');
    $('#hilo').innerHTML = '';
    destello('Historial borrado');
  },
  'borrar-perfil': async () => {
    if (!confirm('¿Borrar tu perfil con toda su agenda y sus avisos? Esto no se puede deshacer.')) return;
    const pin = estado.perfil.tiene_pin ? prompt('Escribe tu PIN para confirmar') || '' : '';
    const r = await api('perfil-borrar', { pin });
    if (!r.ok) { destello('No se borró', r.error || ''); return; }
    salirLocal();
    mostrarPerfiles();
  },
};

function preparar() {
  const plantilla = $('#plantilla-gema');
  $$('[data-gema-svg]').forEach((c) => c.appendChild(plantilla.content.cloneNode(true)));
  if (guardado('protogema.luz') === 'clara') document.documentElement.dataset.luz = 'clara';

  document.addEventListener('click', (e) => {
    const b = e.target.closest('[data-accion]');
    if (b && acciones[b.dataset.accion]) { e.preventDefault(); acciones[b.dataset.accion](); }
    const ir = e.target.closest('[data-ir]');
    if (ir) irA(ir.dataset.ir);
    const sem = e.target.closest('[data-semana]');
    if (sem) { const v = Number(sem.dataset.semana); estado.semana = v === 0 ? 0 : estado.semana + v; pintarSemana(); }
  });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') cerrarCajon(); });

  $('#redactor').addEventListener('submit', (e) => { e.preventDefault(); enviar(); });
  $('#mensaje').addEventListener('keydown', (e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); enviar(); } });
  $('#mensaje').addEventListener('input', (e) => { e.target.style.height = ''; e.target.style.height = Math.min(e.target.scrollHeight, 160) + 'px'; });

  $('#form-actividad').addEventListener('submit', guardarActividad);
  $('#e-importancia').addEventListener('click', (e) => {
    const b = e.target.closest('button');
    if (b) $$('#e-importancia button').forEach((x) => x.setAttribute('aria-pressed', String(x === b)));
  });
  document.addEventListener('visibilitychange', () => { if (!document.hidden && estado.ficha) revisarBandeja(); });

  prepararForja();
  prepararAjustes();
}

async function arrancar() {
  preparar();
  if (!(await despertar())) return;
  if (estado.ficha) {
    const r = await api('panel');
    if (r.ok) return abrirTaller();
  }
  mostrarPerfiles();
}

arrancar();
