#!/usr/bin/env python3
"""
ProtoGema | Portal

Servidor pequeño (solo biblioteca estándar de Python) que:
  1. Entrega la interfaz web de la carpeta "publico".
  2. Pasa las peticiones /api/... al cerebro (n8n) dentro de Docker.
     El navegador nunca habla con n8n directamente.

Rutas:
  GET  /api/latido        -> ¿el cerebro ya despertó?
  POST /api/hablar        -> mensaje para la IA      (flujo "Conversación")
  POST /api/<ruta>        -> cualquier acción del panel (flujo "Portal")
"""
import json
import mimetypes
import os
import re
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CEREBRO = os.environ.get("CEREBRO_URL", "http://cerebro:5678").rstrip("/")
PUBLICO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "publico")
PUERTO = int(os.environ.get("PUERTO", "4646"))
LIMITE = 64 * 1024  # 64 KB por petición es más que suficiente para un chat
RUTA_VALIDA = re.compile(r"^[a-z][a-z-]{1,30}$")

mimetypes.add_type("application/manifest+json", ".webmanifest")
mimetypes.add_type("image/svg+xml", ".svg")


class Portal(BaseHTTPRequestHandler):
    server_version = "ProtoGema/2.0"

    # ---------- utilidades ----------
    def _enviar(self, codigo, cuerpo, tipo="application/json; charset=utf-8", cache="no-store"):
        if isinstance(cuerpo, (dict, list)):
            cuerpo = json.dumps(cuerpo, ensure_ascii=False).encode("utf-8")
        self.send_response(codigo)
        self.send_header("Content-Type", tipo)
        self.send_header("Content-Length", str(len(cuerpo)))
        self.send_header("Cache-Control", cache)
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Frame-Options", "DENY")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(cuerpo)

    def _al_cerebro(self, metodo, camino, datos=None, espera=150):
        cabeceras = {"Content-Type": "application/json"}
        ficha = self.headers.get("X-Gema-Token", "")
        if ficha:
            cabeceras["X-Gema-Token"] = ficha[:100]
        cuerpo = json.dumps(datos).encode("utf-8") if datos is not None else None
        pedido = urllib.request.Request(CEREBRO + camino, data=cuerpo, headers=cabeceras, method=metodo)
        # Sin proxys: el cerebro está en la misma red de Docker
        abridor = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        try:
            with abridor.open(pedido, timeout=espera) as r:
                return r.status, r.read()
        except urllib.error.HTTPError as e:
            # 404 = los flujos todavía no están publicados (el cerebro sigue despertando)
            if e.code == 404:
                return 503, json.dumps({"ok": False, "error": "despertando"}).encode()
            return e.code, e.read() or b'{"ok": false, "error": "cerebro"}'
        except Exception:
            return 503, json.dumps({"ok": False, "error": "despertando"}).encode()

    def _leer_json(self):
        largo = int(self.headers.get("Content-Length") or 0)
        if largo > LIMITE:
            return None
        crudo = self.rfile.read(largo) if largo else b"{}"
        try:
            datos = json.loads(crudo.decode("utf-8") or "{}")
            return datos if isinstance(datos, dict) else {}
        except ValueError:
            return {}

    # ---------- métodos HTTP ----------
    def do_GET(self):
        camino = self.path.split("?", 1)[0]
        if camino == "/api/latido":
            codigo, cuerpo = self._al_cerebro("GET", "/webhook/gema/latido", espera=5)
            return self._enviar(codigo, cuerpo)
        if camino.startswith("/api/"):
            return self._enviar(405, {"ok": False, "error": "Usa POST"})
        return self._archivo(camino)

    do_HEAD = do_GET

    def do_POST(self):
        camino = self.path.split("?", 1)[0]
        if not camino.startswith("/api/"):
            return self._enviar(404, {"ok": False, "error": "No existe"})
        ruta = camino[len("/api/"):]
        if not RUTA_VALIDA.match(ruta):
            return self._enviar(400, {"ok": False, "error": "Ruta no válida"})
        datos = self._leer_json()
        if datos is None:
            return self._enviar(413, {"ok": False, "error": "Mensaje demasiado largo"})

        if ruta == "hablar":
            texto = str(datos.get("texto", ""))[:3000]
            codigo, cuerpo = self._al_cerebro("POST", "/webhook/gema/hablar", {"texto": texto})
        else:
            paquete = {"ruta": ruta, "datos": datos if isinstance(datos, dict) else {}}
            codigo, cuerpo = self._al_cerebro("POST", "/webhook/gema/portal", paquete, espera=40)
        return self._enviar(codigo, cuerpo)

    def _archivo(self, camino):
        if camino in ("", "/"):
            camino = "/index.html"
        destino = os.path.normpath(os.path.join(PUBLICO, camino.lstrip("/")))
        # Nunca se sale de la carpeta "publico"
        if not destino.startswith(PUBLICO + os.sep) or not os.path.isfile(destino):
            destino = os.path.join(PUBLICO, "index.html")
        tipo = mimetypes.guess_type(destino)[0] or "application/octet-stream"
        if tipo.startswith("text/") or tipo in ("application/javascript", "image/svg+xml", "application/manifest+json"):
            tipo += "; charset=utf-8"
        with open(destino, "rb") as f:
            self._enviar(200, f.read(), tipo, cache="no-cache")

    def log_message(self, formato, *args):
        # Solo se registran los errores, no cada petición
        if args and str(args[1] if len(args) > 1 else "").startswith(("4", "5")):
            super().log_message(formato, *args)


if __name__ == "__main__":
    print(f"[ProtoGema] Portal escuchando en el puerto {PUERTO} (cerebro: {CEREBRO})", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PUERTO), Portal).serve_forever()
