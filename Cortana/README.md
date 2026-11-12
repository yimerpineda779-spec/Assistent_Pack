# Cortana, tu asistente virtual

Cortana es una asistente de inteligencia artificial que funciona en tu computadora.
Habla contigo en una ventana de chat sencilla, se adapta al **tono** que prefieras y a tus **temas de interés**, puede **buscar en internet** y lleva tu **agenda con recordatorios**.

---

## Para usuarios: cómo usar Cortana

### Lo que necesitas (una sola vez)

1. **Windows 10 u 11.**
2. **Docker Desktop** (gratis): <https://www.docker.com/products/docker-desktop/>
   Instálalo con las opciones que trae por defecto y reinicia si te lo pide.
3. **Una clave gratuita de Google Gemini**: <https://aistudio.google.com/apikey>
   Entra con tu cuenta de Google y pulsa *Create API key*. Cópiala.
4. *(Opcional)* **Una clave gratuita de Tavily** para que Cortana busque en internet: <https://app.tavily.com>

### Abrir Cortana

1. Haz doble clic en **`Iniciar_Cortana.bat`** (o en el acceso directo **Cortana** de tu escritorio, que se crea solo al abrirla y se vuelve a crear si lo borras).
2. La primera vez se abre una ventana para **pegar tus claves**. Cortana las verifica y las guarda.
3. Espera mientras aparece *"Iniciando Cortana"*. La primera vez tarda varios minutos porque descarga lo necesario; después tarda solo segundos.
4. Se abre la ventana de chat. Cortana te pregunta tu nombre, cómo quieres que te hable y qué temas te interesan.
5. ¡Listo! Escribe y conversa.

### Tu agenda

Pídele las cosas con tus palabras:

- *"Agéndame el examen de Física el jueves a las 8 de la mañana, avísame una hora antes"*
- *"¿Qué tengo esta semana?"* o *"¿Qué tengo mañana?"*
- *"Mueve el examen a las 10"* o *"Cancela la reunión del viernes"*

Los **recordatorios** salen como notificaciones de Windows. Mientras Cortana esté encendida verás su ícono junto al reloj (clic derecho para abrirla, revisar avisos o apagarla). Si no dices cuándo avisar, te avisa 30 minutos antes.

### Botones del chat

| Botón | Qué hace |
|---|---|
| **+** | Empieza una conversación nueva |
| **Ajustes** (líneas con círculos) | Cambia tu nombre, el tono o tus intereses |
| **Calendario** (ícono de calendario) | Muestra tus actividades por mes y, al tocar un día, organizadas por hora |

### Otros archivos

| Archivo | Para qué sirve |
|---|---|
| `Configurar_Cortana.bat` | Cambiar tus claves de Gemini o Tavily |
| `Detener_Cortana.bat` | Apagar Cortana para liberar memoria de la computadora |

### Si algo falla

- **"No pude responder esta vez"**: revisa tu internet. Si sigue pasando, tu clave de Gemini puede estar mal o se acabó el límite gratuito del día; usa `Configurar_Cortana.bat`.
- **Tarda mucho en abrir**: asegúrate de que Docker Desktop esté abierto y diga *Engine running*.
- En la carpeta **`logs`** quedan los detalles de cada arranque.

---

## Para el desarrollador: cómo está hecho

```
Cortana/
├── Iniciar_Cortana.bat      ← doble clic para abrir
├── Configurar_Cortana.bat   ← cambiar claves
├── Detener_Cortana.bat      ← apagar
├── docker-compose.yml       ← define los 2 contenedores
├── .env.example             ← plantilla (el .env real lo crea el lanzador)
├── lanzador/
│   ├── Cortana.ps1          ← lanzador con ventanas (Windows Forms)
│   └── cortana.ico
├── db/
│   └── init.sql             ← crea la tabla de la agenda (solo la primera vez)
├── n8n/                     ← el "cerebro"
│   ├── Dockerfile           ← n8n 2.45.7 + nodo de Tavily ya instalado
│   ├── arranque.sh          ← importa flujos y claves, luego inicia n8n
│   ├── preparar.js          ← arma los flujos y las credenciales desde el .env
│   ├── cortana.json         ← flujo principal (chat + herramientas de agenda)
│   └── recordatorios.json   ← flujo que entrega los recordatorios vencidos
└── web/                     ← la "cara"
    ├── index.html, estilos.css, app.js
    └── nginx.conf           ← sirve la web y pasa /api/ a n8n
```

### Cómo viaja un mensaje

1. El usuario escribe en la ventana de chat (`web/`).
2. `app.js` envía a `/api/cortana`: `mensaje`, `sessionId`, `nombre`, `tono` e `intereses`.
3. nginx lo pasa a n8n (`/webhook/cortana`).
4. El agente arma su mensaje de sistema con el nombre, el tono y los intereses, responde con Gemini (más memoria y Tavily) y devuelve `{ "respuesta": "..." }`.

### La agenda

- Tercer contenedor `cortana-db` (PostgreSQL 16) con la tabla `actividades` y la memoria de las conversaciones (`cortana_memoria`), en el volumen `cortana_agenda`.
- El agente tiene 4 herramientas: `agendar_actividad`, `consultar_agenda`, `modificar_actividad` y `cancelar_actividad`. Cada una es una **consulta SQL fija y parametrizada**: la IA solo llena los datos, nunca escribe SQL, así que no hay inyección posible.
- El vigilante (`Cortana.ps1 -Vigilar`) consulta `/api/cortana-recordatorios` cada 30 segundos y muestra las notificaciones.

### Por qué ya no pasa el error de Zoe

El lanzador de Zoe abría el navegador apenas encendía n8n, cuando todavía no estaba listo.
El de Cortana **espera** hasta que `/api/cortana-estado` responde (un webhook que no usa la IA) y **solo entonces** abre la ventana. Además, la propia web muestra *"Cortana se está despertando…"* si la abres antes de tiempo.

### Datos y privacidad

- Las claves se guardan solo en el archivo `.env` de esta computadora (no lo compartas; ya está en `.gitignore`). Dentro de n8n quedan cifradas.
- El perfil del usuario y el historial visible del chat se guardan en el navegador de esa computadora.
- La memoria de las conversaciones y la agenda se guardan en PostgreSQL, así que no se pierden al apagar Cortana.
- Todo escucha solo en `127.0.0.1`: nadie más en tu red puede entrar.

### Editar el flujo

- Panel de n8n (solo para ti): <http://localhost:5679>. La primera vez te pedirá crear una cuenta de administrador.
- **Importante:** en cada arranque se vuelve a importar `n8n/cortana.json`. Si cambias el flujo en el panel, expórtalo y reemplaza ese archivo; luego reinicia Cortana.
- Cambiar el modelo de Gemini: edita `GEMINI_MODEL` en `.env` y reinicia.

### Comandos útiles

```bash
docker compose up -d --build   # arrancar (reconstruyendo)
docker compose logs -f n8n     # ver lo que hace n8n
docker compose down            # apagar y borrar contenedores (los datos se conservan)
```
