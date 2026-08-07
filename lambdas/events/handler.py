"""
lambdas/events/handler.py

Handles: GET /events

Lists all events, and computes each one's "status" (Available / Limited / Full)
at read time from registeredCount vs totalCapacity — this field is never
stored, so it can't drift out of sync with the real numbers.
"""

import json
import os
import boto3

TABLE_NAME = os.environ.get("EVENTS_TABLE", "Events")
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)

LIMITED_THRESHOLD = 0.8  # 80%+ full triggers "Limited" instead of "Available"


def compute_status(registered_count: int, total_capacity: int) -> str:
    if total_capacity <= 0:
        return "Unavailable"
    if registered_count >= total_capacity:
        return "Full"
    if registered_count / total_capacity >= LIMITED_THRESHOLD:
        return "Limited"
    return "Available"


def response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",  # CORS: required for API Gateway's REST endpoints
        },
        "body": json.dumps(body),
    }


def handler(event, context):
    try:
        result = table.scan()  # fine at this table size; documented tradeoff, see README
        items = result.get("Items", [])

        events = []
        for item in items:
            registered = int(item.get("registeredCount", 0))
            capacity = int(item.get("totalCapacity", 0))
            events.append({
                "eventId": item["eventId"],
                "eventName": item.get("eventName"),
                "eventDate": item.get("eventDate"),
                "totalCapacity": capacity,
                "registeredCount": registered,
                "status": compute_status(registered, capacity),
            })

        return response(200, {"events": events})

    except Exception as e:
        # CloudWatch Logs captures this automatically — this is what the
        # REGISTRATION_FAILED-style metric filter pattern will key off of
        # for the equivalent error path in the registrations Lambda.
        print(f"ERROR listing events: {str(e)}")
        return response(500, {"error": "Failed to list events"})