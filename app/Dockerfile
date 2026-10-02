FROM python:3.12-alpine

# Aplikasi ini hanya memakai standard library, jadi tidak ada dependensi
# pihak ketiga yang perlu dipasang.
WORKDIR /app
COPY app.py /app/app.py

# berjalan sebagai user biasa (bukan root)
RUN adduser -D -H -u 10001 appuser
USER appuser

ENV APP_PORT=8000 PYTHONUNBUFFERED=1
EXPOSE 8000

HEALTHCHECK --interval=15s --timeout=4s --retries=3 \
    CMD python -c "import urllib.request,sys;sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz',timeout=3).status==200 else 1)"

CMD ["python", "/app/app.py"]
