# ProtoGema | Portal (interfaz + puente hacia n8n)
FROM python:3.12-alpine
ENV PYTHONUNBUFFERED=1 PUERTO=4646
WORKDIR /portal
COPY portal.py /portal/portal.py
COPY publico /portal/publico
RUN adduser -D -H gema
USER gema
EXPOSE 4646
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:4646/', timeout=2)" || exit 1
CMD ["python", "/portal/portal.py"]
