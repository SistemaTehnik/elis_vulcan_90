#!/usr/bin/env python3
"""ELIS_Vulcan-90 — Logic Engine (заглушка)"""
import os, time
import paho.mqtt.client as mqtt

BROKER = os.getenv("MQTT_BROKER", "mqtt-broker")
PORT = int(os.getenv("MQTT_PORT", "1883"))

client = mqtt.Client()
client.connect(BROKER, PORT, 60)
print(f"[logic-engine] Подключён к MQTT {BROKER}:{PORT}", flush=True)

while True:
    client.publish("vulcan/heartbeat", int(time.time()))
    time.sleep(10)
