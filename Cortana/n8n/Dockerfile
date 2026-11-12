# Etapa 1: descargar el nodo comunitario de Tavily
FROM node:22-alpine AS nodos
WORKDIR /opt/cortana-nodos
RUN npm init -y >/dev/null && npm install --omit=dev @tavily/n8n-nodes-tavily@0.7.0

# Etapa 2: n8n con todo lo de Cortana
FROM n8nio/n8n:2.45.7
USER root
COPY --from=nodos --chown=node:node /opt/cortana-nodos /opt/cortana-nodos
COPY --chown=node:node cortana.json preparar.js arranque.sh /cortana/
# Por si el archivo se guardó con saltos de línea de Windows
RUN sed -i 's/\r$//' /cortana/arranque.sh && chmod +x /cortana/arranque.sh
USER node
ENTRYPOINT ["/bin/sh", "/cortana/arranque.sh"]
