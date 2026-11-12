# 💎 ProtoGema

**ProtoGema** es un asistente personal con **agenda inteligente** que funciona en tu propia computadora.
Varias personas pueden usarla en la misma PC: cada una tiene **su propio perfil** (su "gema"), con su color,
su forma de hablar, su agenda, sus avisos y lo que ProtoGema va aprendiendo de ella.

Funciona con **n8n** (el cerebro), **PostgreSQL** (el almacén), **Google Gemini** (la inteligencia)
y todo corre dentro de **Docker**, así que se puede llevar a cualquier computadora.

## Documentación

En la carpeta **`documentos`** están:

- **Manual de usuario de ProtoGema.pdf**: cómo se usa, paso a paso, con capturas.
- **Documentación técnica de ProtoGema.pdf**: cómo está construido y cómo funciona por dentro.
- **Instalación de ProtoGema en Linux.pdf**: guía para instalar y encender en Linux.

---

## Para usuarios

### Lo que necesitas (una sola vez)

1. **Docker Desktop** (gratis): <https://www.docker.com/products/docker-desktop/>
   Instálalo con las opciones por defecto y reinicia si te lo pide.
2. **Internet** (la primera vez descarga cerca de 800 MB).
3. **Una clave gratuita de Google Gemini**: <https://aistudio.google.com/apikey>
   (ProtoGema te explica cómo sacarla cuando creas tu perfil).

### Encender ProtoGema

| Sistema | Qué hacer |
|---|---|
| Windows | Doble clic en **`ProtoGema.bat`** (o en el acceso directo **ProtoGema** del escritorio) |
| Linux / macOS | En una terminal: `./protogema.sh` |

El lanzador revisa Docker, prepara todo, espera a que el cerebro despierte y abre
**<http://localhost:4646>** en tu navegador.

### Primera vez: forja tu gema

1. Pulsa **Nuevo perfil**.
2. Escribe tu nombre y **elige tu gema** (Rubí, Zafiro, Esmeralda, Ámbar, Amatista u Ópalo).
   Toda la interfaz se pinta con ese color cuando entras tú.
3. Elige **cómo quieres que te hable** (cercano, profesional, motivador, directo o divertido) y tus temas.
4. Pega tu **clave de Gemini** y pulsa **Probar**. Puedes compartirla con los demás perfiles o usarla solo para ti.
5. Si quieres, ponle un **PIN de 4 números** a tu perfil.

### Cómo se usa

Escríbele con tus palabras:

- *"Agéndame el examen de Física el jueves a las 8 am, avísame un día antes y una hora antes"*
- *"¿Qué tengo esta semana?"*
- *"Mueve la reunión del viernes a las 3 pm"*
- *"Ya entregué el informe de redes"* (lo marca como hecho)
- *"Busca un hueco libre de 2 horas el sábado"*

Lo que hace ProtoGema por ti:

- **Avisos escalonados**: varios avisos por actividad (por ejemplo 1 día, 1 hora y a la hora exacta).
- **Detecta choques**: si agendas algo encima de otra cosa, te avisa y te sugiere la siguiente hora libre del día.
- **Destello matutino**: cada mañana te deja un resumen de tu día.
- **Lo que sé de ti**: recuerda datos que le cuentas (tus materias, tus horarios) para responderte mejor.
- **Pulso de 14 días**: un mapa de colores que muestra qué días están más cargados.

### Pantallas

| Botón del riel | Para qué sirve |
|---|---|
| 💬 Conversar | Chat con tu ProtoGema, cuenta regresiva de lo próximo, órbita de hoy y pulso de 14 días |
| 📅 Agenda | Semana completa por horas. Clic en un hueco para crear, clic en una actividad para editarla |
| 🔔 Avisos | Tu bandeja: posponer 10 min o 1 h, marcar como leído |
| ⬡ Ajustes | Personalidad, avisos, Telegram, clave de Gemini, PIN y "lo que sé de ti" |
| 🌙 | Modo claro u oscuro |
| Tu inicial | Cambiar de perfil |

### Avisos en el teléfono (Telegram, opcional)

1. En Telegram, habla con **@BotFather**, escribe `/newbot` y copia el **token**. Esto se hace una sola vez por computadora.
2. En **Ajustes ▸ Avisos y horario**, pega el token en *Bot de Telegram de la casa*.
3. Cada persona escribe a **@userinfobot**, copia su número **Id** y lo pega en *Mi chat de Telegram*.
4. Cada persona le envía cualquier mensaje a su bot (Telegram no deja que un bot escriba primero).

Los avisos también salen dentro de ProtoGema (con un sonido suave) y como notificación del navegador.

### Apagar

Doble clic en **`Apagar ProtoGema.bat`** (Windows) o `./protogema.sh apagar` (Linux/macOS).
Tus perfiles y tu agenda **quedan guardados**.

### Si algo falla

| Problema | Solución |
|---|---|
| "Docker Desktop no está instalado" | Instálalo desde el enlace de arriba |
| Tarda mucho la primera vez | Es normal: descarga n8n y PostgreSQL. Las siguientes veces tarda segundos |
| "Tu clave de Gemini no funciona" | Ve a Ajustes ▸ Inteligencia y pega una nueva |
| "Llegaste al límite gratuito" | Espera un minuto. Si usas mucho, cada perfil puede tener su propia clave |
| El puerto 4646 está ocupado | Cambia `PUERTO_PROTOGEMA` en el archivo `.env` |
| Otros detalles | Revisa la carpeta `registros` |

---

## Para el desarrollador

### Estructura

```
ProtoGema/
├── ProtoGema.bat              ← doble clic para encender (Windows)
├── Apagar ProtoGema.bat
├── protogema.sh               ← encender / apagar / estado (Linux y macOS)
├── docker-compose.yml         ← los 4 servicios
├── configuracion-ejemplo.txt  ← modelo del .env (el real lo crea el lanzador)
├── lanzador/
│   ├── protogema.ps1          ← lanzador de Windows
│   ├── protogema.ico
│   └── protogema.png
├── almacen/                   ← PostgreSQL
│   ├── 01_tablas.sql          ← perfiles, sesiones, eventos, notificaciones, mensajes, recuerdos
│   └── 02_funciones.sql       ← toda la lógica de la agenda inteligente
├── cerebro/                   ← n8n
│   ├── arrancar.sh            ← registra la conexión, importa y publica los flujos
│   └── flujos/
│       ├── conversacion.json  ← chat con Gemini (plan JSON)
│       ├── portal.json        ← todas las acciones del panel
│       └── vigia.json         ← avisos cada minuto + Telegram
├── portal/                    ← interfaz
│   ├── Dockerfile             ← Python 3.12 (solo biblioteca estándar)
│   ├── portal.py              ← entrega la web y pasa /api/... a n8n
│   └── publico/               ← index.html, gema.css, gema.js, gema.svg, telegram.html
└── documentos/                ← manual de usuario, documentación técnica e instalación en Linux
```

### Servicios y puertos

| Servicio | Imagen | Puerto en tu PC | Qué hace |
|---|---|---|---|
| `almacen` | postgres:17-alpine | ninguno | Guarda todo |
| `estructura` | postgres:17-alpine | ninguno | Aplica `almacen/*.sql` en cada encendido y termina |
| `cerebro` | n8nio/n8n:2.45.7 | **5699** (editor de n8n) | Los 3 flujos |
| `portal` | protogema-portal (Python) | **4646** (la interfaz) | Web + puente hacia n8n |

Todo escucha solo en `127.0.0.1`: nadie más en tu red puede entrar.

### Cómo viaja un mensaje

1. El navegador envía `POST /api/hablar` con la **ficha de sesión** del perfil (`X-Gema-Token`).
2. `portal.py` lo pasa al webhook `gema/hablar` de n8n.
3. **Reunir contexto**: `gema.contexto()` valida la sesión y devuelve el perfil, la memoria, el historial y la agenda de **esa** persona.
4. **Preparar consulta** arma la personalidad y pide a Gemini un **JSON** con `respuesta` y `acciones`
   (`crear`, `editar`, `cancelar`, `completar`, `recordar`), usando `responseSchema`.
5. Si el modelo principal falla (límite, saturación), se usa el **modelo de respaldo**.
6. **Aplicar y guardar**: `gema.cerrar_turno()` ejecuta las acciones, detecta choques, sugiere huecos y guarda el chat.

La IA nunca escribe SQL: solo llena datos que las funciones validan.

### Avisos

- El flujo **Vigía** corre cada minuto y llama a `gema.vigilar()`, que crea los avisos que ya tocan
  (uno por cada minuto de `avisos` de la actividad, más el de la hora exacta) y el **Destello** de la mañana.
- El navegador revisa `/api/bandeja` cada 20 segundos y muestra los nuevos.
- Los que deben ir a Telegram salen del mismo flujo y se marcan como `enviado` o `fallo`.

### Editar los flujos

- Editor de n8n: <http://localhost:5699> (la primera vez pide crear un usuario).
- En cada encendido se vuelven a importar los archivos de `cerebro/flujos`. Si cambias un flujo en el editor,
  **expórtalo y reemplaza el .json** para no perder el cambio.
- Modelos de Gemini: tabla `gema.ajustes` (`modelo` y `modelo_respaldo`).

### Comandos útiles

```bash
docker compose up -d --build     # encender
docker compose logs -f cerebro   # ver lo que hace n8n
docker compose down              # apagar (los datos se conservan en los volúmenes)
docker compose down -v           # BORRAR todo (perfiles y agenda incluidos)
```

### Privacidad

- Las claves internas viven solo en `.env` (está en `.gitignore`).
- Las claves de Gemini y el bot de Telegram se guardan en el almacén local.
- Los PIN se guardan cifrados (bcrypt con `pgcrypto`).
- Las sesiones caducan a los 60 días sin uso.
