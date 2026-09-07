FROM python:3.13-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY providers.py server.py ./
RUN useradd --create-home aurum && mkdir -p /data && chown aurum:aurum /data
USER aurum
ENV AURUM_DATABASE=/data/aurum.sqlite3
EXPOSE 8787
CMD ["gunicorn", "--bind", "0.0.0.0:8787", "--workers", "2", "--threads", "4", "--timeout", "90", "--limit-request-line", "4094", "server:app"]
