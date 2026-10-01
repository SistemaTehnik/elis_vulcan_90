FROM python:3.11-slim
WORKDIR /app
RUN pip install --no-cache-dir paho-mqtt
COPY scripts/ /app/scripts/
CMD ["python", "-u", "/app/scripts/main.py"]
