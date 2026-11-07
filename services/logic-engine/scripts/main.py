#!/usr/bin/env python3
"""ELIS MQTT connectivity and diagnostic echo; no equipment control."""
import json
import logging
import math
import os
import re
import signal
import threading
import time

import paho.mqtt.client as mqtt

BROKER = os.getenv("MQTT_BROKER", "mqtt-broker")
PORT = int(os.getenv("MQTT_PORT", "1883"))
HEARTBEAT_TOPIC = "vulcan/heartbeat"
REQUEST_TOPIC = "elis/diagnostics/logic-engine/request"
RESPONSE_TOPIC = "elis/diagnostics/logic-engine/response"
LOG = logging.getLogger("logic-engine")


def diagnostic_response(payload):
    """Accept a bounded synthetic sample and return its doubled value."""
    if len(payload) > 4096:
        raise ValueError("diagnostic packet too large")
    body = json.loads(payload)
    if not isinstance(body, dict):
        raise ValueError("diagnostic packet must be an object")
    if body.get("kind") != "elis-diagnostic" or body.get("source") != "node-red":
        raise ValueError("unexpected diagnostic source")
    run_id = body.get("run_id")
    if not isinstance(run_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", run_id):
        raise ValueError("invalid diagnostic run_id")
    value = body.get("value")
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError("diagnostic value must be numeric")
    if not math.isfinite(value) or abs(value) > 1_000_000:
        raise ValueError("diagnostic value out of range")
    return {
        "kind": "elis-diagnostic",
        "source": "logic-engine",
        "run_id": run_id,
        "input_value": value,
        "value": round(value * 2, 6),
        "processed_at": int(time.time()),
    }


def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
    stop = threading.Event()
    connected = threading.Event()
    client = mqtt.Client(
        callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
        client_id="elis-logic-engine",
        protocol=mqtt.MQTTv311,
    )
    client.max_queued_messages_set(100)
    client.reconnect_delay_set(min_delay=1, max_delay=30)

    def on_connect(client, userdata, flags, reason_code, properties):
        if reason_code.is_failure:
            LOG.error("MQTT connection rejected: %s", reason_code)
            return
        result, _ = client.subscribe(REQUEST_TOPIC, qos=1)
        if result != mqtt.MQTT_ERR_SUCCESS:
            LOG.error("Diagnostic subscription failed: %s", result)
            return
        connected.set()
        LOG.info("MQTT connected; diagnostic request subscription requested")

    def on_disconnect(client, userdata, flags, reason_code, properties):
        connected.clear()
        if not stop.is_set():
            LOG.warning("MQTT disconnected: %s; reconnecting", reason_code)

    def on_message(client, userdata, message):
        if message.topic != REQUEST_TOPIC or message.retain:
            return
        try:
            response = diagnostic_response(message.payload)
        except (ValueError, UnicodeError, OverflowError):
            LOG.warning("Invalid diagnostic packet ignored")
            return
        info = client.publish(RESPONSE_TOPIC, json.dumps(response, allow_nan=False), qos=1, retain=False)
        if info.rc == mqtt.MQTT_ERR_SUCCESS:
            LOG.info("Diagnostic response queued: %s", response["run_id"])
        else:
            LOG.error("Diagnostic publish failed: %s", info.rc)

    client.on_connect = on_connect
    client.on_disconnect = on_disconnect
    client.on_message = on_message
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda signum, frame: stop.set())
    client.connect_async(BROKER, PORT, keepalive=60)
    client.loop_start()
    LOG.info("Starting MQTT diagnostics on %s:%s", BROKER, PORT)
    try:
        while not stop.is_set():
            if connected.is_set():
                # Preserve the existing topic; Telegraf's JSON parser needs an object.
                info = client.publish(HEARTBEAT_TOPIC, json.dumps({"heartbeat": int(time.time())}), qos=1, retain=False)
                try:
                    info.wait_for_publish(timeout=3)
                    if not info.is_published():
                        LOG.warning("Heartbeat acknowledgement timed out")
                except (RuntimeError, ValueError):
                    LOG.warning("Heartbeat was not published")
            stop.wait(10)
    finally:
        client.disconnect()
        client.loop_stop()
        LOG.info("Stopped")


if __name__ == "__main__":
    main()
