"""
tests/test_events.py

Tests the Events Lambda against a FAKE DynamoDB table — moto intercepts
boto3 calls and simulates AWS entirely in-memory. No real AWS account
is touched, so this is safe to run in CI on every push.
"""

import json
import os
import boto3
import pytest
from moto import mock_aws
from conftest import load_handler


@pytest.fixture
def events_table():
    """Spins up a fake Events table for each test, torn down automatically after."""
    with mock_aws():
        os.environ["EVENTS_TABLE"] = "Events"
        client = boto3.client("dynamodb", region_name="us-east-1")
        client.create_table(
            TableName="Events",
            KeySchema=[{"AttributeName": "eventId", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "eventId", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        yield client


def test_status_available_when_low_registrations(events_table):
    table = boto3.resource("dynamodb", region_name="us-east-1").Table("Events")
    table.put_item(Item={"eventId": "e1", "eventName": "Test Event", "totalCapacity": 50, "registeredCount": 10})

    events_handler = load_handler("events")
    result = events_handler.handler({}, {})
    body = json.loads(result["body"])

    assert result["statusCode"] == 200
    assert body["events"][0]["status"] == "Available"


def test_status_limited_at_80_percent(events_table):
    table = boto3.resource("dynamodb", region_name="us-east-1").Table("Events")
    table.put_item(Item={"eventId": "e2", "eventName": "Almost Full", "totalCapacity": 10, "registeredCount": 8})

    events_handler = load_handler("events")
    result = events_handler.handler({}, {})
    body = json.loads(result["body"])

    assert body["events"][0]["status"] == "Limited"


def test_status_full_when_at_capacity(events_table):
    table = boto3.resource("dynamodb", region_name="us-east-1").Table("Events")
    table.put_item(Item={"eventId": "e3", "eventName": "Sold Out", "totalCapacity": 5, "registeredCount": 5})

    events_handler = load_handler("events")
    result = events_handler.handler({}, {})
    body = json.loads(result["body"])

    assert body["events"][0]["status"] == "Full"
