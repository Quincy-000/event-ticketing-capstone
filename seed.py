"""
seed.py — populates the Events table with sample data.

Run this AFTER `terraform apply` has created the tables.
Requires: pip install boto3
Uses whatever AWS credentials/region your CLI is already configured with
(same terraform-admin-user setup you use for everything else).
"""

import boto3
import uuid

# ---- config ----
TABLE_NAME = "Events"
REGION = "us-east-1"  # change if your tables were created in a different region

dynamodb = boto3.resource("dynamodb", region_name=REGION)
table = dynamodb.Table(TABLE_NAME)

# ---- sample events ----
# Note the last one: totalCapacity=1, registeredCount=0.
# This is the event you fire two simultaneous /register requests at
# during your live demo to prove the conditional write actually works.
events = [
    {
        "eventId": str(uuid.uuid4()),
        "eventName": "AWS Workshop Accra 2026",
        "eventDate": "2026-05-15",
        "totalCapacity": 50,
        "registeredCount": 0,
    },
    {
        "eventId": str(uuid.uuid4()),
        "eventName": "Cloud Solutions Summit",
        "eventDate": "2026-06-28",
        "totalCapacity": 30,
        "registeredCount": 27,  # pre-seeded near-full, so it shows "Limited" immediately
    },
    {
        "eventId": str(uuid.uuid4()),
        "eventName": "DevOps Deep Dive Accra",
        "eventDate": "2026-07-10",
        "totalCapacity": 40,
        "registeredCount": 0,
    },
    {
        "eventId": str(uuid.uuid4()),
        "eventName": "Race Condition Demo Event",
        "eventDate": "2026-08-20",
        "totalCapacity": 1,
        "registeredCount": 0,
    },
]

def seed():
    for event in events:
        table.put_item(Item=event)
        print(f"Seeded: {event['eventName']} (eventId={event['eventId']})")
    print(f"\nDone — {len(events)} events written to {TABLE_NAME}.")

if __name__ == "__main__":
    seed()