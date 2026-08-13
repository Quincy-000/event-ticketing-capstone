import json
import os
import uuid
from datetime import datetime, timezone
from urllib.parse import unquote

import boto3
from botocore.exceptions import ClientError

EVENTS_TABLE = os.environ.get("EVENTS_TABLE", "Events")
REGISTRATIONS_TABLE = os.environ.get("REGISTRATIONS_TABLE", "Registrations")

dynamodb = boto3.resource("dynamodb")
events_table = dynamodb.Table(EVENTS_TABLE)
registrations_table = dynamodb.Table(REGISTRATIONS_TABLE)


def response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "OPTIONS,POST,GET,DELETE",
            "Access-Control-Allow-Headers": "Content-Type, Authorization",
        },
        "body": json.dumps(body),
    }


# ---------- POST /register ----------
def register(event):
    claims = (event.get("requestContext") or {}).get("authorizer", {}).get("claims") or {}
    caller_email = (claims.get("email") or "").lower()
    if not caller_email:
        return response(401, {"error": "Authentication required"})

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return response(400, {"error": "Invalid JSON body"})

    event_id = body.get("eventId")
    email = caller_email  # always from verified token

    if not event_id:
        return response(400, {"error": "eventId is required"})

    # Dedupe check: has this email already got a confirmed registration
    # for this event? Reduces double-submits in the common case.
    # NOTE: this is a check-then-act read, not an atomic guard — a
    # genuinely simultaneous double-submit from the same email could
    # still slip both past this check before either write lands. That
    # residual race is documented in the README as an accepted scope
    # tradeoff (fixing it fully needs a composite-key conditional put,
    # out of scope here).
    try:
        existing = registrations_table.query(
            IndexName="email-index",
            KeyConditionExpression=boto3.dynamodb.conditions.Key("email").eq(email),
        )
        for reg in existing.get("Items", []):
            if reg.get("eventId") == event_id and reg.get("status") == "confirmed":
                return response(409, {"error": "Already registered for this event"})
    except ClientError as e:
        print(f"ERROR checking existing registration for {email}: {str(e)}")
        return response(500, {"error": "Failed to register"})

    try:
        # THE conditional write. This is the whole race-condition fix in
        # one call: DynamoDB only applies the increment if the condition
        # is still true AT THE MOMENT it commits — not when we checked
        # earlier. Two simultaneous requests against a 1-seat event:
        # exactly one of these succeeds, the other raises
        # ConditionalCheckFailedException. There is no window where both
        # can slip through.
        events_table.update_item(
            Key={"eventId": event_id},
            UpdateExpression="ADD registeredCount :inc",
            ConditionExpression="registeredCount < totalCapacity",
            ExpressionAttributeValues={":inc": 1},
        )
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            # Event is full. Log a structured line — this is what the
            # REGISTRATION_FAILED metric filter watches for in CloudWatch.
            print(f"REGISTRATION_FAILED eventId={event_id} reason=capacity_full")
            return response(409, {"error": "Event is full"})
        print(f"ERROR incrementing event {event_id}: {str(e)}")
        return response(500, {"error": "Failed to register"})

    registration_id = str(uuid.uuid4())
    registrations_table.put_item(Item={
        "registrationId": registration_id,
        "eventId": event_id,
        "email": email,
        "status": "confirmed",
        "registeredAt": datetime.now(timezone.utc).isoformat(),
    })

    return response(201, {
        "registrationId": registration_id,
        "eventId": event_id,
        "email": email,
        "status": "confirmed",
    })


# ---------- GET /registrations/{email} ----------
def get_by_email(event):
    claims = (event.get("requestContext") or {}).get("authorizer", {}).get("claims") or {}
    caller_email = (claims.get("email") or "").lower()
    if not caller_email:
        return response(401, {"error": "Authentication required"})

    # API Gateway v1 does NOT decode path params (e.g. %40 stays literal),
    # so decode here — handles both raw and percent-encoded callers.
    email = unquote(event.get("pathParameters", {}).get("email") or "").lower()
    if not email:
        return response(400, {"error": "email path parameter is required"})

    if email != caller_email:
        return response(403, {"error": "Access denied"})

    try:
        result = registrations_table.query(
            IndexName="email-index",
            KeyConditionExpression=boto3.dynamodb.conditions.Key("email").eq(email),
            FilterExpression=boto3.dynamodb.conditions.Attr("status").eq("confirmed"),
        )
        return response(200, {"registrations": result.get("Items", [])})
    except ClientError as e:
        print(f"ERROR querying registrations for {email}: {str(e)}")
        return response(500, {"error": "Failed to fetch registrations"})


# ---------- DELETE /registration/{id} ----------
def cancel(event):
    claims = (event.get("requestContext") or {}).get("authorizer", {}).get("claims") or {}
    caller_email = (claims.get("email") or "").lower()
    if not caller_email:
        return response(401, {"error": "Authentication required"})

    registration_id = event.get("pathParameters", {}).get("id")
    if not registration_id:
        return response(400, {"error": "id path parameter is required"})

    try:
        existing = registrations_table.get_item(Key={"registrationId": registration_id})
        item = existing.get("Item")
        if not item:
            return response(404, {"error": "Registration not found"})

        if item["email"].lower() != caller_email:
            return response(403, {"error": "Access denied"})

        try:
            # Conditional cancel: only flip to "cancelled" if it's still
            # "confirmed". A second DELETE for the same registration
            # (double-click, retry, replay) fails this condition instead
            # of silently double-decrementing the seat count.
            registrations_table.update_item(
                Key={"registrationId": registration_id},
                UpdateExpression="SET #s = :cancelled",
                ConditionExpression="#s = :confirmed",
                ExpressionAttributeNames={"#s": "status"},
                ExpressionAttributeValues={":cancelled": "cancelled", ":confirmed": "confirmed"},
            )
        except ClientError as e:
            if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
                return response(409, {"error": "Registration already cancelled"})
            raise

        # give the seat back — best-effort, not wrapped in the same
        # transaction as the status update above. Documented tradeoff:
        # see README for the promote-on-cancel / waitlist race notes.
        # Guard against going negative if this write ever runs twice.
        events_table.update_item(
            Key={"eventId": item["eventId"]},
            UpdateExpression="ADD registeredCount :dec",
            ConditionExpression="registeredCount > :zero",
            ExpressionAttributeValues={":dec": -1, ":zero": 0},
        )

        return response(200, {"registrationId": registration_id, "status": "cancelled"})
    except ClientError as e:
        print(f"ERROR cancelling {registration_id}: {str(e)}")
        return response(500, {"error": "Failed to cancel registration"})


# ---------- router ----------
def handler(event, context):
    method = event.get("httpMethod")

    if method == "POST":
        return register(event)
    elif method == "GET":
        return get_by_email(event)
    elif method == "DELETE":
        return cancel(event)
    elif method == "OPTIONS":
        # Browser CORS preflight — the response helper already carries the
        # Allow-Origin/Methods/Headers; nothing else to do here.
        return response(200, {})
    else:
        return response(405, {"error": f"Method {method} not allowed"})