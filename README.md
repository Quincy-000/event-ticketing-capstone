# Event Registration & Ticketing System

A fully serverless event registration and ticketing API on AWS that replaces a manual **Microsoft Forms + Excel** workflow with a scalable, race-safe REST API. Built as the final capstone for the **Azubi Africa AWS Cloud & AI Intensive Programme**.

> **Live API (dev stage):** `https://qhmocsswo9.execute-api.us-east-1.amazonaws.com/dev`
> *(yours will differ — grab it from `terraform output api_base_url` after deploy)*

---

## Table of Contents

1. [Problem Statement](#problem-statement)
2. [Features](#features)
3. [Architecture](#architecture)
4. [Tech Stack](#tech-stack)
5. [API Reference](#api-reference)
6. [Data Model](#data-model)
7. [Design Decisions](#design-decisions)
8. [Project Structure](#project-structure)
9. [Local Development](#local-development)
10. [Deployment](#deployment)
11. [CI/CD Pipeline](#cicd-pipeline)
12. [Monitoring & Alerts](#monitoring--alerts)
13. [Screenshots](#screenshots)
14. [Known Limitations](#known-limitations)
15. [Future Work](#future-work)

---

## Problem Statement

Organizers previously collected registrations through Microsoft Forms, then manually copied entries into Excel — a process prone to:

- **Double-bookings** — no automated check against capacity or duplicates
- **Overselling** — no live seat counter, so events could exceed capacity
- **Manual effort** — a human in the loop for every single registration and cancellation
- **No accountability** — no audit trail, no email, no real-time visibility

This project removes the human from the hot path: a machine books seats atomically, enforces capacity, dedupes requests, and exposes everything through a clean REST API.

## Features

- ✅ **Four REST endpoints** covering the full registration lifecycle
- ✅ **Real capacity control** — DynamoDB conditional writes, not a status badge (see [Design Decisions](#design-decisions))
- ✅ **Duplicate protection** — same email + event can't double-register
- ✅ **Safe cancellations** — double-cancel returns `409` and can never corrupt the seat count
- ✅ **Live status computation** — events report `Available` / `Limited` / `Full` based on real occupancy
- ✅ **Observability** — 5 CloudWatch alarms + a custom metric filter on failed registrations
- ✅ **Everything as code** — Terraform provisions the entire stack; GitHub Actions tests every push
- ✅ **Least-privilege IAM** — each Lambda can touch only what it needs

## Architecture

```mermaid
flowchart LR
    C[Client<br/>curl / browser] -->|HTTPS| A[API Gateway<br/>REST API v1 · dev stage]

    A -->|GET /events| LE[Lambda<br/>events-handler]
    A -->|POST /register| LR[Lambda<br/>registrations-handler]
    A -->|GET /registrations/{email}| LR
    A -->|DELETE /registration/{id}| LR

    LE -->|Scan| DE[(DynamoDB<br/>Events)]
    LR -->|Put / Query / Update| DR[(DynamoDB<br/>Registrations)]
    LR -->|UpdateItem · capacity| DE

    LE -.->|logs / metrics| CW[CloudWatch<br/>5 alarms + metric filter]
    LR -.->|REGISTRATION_FAILED| CW
    CW -->|alarm actions| S[SNS<br/>event-ticketing-alarms]

    TF[Terraform] -.->|provisions all infra| A
    GHA[GitHub Actions<br/>test + terraform-validate] -.->|on push / PR| A
```

> 📊 **Full-resolution diagram:** open [`docs/architecture-diagram.html`](docs/architecture-diagram.html) in a browser (dark-themed, screenshot-ready).
>
> 📸 **Screenshot placeholder:** *[insert: architecture diagram screenshot here]*

**Flow:** a client calls the API → API Gateway routes to the correct Lambda → the Lambda reads/writes DynamoDB with race-safe conditional operations → metrics and logs stream to CloudWatch, which alarms via SNS. Terraform declared the entire AWS footprint; GitHub Actions verifies every change.

## Tech Stack

| Layer | Technology |
|---|---|
| API layer | AWS API Gateway (REST API v1, `AWS_PROXY` integrations) |
| Compute | AWS Lambda (Python 3.12, zip-packaged) |
| Data | Amazon DynamoDB (on-demand, 2 tables + 1 GSI) |
| Observability | CloudWatch (logs, metrics, alarms, metric filter) + SNS |
| IaC | Terraform (AWS provider ~> 6.0, archive ~> 2.0) |
| CI/CD | GitHub Actions (pytest + terraform validate) |
| Tests | pytest + moto (offline AWS mocking) |

## API Reference

Base URL: `https://qhmocsswo9.execute-api.us-east-1.amazonaws.com/dev`

| Method | Path | Description | Success |
|---|---|---|---|
| `GET` | `/events` | List all events with computed status | `200` |
| `POST` | `/register` | Register for an event (body: `eventId`, `email`) | `201` |
| `GET` | `/registrations/{email}` | List a user's confirmed registrations | `200` |
| `DELETE` | `/registration/{id}` | Cancel a registration | `200` |

### Example calls

```bash
# List events
curl https://qhmocsswo9.execute-api.us-east-1.amazonaws.com/dev/events

# Register (201 → registration created)
curl -X POST https://qhmocsswo9.execute-api.us-east-1.amazonaws.com/dev/register \
  -H "Content-Type: application/json" \
  -d '{"eventId": "763b03aa-c8ee-45ab-81bd-b3709e0cf953", "email": "you@example.com"}'

# Look up your registrations
curl https://qhmocsswo9.execute-api.us-east-1.amazonaws.com/dev/registrations/you@example.com

# Cancel (second call returns 409 "already cancelled")
curl -X DELETE https://qhmocsswo9.execute-api.us-east-1.amazonaws.com/dev/registration/<registrationId>
```

### Error responses

| Code | Meaning |
|---|---|
| `400` | Missing/invalid fields (`eventId`, `email` required; `@` must be present) |
| `409` | Event is full / already registered / already cancelled |
| `404` | Registration not found |
| `405` | Unsupported HTTP method |
| `500` | Server-side failure |

## Data Model

### `Events` table

| Attribute | Type | Notes |
|---|---|---|
| `eventId` | String | **Partition key** (HASH) |
| `eventName` | String | Display name |
| `eventDate` | String | ISO date |
| `totalCapacity` | Number | Max seats |
| `registeredCount` | Number | Live seat counter (atomic) |

### `Registrations` table

| Attribute | Type | Notes |
|---|---|---|
| `registrationId` | String | **Partition key** (HASH) |
| `eventId` | String | References an event |
| `email` | String | Attendee — GSI `email-index` (HASH) |
| `status` | String | `confirmed` \| `cancelled` |
| `registeredAt` | String | ISO timestamp |

The `email-index` GSI powers `GET /registrations/{email}` and the duplicate check.

## Design Decisions

### 1. Real capacity control with conditional writes (the differentiator)
Many capstones fake capacity with a status badge. Here, `POST /register` runs a **conditional `UpdateItem`**: `ADD registeredCount :inc WHERE registeredCount < totalCapacity`. DynamoDB evaluates the condition **atomically at commit time** — two simultaneous requests for the last seat: exactly one succeeds, the other gets `409 Event is full`. There is no check-then-act window.

### 2. Why no VPC?
Everything the Lambdas talk to (DynamoDB, API Gateway) is a **managed service** reachable over AWS's network — nothing lives in a private subnet. Attaching a VPC would add NAT-gateway cost, cold-start latency, and ENI complexity for **zero security benefit**. Serverless means exactly this: no VPC, no servers, no patching.

### 3. Double-cancel safety (two layers)
- **Primary guard:** cancel flips `status` with a condition (`#s = :confirmed`) — a second DELETE fails the condition → `409`.
- **Defense in depth:** the seat decrement itself requires `registeredCount > 0`, so the counter can never go negative even in a corrupted state.

### 4. Duplicate registration (documented residual race)
Registration checks the `email-index` for an existing `confirmed` row for the same event → `409`. This is a **check-then-act read**, not atomic — a genuinely simultaneous double-submit could both slip through. Fully fixing it needs a composite-key conditional `put_item`, accepted as out of scope (see [Limitations](#known-limitations)). Crucially, the check only blocks `confirmed` rows, so a **cancelled** registration can be re-booked.

### 5. Confirmed-only reads
`GET /registrations/{email}` filters to `status = confirmed` — cancelled registrations disappear from listings but remain re-bookable. Readers see live data; writers can reuse freed seats.

### 6. REST API v1 (not HTTP API)
Matches the brief's "REST endpoints" wording and the classic architecture diagram; HTTP API v2 would be the modern leaner choice if built again.

### 7. Least-privilege IAM
Verified against the *actual* deployed policies: `events-handler` has `Scan` on Events only; `registrations-handler` has scoped `Put/Get/Update/Query` on Registrations + index, and `UpdateItem` only on Events (for the seat counter).

## Project Structure

```
event-ticketing-capstone/
├── .github/workflows/
│   └── ci.yml                    # pytest + terraform validate on push/PR
├── lambdas/
│   ├── events/
│   │   └── handler.py            # GET /events — list + status computation
│   └── registrations/
│       └── handler.py            # register / list / cancel + router
├── modules/
│   ├── dynamodb/                 # reusable table module (tables + GSI)
│   └── lambda/                   # reusable function module (zip, role, policy)
├── tests/
│   ├── conftest.py               # handler loader (both handlers named handler.py)
│   ├── test_events.py            # 3 tests — status computation
│   └── test_registrations.py     # 5 tests — register/cancel/dedupe/GET filter
├── docs/
│   └── architecture-diagram.html # full-resolution architecture visual
├── cloudwatch.tf                 # alarms, metric filter, SNS
├── main.tf                       # tables, lambdas, API Gateway, outputs
├── seed.py                       # populate Events with sample data
├── versions.tf                   # provider constraints
└── README.md
```

## Local Development

### Prerequisites
- Python 3.12, Terraform ≥ 1.x, AWS CLI (configured credentials)
- `boto3`, `moto`, `pytest`

### Isolated environment (WSL-safe)

```bash
cd event-ticketing-capstone
python3 -m venv venv          # create the isolated env
source venv/bin/activate      # activate it (do this every session)
which python                  # verify → .../event-ticketing-capstone/venv/bin/python
pip install boto3 moto pytest
```

> ⚠️ The venv lives *inside* the repo (and is gitignored) — your system Python is never touched.

### Run the tests

```bash
python -m pytest tests -q     # expect: 8 passed
```

The suite uses **moto** to mock DynamoDB — no AWS account is touched. CI sets `AWS_DEFAULT_REGION=us-east-1` because boto3 requires a region even under mock (see the CI story below).

### Seed sample data (after deploy)

```bash
python seed.py                # populates the Events table, incl. a capacity-1 demo event
```

## Deployment

```bash
terraform init                # downloads providers (once)
terraform plan                # review the changes
terraform apply               # provisions everything
terraform output api_base_url # your live API URL
```

Then seed the data and hit the endpoints (see [API Reference](#api-reference)).

## CI/CD Pipeline

`.github/workflows/ci.yml` runs **two parallel jobs on every push/PR to `main`**:

| Job | Steps | Purpose |
|---|---|---|
| `test` | checkout → setup-python 3.12 → `pip install boto3 moto pytest` → `pytest` | Prove the Lambdas work |
| `terraform-validate` | checkout → setup-terraform → `init -backend=false` → `validate` | Prove the IaC is sound |

**Real story:** the first CI runs failed — the Node 20 actions were forced onto Node 24 by GitHub (fixed by bumping to checkout v7 / setup-python v7 / terraform v4), then all 8 tests failed with `NoRegionError` because the tests relied on a local `~/.aws/config` that runners don't have. Fix: `AWS_DEFAULT_REGION: us-east-1` in the job env. **CI caught a real environment bug the day it went live — exactly what it's for.**

## Monitoring & Alerts

| Alarm | Metric | Condition |
|---|---|---|
| `*-errors` (×2) | `AWS/Lambda` Errors | `> 0` in 1 min |
| `*-throttles` (×2) | `AWS/Lambda` Throttles | `> 0` in 1 min |
| `registrations-handler-registration-failed` | `EventTicketing/RegistrationFailedCount` (custom metric filter on the `REGISTRATION_FAILED` log line) | `≥ 3` in 5 min |

All alarms publish to SNS topic `event-ticketing-alarms`.

## Screenshots

*(insert screenshots here — suggested set)*

- 📸 **Screenshot:** *[API Gateway console — routes]*
- 📸 **Screenshot:** *[Lambda console — both functions, env vars, IAM roles]*
- 📸 **Screenshot:** *[DynamoDB console — Events & Registrations tables]*
- 📸 **Screenshot:** *[Live curl output — register → 201, double-cancel → 409]*
- 📸 **Screenshot:** *[CloudWatch console — 5 alarms in OK state]*
- 📸 **Screenshot:** *[GitHub Actions — green run, both jobs]*
- 📸 **Screenshot:** *[terraform apply output — resources added]*

## Known Limitations

- **Dedupe residual race** — duplicate check is read-then-write; a perfectly simultaneous double-submit can both succeed (fix: composite-key conditional `put_item`).
- **SNS has no subscription yet** — alarms currently publish to a topic nobody reads; add an email subscription before production use.
- **API Gateway `source_arn` wildcard** — Lambda permissions allow any stage/method; harmless at this scale, tightenable per-route.
- **Unpinned CI dependencies** — `pip install boto3 moto pytest` pulls latest; a future moto release could break CI (fix: `requirements-dev.txt`).
- **Terraform deprecation warnings** — `hash_key`/`range_key` in the DynamoDB module are deprecated in favor of `key_schema` (cosmetic).
- **Cancel is not transactional** — status flip and seat decrement are two writes; the conditional guards prevent corruption, but a crash between them could theoretically leave a seat unreleased.

## Future Work

- [ ] Email confirmation on registration (SNS → SES)
- [ ] Waitlist / promote-on-cancel logic
- [ ] Frontend (static S3 site calling the API) — CORS `OPTIONS` handling required
- [ ] API keys / usage plans for public access
- [ ] Remote Terraform state (S3 backend + DynamoDB locking)
- [ ] Per-route Lambda permission scoping
- [ ] CloudFront in front of the API for global edge caching

---

*Capstone for the Azubi Africa AWS Cloud & AI Intensive Programme · built with Terraform, Python, and GitHub Actions · repo: [github.com/Quincy-000/event-ticketing-capstone](https://github.com/Quincy-000/event-ticketing-capstone)*
