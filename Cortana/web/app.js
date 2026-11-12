// =============================================================
//  Cortana: interfaz de chat
//  Habla con n8n a través de /api/cortana (nginx lo redirige).
// =============================================================

const API_CHAT = '/api/cortana';
const API_ESTADO = '/api/cortana-estado';
const API_CALENDARIO = '/api/cortana-agenda';

const TONOS = [
  { id: 'amigable', emoji: '😊', nombre: 'Amigable', desc: 'Cercana y cálida, como una amiga que sabe mucho.',
    instruccion: 'amigable, cálido y cercano, como una amiga que sabe mucho; tutea a la persona' },
  { id: 'formal', emoji: '🎩', nombre: 'Formal', desc: 'Profesional y respetuosa.',
    instruccion: 'formal, profesional y respetuoso; trata a la persona de usted' },
  { id: 'divertida', emoji: '🎉', nombre: 'Divertida', desc: 'Con humor y buena energía.',
    instruccion: 'divertido y con humor ligero, usando algún emoji de vez en cuando, sin dejar de ser útil' },
  { id: 'directa', emoji: '🎯', nombre: 'Directa', desc: 'Respuestas cortas, al grano.',
    instruccion: 'directo y conciso: respuestas cortas y al grano, sin rodeos' },
  { id: 'profesora', emoji: '📚', nombre: 'Profesora', desc: 'Explica paso a paso con paciencia.',
    instruccion: 'didáctico y paciente, como una buena profesora: explica paso a paso y con ejemplos sencillos' },
  { id: 'motivadora', emoji: '💪', nombre: 'Motivadora', desc: 'Te anima y te impulsa.',
    instruccion: 'motivador y positivo, que anima a la persona a lograr sus metas' },
];

const INTERESES_BASE = [
  'Tecnología', 'Programación', 'Ciberseguridad', 'Ciencia', 'Videojuegos', 'Música',
  'Cine y series', 'Deportes', 'Salud y bienestar', 'Cocina', 'Finanzas personales',
  'Idiomas', 'Arte y diseño', 'Viajes', 'Historia', 'Emprendimiento', 'Estudios',
];

// ---------- Datos guardados en este navegador ----------
const almacen = {
  leer(clave, defecto) {
    try { const v = localStorage.getItem('cortana.' + clave); return v ? JSON.parse(v) : defecto; }
    catch { return defecto; }
  },
  guardar(clave, valor) {
    try { localStorage.setItem('cortana.' + clave, JSON.stringify(valor)); } catch { /* sin almacenamiento */ }
  },
};

let perfil = almacen.leer('perfil', null);          // { nombre, tono, intereses[] }
let sesion = almacen.leer('sesion', null);          // id de la conversación
let historial = almacen.leer('historial', []);      // [{ quien, texto }]
let enviando = false;

const $ = (sel) => document.querySelector(sel);

// ---------- Navegación entre pantallas ----------
function mostrar(id) {
  document.querySelectorAll('.pantalla').forEach((p) => p.classList.toggle('activa', p.id === id));
}

// ---------- Esperar a que n8n esté listo ----------
async function esperarCortana() {
  mostrar('pantalla-espera');
  const inicio = Date.now();
  for (;;) {
    try {
      const r = await fetch(API_ESTADO, { cache: 'no-store' });
      if (r.ok) return;
    } catch { /* todavía no responde */ }
    const seg = Math.round((Date.now() - inicio) / 1000);
    $('#texto-espera').textContent = seg < 20
      ? 'Esto toma unos segundos.'
      : 'Sigue arrancando… la primera vez puede tardar un poco más.';
    await new Promise((ok) => setTimeout(ok, 1500));
  }
}

// ---------- Asistente de configuración ----------
let borrador = null;

function abrirConfig() {
  borrador = perfil ? JSON.parse(JSON.stringify(perfil)) : { nombre: '', tono: 'amigable', intereses: [] };
  $('#titulo-bienvenida').textContent = perfil ? 'Personaliza a Cortana' : '¡Hola! Soy Cortana';
  $('#campo-nombre').value = borrador.nombre;
  pintarTonos();
  pintarIntereses();
  irPaso(1);
  mostrar('pantalla-config');
  setTimeout(() => $('#campo-nombre').focus(), 50);
}

function irPaso(n) {
  if (n > 1) borrador.nombre = $('#campo-nombre').value.trim();
  document.querySelectorAll('.paso').forEach((p) => p.classList.toggle('activo', p.dataset.paso == n));
  document.querySelectorAll('.punto').forEach((p, i) => p.classList.toggle('activo', i < n));
}

function pintarTonos() {
  const cont = $('#lista-tonos');
  cont.innerHTML = '';
  for (const t of TONOS) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'tono';
    b.setAttribute('role', 'radio');
    b.setAttribute('aria-checked', String(borrador.tono === t.id));
    b.innerHTML = `<span class="emoji">${t.emoji}</span><strong>${t.nombre}</strong><small>${t.desc}</small>`;
    b.onclick = () => { borrador.tono = t.id; pintarTonos(); };
    cont.appendChild(b);
  }
}

function pintarIntereses() {
  const cont = $('#lista-intereses');
  cont.innerHTML = '';
  const todos = [...new Set([...INTERESES_BASE, ...borrador.intereses])];
  for (const nombre of todos) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'chip';
    b.textContent = nombre;
    b.setAttribute('aria-pressed', String(borrador.intereses.includes(nombre)));
    b.onclick = () => {
      const i = borrador.intereses.indexOf(nombre);
      if (i >= 0) borrador.intereses.splice(i, 1); else borrador.intereses.push(nombre);
      pintarIntereses();
    };
    cont.appendChild(b);
  }
}

$('#form-interes').addEventListener('submit', (e) => {
  e.preventDefault();
  const v = $('#campo-interes').value.trim();
  if (v && !borrador.intereses.includes(v)) borrador.intereses.push(v);
  $('#campo-interes').value = '';
  pintarIntereses();
});

document.querySelectorAll('[data-ir]').forEach((b) => b.addEventListener('click', () => irPaso(Number(b.dataset.ir))));
$('#campo-nombre').addEventListener('keydown', (e) => { if (e.key === 'Enter') irPaso(2); });

$('#btn-terminar').addEventListener('click', () => {
  const cambioDePerfil = !!perfil;
  perfil = borrador;
  almacen.guardar('perfil', perfil);
  // Si cambió el tono o los intereses, empieza una conversación nueva para que se note
  if (cambioDePerfil) nuevaConversacion();
  abrirChat();
});

// ---------- Chat ----------
function nuevaConversacion() {
  sesion = (crypto.randomUUID ? crypto.randomUUID() : String(Date.now()) + Math.random());
  historial = [];
  almacen.guardar('sesion', sesion);
  almacen.guardar('historial', historial);
  pintarHistorial();
}

function abrirChat() {
  if (!sesion) nuevaConversacion();
  $('#saludo').textContent = perfil.nombre ? `¿En qué te ayudo, ${perfil.nombre}?` : '¿En qué te ayudo hoy?';
  pintarSugerencias();
  pintarHistorial();
  mostrar('pantalla-chat');
  $('#entrada').focus();
}

function pintarSugerencias() {
  const ideas = ['¿Qué tengo en mi agenda esta semana?', 'Agéndame una reunión mañana a las 3 de la tarde'];
  for (const tema of perfil.intereses.slice(0, 2)) ideas.push(`Cuéntame algo interesante sobre ${tema.toLowerCase()}`);
  ideas.push('¿Cuáles son las noticias más importantes de hoy?');
  const cont = $('#sugerencias');
  cont.innerHTML = '';
  for (const idea of ideas.slice(0, 4)) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'sugerencia';
    b.textContent = idea;
    b.onclick = () => enviar(idea);
    cont.appendChild(b);
  }
}

function pintarHistorial() {
  const cont = $('#mensajes');
  cont.querySelectorAll('.msg').forEach((m) => m.remove());
  $('#vacio').style.display = historial.length ? 'none' : '';
  for (const m of historial) agregarBurbuja(m.quien, m.texto, false);
}

function agregarBurbuja(quien, texto, animarScroll = true, esError = false) {
  $('#vacio').style.display = 'none';
  const fila = document.createElement('div');
  fila.className = 'msg ' + quien + (esError ? ' error' : '');
  const burbuja = document.createElement('div');
  burbuja.className = 'burbuja';
  if (quien === 'yo') burbuja.textContent = texto;
  else burbuja.innerHTML = markdown(texto);
  if (quien === 'ella') {
    const o = document.createElement('div');
    o.className = 'orbe orbe-chico';
    fila.appendChild(o);
  }
  fila.appendChild(burbuja);
  $('#mensajes').appendChild(fila);
  if (animarScroll) fila.scrollIntoView({ behavior: 'smooth', block: 'end' });
  else $('#mensajes').scrollTop = $('#mensajes').scrollHeight;
  return fila;
}

async function enviar(texto) {
  texto = (texto || '').trim();
  if (!texto || enviando) return;
  enviando = true;
  $('#btn-enviar').disabled = true;
  $('#entrada').value = '';
  ajustarAltura();

  agregarBurbuja('yo', texto);
  historial.push({ quien: 'yo', texto });
  almacen.guardar('historial', historial);

  const pensando = agregarBurbuja('ella', '');
  pensando.querySelector('.burbuja').innerHTML = '<span class="escribiendo"><i></i><i></i><i></i></span>';
  document.body.classList.add('pensando');
  $('#estado-chat').textContent = 'Pensando…';

  const tono = TONOS.find((t) => t.id === perfil.tono) || TONOS[0];
  try {
    const r = await fetch(API_CHAT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        mensaje: texto,
        sessionId: sesion,
        nombre: perfil.nombre,
        tono: tono.instruccion,
        intereses: perfil.intereses,
      }),
    });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const datos = await r.json();
    const respuesta = (datos && datos.respuesta) || 'No recibí respuesta. ¿Puedes intentarlo de nuevo?';
    pensando.remove();
    agregarBurbuja('ella', respuesta);
    historial.push({ quien: 'ella', texto: respuesta });
    almacen.guardar('historial', historial);
  } catch (err) {
    pensando.remove();
    agregarBurbuja('ella',
      'Ups, no pude responder esta vez. 😕\n\n' +
      'Revisa tu conexión a internet e inténtalo de nuevo. Si sigue pasando, puede que tu clave de Gemini ' +
      'no sea válida o se haya agotado el límite gratuito por hoy: abre **Configurar_Cortana** para revisarla.',
      true, true);
    console.error('[Cortana]', err);
  } finally {
    enviando = false;
    $('#btn-enviar').disabled = false;
    document.body.classList.remove('pensando');
    $('#estado-chat').textContent = 'En línea';
    $('#entrada').focus();
  }
}

// ---------- Markdown sencillo y seguro ----------
function escapar(s) {
  return s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
function enLinea(s) {
  return s
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/(^|[^*])\*([^*\n]+)\*/g, '$1<em>$2</em>')
    .replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>')
    .replace(/(^|[\s(])(https?:\/\/[^\s<)]+)/g, '$1<a href="$2" target="_blank" rel="noopener">$2</a>');
}
function markdown(texto) {
  const bloques = escapar(texto || '').split(/```/);
  let html = '';
  bloques.forEach((b, i) => {
    if (i % 2 === 1) { html += '<pre><code>' + b.replace(/^\w*\n/, '') + '</code></pre>'; return; }
    let lista = null;
    for (const linea of b.split('\n')) {
      const ul = linea.match(/^\s*[-*•]\s+(.*)/);
      const ol = linea.match(/^\s*\d+[.)]\s+(.*)/);
      const h = linea.match(/^\s*#{1,6}\s+(.*)/);
      const tipo = ul ? 'ul' : ol ? 'ol' : null;
      if (lista && tipo !== lista) { html += `</${lista}>`; lista = null; }
      if (tipo) {
        if (!lista) { html += `<${tipo}>`; lista = tipo; }
        html += '<li>' + enLinea((ul || ol)[1]) + '</li>';
      } else if (h) {
        html += '<h3>' + enLinea(h[1]) + '</h3>';
      } else if (linea.trim()) {
        html += '<p>' + enLinea(linea) + '</p>';
      }
    }
    if (lista) html += `</${lista}>`;
  });
  return html;
}

// ---------- Caja de texto ----------
function ajustarAltura() {
  const t = $('#entrada');
  t.style.height = 'auto';
  t.style.height = Math.min(t.scrollHeight, 160) + 'px';
}
$('#entrada').addEventListener('input', ajustarAltura);
$('#entrada').addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); enviar($('#entrada').value); }
});
$('#form-chat').addEventListener('submit', (e) => { e.preventDefault(); enviar($('#entrada').value); });
$('#btn-nueva').addEventListener('click', () => { nuevaConversacion(); abrirChat(); });
$('#btn-ajustes').addEventListener('click', abrirConfig);

// ---------- Calendario: actividades por fecha y por hora ----------
const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto',
  'septiembre', 'octubre', 'noviembre', 'diciembre'];
const DIAS = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'];
const cal = { mes: null, elegido: null, porDia: {} };

const dos = (n) => String(n).padStart(2, '0');
const fechaISO = (f) => `${f.getFullYear()}-${dos(f.getMonth() + 1)}-${dos(f.getDate())}`;
function hora12(hhmm) {
  const [h, m] = hhmm.split(':').map(Number);
  return `${h % 12 || 12}:${dos(m)} ${h < 12 ? 'a. m.' : 'p. m.'}`;
}

function abrirCalendario() {
  const hoy = new Date();
  cal.mes = new Date(hoy.getFullYear(), hoy.getMonth(), 1);
  cal.elegido = fechaISO(hoy);
  mostrar('pantalla-calendario');
  cargarMes();
}

async function cargarMes() {
  // La rejilla empieza el lunes de la primera semana y muestra 6 semanas
  const inicio = new Date(cal.mes);
  inicio.setDate(1 - ((inicio.getDay() + 6) % 7));
  const fin = new Date(inicio);
  fin.setDate(inicio.getDate() + 41);
  $('#titulo-mes').textContent = `${MESES[cal.mes.getMonth()]} de ${cal.mes.getFullYear()}`;
  $('#estado-cal').textContent = 'Cargando actividades…';
  cal.porDia = {};
  pintarMes(inicio);
  pintarDia();
  try {
    const r = await fetch(`${API_CALENDARIO}?desde=${fechaISO(inicio)}&hasta=${fechaISO(fin)}`, { cache: 'no-store' });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const datos = await r.json();
    for (const a of datos.actividades || []) (cal.porDia[a.fecha] = cal.porDia[a.fecha] || []).push(a);
    const total = Object.values(cal.porDia).reduce((n, l) => n + l.length, 0);
    $('#estado-cal').textContent = total
      ? `${total} actividad${total === 1 ? '' : 'es'} en estas semanas. Toca un día para verlo por horas.`
      : 'No tienes actividades en estas semanas. Pídele a Cortana en el chat que agende algo.';
  } catch (err) {
    $('#estado-cal').textContent = 'No pude cargar las actividades. Inténtalo de nuevo en un momento.';
    console.error('[Cortana]', err);
  }
  pintarMes(inicio);
  pintarDia();
}

function pintarMes(inicio) {
  const cont = $('#rejilla-mes');
  cont.innerHTML = '';
  const hoy = fechaISO(new Date());
  for (let i = 0; i < 42; i++) {
    const f = new Date(inicio);
    f.setDate(inicio.getDate() + i);
    const iso = fechaISO(f);
    const acts = cal.porDia[iso] || [];
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'dia' + (f.getMonth() !== cal.mes.getMonth() ? ' fuera' : '') + (iso === hoy ? ' hoy' : '')
      + (iso === cal.elegido ? ' elegido' : '') + (acts.length ? ' con-act' : '');
    b.setAttribute('aria-label', `${f.getDate()} de ${MESES[f.getMonth()]}: ${acts.length} actividades`);
    let html = `<span class="num">${f.getDate()}</span>`;
    for (const a of acts.slice(0, 2)) html += `<span class="act">${a.hora} ${escapar(a.titulo)}</span>`;
    if (acts.length > 2) html += `<span class="mas">+${acts.length - 2} más</span>`;
    b.innerHTML = html;
    b.onclick = () => { cal.elegido = iso; pintarMes(inicio); pintarDia(); };
    cont.appendChild(b);
  }
}

function pintarDia() {
  const [a, m, d] = cal.elegido.split('-').map(Number);
  const f = new Date(a, m - 1, d);
  $('#titulo-dia').textContent = `${DIAS[f.getDay()]} ${d} de ${MESES[m - 1]}`;
  const acts = cal.porDia[cal.elegido] || [];
  const cont = $('#horas-dia');
  if (!acts.length) {
    cont.innerHTML = '<div class="dia-vacio"><div class="orbe orbe-mediano"></div>No tienes actividades este día.</div>';
    return;
  }
  // Una fila por hora: de 7 a. m. a 10 p. m., ampliando si hay algo antes o después
  const horas = acts.map((x) => Number(x.hora.slice(0, 2)));
  const desde = Math.min(7, ...horas), hasta = Math.max(22, ...horas);
  const ahora = new Date();
  const esHoy = cal.elegido === fechaISO(ahora);
  cont.innerHTML = '';
  for (let h = desde; h <= hasta; h++) {
    const fila = document.createElement('div');
    fila.className = 'hora-fila' + (esHoy && ahora.getHours() === h ? ' ahora' : '');
    let html = `<span>${hora12(dos(h) + ':00')}</span><div>`;
    for (const x of acts.filter((y) => Number(y.hora.slice(0, 2)) === h)) {
      html += `<div class="evento"><strong>${escapar(x.titulo)}</strong><small>${hora12(x.hora)}`
        + (x.recordar_min ? ` · aviso ${x.recordar_min} min antes` : '') + '</small>'
        + (x.descripcion ? `<br><small>${escapar(x.descripcion)}</small>` : '') + '</div>';
    }
    fila.innerHTML = html + '</div>';
    cont.appendChild(fila);
  }
}

$('#btn-calendario').addEventListener('click', abrirCalendario);
$('#btn-volver-chat').addEventListener('click', abrirChat);
$('#btn-hoy').addEventListener('click', abrirCalendario);
function cambiarMes(paso) {
  cal.mes.setMonth(cal.mes.getMonth() + paso);
  const hoy = new Date();
  // Al cambiar de mes se muestra el día 1 (o hoy, si es el mes actual)
  cal.elegido = (hoy.getMonth() === cal.mes.getMonth() && hoy.getFullYear() === cal.mes.getFullYear())
    ? fechaISO(hoy) : fechaISO(cal.mes);
  cargarMes();
}
$('#btn-mes-anterior').addEventListener('click', () => cambiarMes(-1));
$('#btn-mes-siguiente').addEventListener('click', () => cambiarMes(1));

// ---------- Inicio ----------
(async function iniciar() {
  await esperarCortana();
  if (!perfil) abrirConfig(); else abrirChat();
})();
