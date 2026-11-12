// Prepara los flujos y las credenciales de Cortana antes de arrancar n8n.
// Lee las claves desde las variables de entorno (archivo .env) y genera
// archivos temporales que luego se importan con la CLI de n8n.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const salida = process.argv[2] || '/tmp/cortana';
const carpetaFlujos = process.env.CORTANA_FLUJOS || '/cortana';
fs.mkdirSync(path.join(salida, 'flujos'), { recursive: true });

const gemini = (process.env.GEMINI_API_KEY || '').trim();
const tavily = (process.env.TAVILY_API_KEY || '').trim();
const modelo = (process.env.GEMINI_MODEL || 'gemini-3-flash-preview').trim();
const claveDb = (process.env.DB_PASSWORD || '').trim();

if (!gemini) {
  console.error('[Cortana] Falta GEMINI_API_KEY en el archivo .env. Ejecuta Configurar_Cortana.bat');
  process.exit(1);
}
if (!claveDb) {
  console.error('[Cortana] Falta DB_PASSWORD en el archivo .env. Vuelve a abrir Cortana con Iniciar_Cortana.bat');
  process.exit(1);
}

// 1) Flujo principal (chat + agenda)
const flujo = JSON.parse(fs.readFileSync(path.join(carpetaFlujos, 'cortana.json'), 'utf8'));
flujo.versionId = crypto.randomUUID();
flujo.active = false;
for (const nodo of flujo.nodes) {
  if (nodo.type === '@n8n/n8n-nodes-langchain.lmChatGoogleGemini') {
    nodo.parameters.modelName = 'models/' + modelo;
  }
}
if (!tavily) {
  // Sin clave de Tavily: se quita la herramienta de búsqueda para que el flujo no falle.
  const tav = flujo.nodes.find((n) => n.type.startsWith('@tavily/'));
  if (tav) {
    flujo.nodes = flujo.nodes.filter((n) => n !== tav);
    delete flujo.connections[tav.name];
  }
  console.log('[Cortana] Sin clave de Tavily: Cortana funcionará sin búsqueda web.');
}
fs.writeFileSync(path.join(salida, 'flujos', 'cortana.json'), JSON.stringify(flujo));

// 2) Flujo de recordatorios
const rec = JSON.parse(fs.readFileSync(path.join(carpetaFlujos, 'recordatorios.json'), 'utf8'));
rec.versionId = crypto.randomUUID();
rec.active = false;
fs.writeFileSync(path.join(salida, 'flujos', 'recordatorios.json'), JSON.stringify(rec));

// 3) Credenciales (n8n las cifra al importarlas)
const credenciales = [
  {
    id: 'cortanaGemini001',
    name: 'Gemini (Cortana)',
    type: 'googlePalmApi',
    data: { host: 'https://generativelanguage.googleapis.com', apiKey: gemini },
  },
  {
    id: 'cortanaPostgres1',
    name: 'Postgres (Cortana)',
    type: 'postgres',
    data: {
      host: process.env.DB_HOST || 'db',
      port: Number(process.env.DB_PORT || 5432),
      database: 'cortana',
      user: 'cortana',
      password: claveDb,
      ssl: 'disable',
      allowUnauthorizedCerts: false,
      maxConnections: 10,
    },
  },
];
if (tavily) {
  credenciales.push({
    id: 'cortanaTavily001',
    name: 'Tavily (Cortana)',
    type: 'tavilyApi',
    data: { apiKey: tavily, baseUrl: 'https://api.tavily.com' },
  });
}
fs.writeFileSync(path.join(salida, 'credenciales.json'), JSON.stringify(credenciales));
console.log('[Cortana] Flujos y credenciales preparados (modelo: ' + modelo + ').');
