"""
tests/test_registrations.py

Tests the Registrations Lambda against fake DynamoDB tables via moto.
No real AWS account is touched.
"""

import json
import os
import boto3
import pytest
from moto import mock_aws
from conftest import load_handler


@pytest.fixture
def tables():
    with mock_aws():
        os.environ["EVENTS_TABLE"] = "Events"
        os.environ["REGISTRATIONS_TABLE"] = "Registrations"

        ddb = boto3.resource("dynamodb", region_name="us-east-1")

        ddb.create_table(
            TableName="Events",
            KeySchema=[{"AttributeName": "eventId", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "eventId", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )

        ddb.create_table(
            TableName="Registrations",
            KeySchema=[{"AttributeName": "registrationId", "KeyType": "HASH"}],
            AttributeDefinitions=[
                {"AttributeName": "registrationId", "AttributeType": "S"},
                {"AttributeName": "email", "AttributeType": "S"},
            ],
            GlobalSecondaryIndexes=[{
                "IndexName": "email-index",
                "KeySchema": [{"AttributeName": "email", "KeyType": "HASH"}],
                "Projection": {"ProjectionType": "ALL"},
            }],
            BillingMode="PAY_PER_REQUEST",
        )

        yield ddb


def _post(handler, event_id, email):
    return handler.handler({
        "httpMethod": "POST",
        "body": json.dumps({"eventId": event_id, "email": email}),
    }, {})


def _delete(handler, registration_id):
    return handler.handler({
        "httpMethod": "DELETE",
        "pathParameters": {"id": registration_id},
    }, {})


def test_register_happy_path(tables):
    tables.Table("Events").put_item(Item={
        "eventId": "e1", "totalCapacity": 10, "registeredCount": 0,
    })

    h = load_handler("registrations")
    result = _post(h, "e1", "user@example.com")
    body = json.loads(result["body"])

    assert result["statusCode"] == 201
    assert body["status"] == "confirmed"
    assert "registrationId" in body

    count = tables.Table("Events").get_item(Key={"eventId": "e1"})["Item"]["registeredCount"]
    assert count == 1

    reg = tables.Table("Registrations").get_item(
        Key={"registrationId": body["registrationId"]}
    )["Item"]
    assert reg["status"] == "confirmed"


def test_register_full_event_returns_409_and_logs(tables, capsys):
    tables.Table("Events").put_item(Item={
        "eventId": "e2", "totalCapacity": 1, "registeredCount": 1,
    })

    h = load_handler("registrations")
    result = _post(h, "e2", "user@example.com")
    body = json.loads(result["body"])

    assert result["statusCode"] == 409
    assert "full" in body["error"].lower()
    assert "REGISTRATION_FAILED" in capsys.readouterr().out


def test_register_duplicate_confirmed_returns_409(tables):
    tables.Table("Events").put_item(Item={
        "eventId": "e3", "totalCapacity": 10, "registeredCount": 1,
    })
    tables.Table("Registrations").put_item(Item={
        "registrationId": "existing-id",
        "eventId": "e3",
        "email": "dup@example.com",
        "status": "confirmed",
    })

    h = load_handler("registrations")
    result = _post(h, "e3", "dup@example.com")
    body = json.loads(result["body"])

    assert result["statusCode"] == 409
    assert "already registered" in body["error"].lower()


def test_get_by_email_excludes_cancelled(tables):
    tables.Table("Events").put_item(Item={
        "eventId": "e5", "totalCapacity": 10, "registeredCount": 1,
    })
    tables.Table("Registrations").put_item(Item={
        "registrationId": "reg-confirmed", "eventId": "e5",
        "email": "mixed@example.com", "status": "confirmed",
    })
    tables.Table("Registrations").put_item(Item={
        "registrationId": "reg-cancelled", "eventId": "e5",
        "email": "mixed@example.com", "status": "cancelled",
    })

    h = load_handler("registrations")
    result = h.handler({
        "httpMethod": "GET",
        "pathParameters": {"email": "mixed@example.com"},
    }, {})

    assert result["statusCode"] == 200
    regs = json.loads(result["body"])["registrations"]
    assert len(regs) == 1
    assert regs[0]["registrationId"] == "reg-confirmed"


def test_double_cancel(tables):
    tables.Table("Events").put_item(Item={
        "eventId": "e4", "totalCapacity": 10, "registeredCount": 1,
    })
    tables.Table("Registrations").put_item(Item={
        "registrationId": "reg-abc",
        "eventId": "e4",
        "email": "cancel@example.com",
        "status": "confirmed",
    })

    h = load_handler("registrations")

    first = _delete(h, "reg-abc")
    assert first["statusCode"] == 200

    second = _delete(h, "reg-abc")
    assert second["statusCode"] == 409
    assert "already cancelled" in json.loads(second["body"])["error"].lower()

    count = tables.Table("Events").get_item(Key={"eventId": "e4"})["Item"]["registeredCount"]
    assert count == 0  # decremented once, not twice


def test_options_preflight_returns_cors_headers(tables):
    """Browser CORS preflight must succeed with the right headers."""
    h = load_handler("registrations")
    result = h.handler({"httpMethod": "OPTIONS"}, {})

    assert result["statusCode"] == 200
    assert result["headers"]["Access-Control-Allow-Origin"] == "*"
    assert "POST" in result["headers"]["Access-Control-Allow-Methods"]
    assert "DELETE" in result["headers"]["Access-Control-Allow-Methods"]
    assert "Content-Type" in result["headers"]["Access-Control-Allow-Headers"]


def test_get_by_email_handles_percent_encoded_email(tables):
    """API Gateway v1 passes %40 literally — the handler must decode it."""
    tables.Table("Events").put_item(Item={
        "eventId": "e6", "totalCapacity": 10, "registeredCount": 1,
    })
    tables.Table("Registrations").put_item(Item={
        "registrationId": "reg-enc", "eventId": "e6",
        "email": "encoded@example.com", "status": "confirmed",
    })

    h = load_handler("registrations")
    result = h.handler({
        "httpMethod": "GET",
        "pathParameters": {"email": "encoded%40example.com"},
    }, {})

    assert result["statusCode"] == 200
    regs = json.loads(result["body"])["registrations"]
    assert len(regs) == 1
    assert regs[0]["registrationId"] == "reg-enc"
