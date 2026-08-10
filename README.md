# Event Registration & Ticketing System

A fully serverless event registration API on AWS (API Gateway → Lambda → DynamoDB) that replaces a manual Forms + Excel workflow with a scalable, race-safe REST API. Infrastructure is defined with Terraform and verified by a GitHub Actions CI pipeline.

**Live API (dev stage):** `https://qhmocsswo9.execute-api.us-east-1.amazonaws.com/dev` *(yours will differ — see `terraform output api_base_url`)*
**Live frontend:** `http://event-ticketing-frontend-quincy-000.s3-website-us-east-1.amazonaws.com` *(static S3 site calling the API — see `terraform output frontend_url`)*

---

## Architecture

 <img width="900" alt="image" src="https://github.com/user-attachments/assets/af849531-86d4-4817-a9ec-facbb7e06ce0" />



## Tech Stack

| Layer | Technology |
|---|---|
| API | AWS API Gateway (REST v1, `AWS_PROXY` integrations) |
| Compute | AWS Lambda (Python 3.12) |
| Data | DynamoDB (on-demand, 2 tables + 1 GSI) |
| Observability | CloudWatch (alarms, metric filter) + SNS |
| Cost tracking | AWS Budgets ($10/mo — forecast + actual alerts) |
| IaC | Terraform (AWS ~> 6.0, archive ~> 2.0) |
| CI/CD | GitHub Actions (pytest + terraform validate) |
| Tests | pytest + moto (offline AWS mocking) |

## API Reference

| Method | Path | Description | Success |
|---|---|---|---|
| `GET` | `/events` | List events with computed status | `200` |
| `POST` | `/register` | Register (body: `eventId`, `email`) | `201` |
| `GET` | `/registrations/{email}` | User's confirmed registrations | `200` |
| `DELETE` | `/registration/{id}` | Cancel a registration | `200` |

```bash
BASE=https://qhmocsswo9.execute-api.us-east-1.amazonaws.com/dev

curl $BASE/events
curl -X POST $BASE/register -H "Content-Type: application/json" \
  -d '{"eventId": "<eventId>", "email": "you@example.com"}'
curl $BASE/registrations/you@example.com
curl -X DELETE $BASE/registration/<registrationId>
```

Errors: `400` invalid input · `409` full/duplicate/already-cancelled · `404` not found · `405` bad method · `500` server error.

## Data Model

**Events** — `eventId` (PK) · `eventName` · `eventDate` · `totalCapacity` · `registeredCount`
**Registrations** — `registrationId` (PK) · `eventId` · `email` · `status` (`confirmed`/`cancelled`) · `registeredAt` · GSI `email-index`

## Key Design Decisions

- **Real capacity control** — `registeredCount` is incremented with a conditional write (`registeredCount < totalCapacity`), evaluated atomically by DynamoDB at commit time. Two simultaneous requests for the last seat: exactly one wins. Not a status badge.
- **No VPC** — every dependency (DynamoDB, API Gateway) is a managed service; a VPC would add cost and latency with zero security benefit.
- **Race-safe cancellation** — status flip is conditional (`confirmed` → `cancelled`), and the seat decrement requires `registeredCount > 0` — double-cancels return `409` and the counter can never underflow.
- **Dedupe** — same email + event can't hold two confirmed registrations; cancelled seats remain re-bookable.
- **Confirmed-only reads** — `GET /registrations/{email}` filters out cancelled rows.
- **Least-privilege IAM** — each Lambda's policy is scoped to exactly the tables/actions it uses.
- **REST API v1** — matches the brief's "REST endpoints" requirement.
- **Cost tracking** — AWS Budgets caps spend at $10/month with a forecast alert at 80% and an actual alert at 100%; live forecast for this stack is ~$0.79/month.

## Project Structure

```
├── .github/workflows/ci.yml    # pytest + terraform validate on push/PR
├── lambdas/
│   ├── events/handler.py       # GET /events
│   └── registrations/handler.py # register / list / cancel
├── modules/                    # reusable dynamodb + lambda modules
├── tests/                      # 10 tests (pytest + moto)
├── docs/architecture-diagram.html
├── budgets.tf · cloudwatch.tf · main.tf · versions.tf
├── seed.py                     # sample event data
└── README.md
```

## Local Development

```bash
python3 -m venv venv && source venv/bin/activate
pip install boto3 moto pytest
python -m pytest tests -q        # 10 passed (mocked AWS — no account needed)
```

## Deployment

```bash
terraform init && terraform apply   # provisions everything
terraform output api_base_url       # live URL
python seed.py                      # populate Events (incl. capacity-1 demo event)
```

## CI/CD

On every push/PR to `main`: **`test`** job runs the pytest suite (with `AWS_DEFAULT_REGION=us-east-1`), **`terraform-validate`** job runs `init -backend=false` + `validate`.

## Monitoring

5 CloudWatch alarms: Lambda `Errors` and `Throttles` (`> 0`) for both functions, plus a custom `REGISTRATION_FAILED` metric filter alarm (`≥ 3` in 5 min). All publish to SNS `event-ticketing-alarms` (email subscription; confirm via the link AWS emails you after deploy).

Failed registrations are returned to the client immediately with a specific error (`400` validation · `409` full/duplicate · `500` failure) and displayed in the frontend UI. The `REGISTRATION_FAILED` alarm is a **pattern detector for operators** — it fires when 3+ capacity rejections occur within 5 minutes, surfacing capacity pressure or systemic failures rather than individual user rejections (which are expected business outcomes the client sees and resolves themselves).

**Cost guardrail:** AWS Budgets caps monthly spend at $10 with alerts at 80% (forecast) and 100% (actual) — email to the same address.

## Screenshots

<img width="1169" height="389" alt="image" src="https://github.com/user-attachments/assets/3a352363-3968-4c68-8d8f-051a716407c4" />
<img width="1365" height="309" alt="image" src="https://github.com/user-attachments/assets/2af7e926-b455-47fe-b82d-ad5821e73894" />
<img width="1126" height="555" alt="image" src="https://github.com/user-attachments/assets/94d72c43-002b-4a13-8006-01a17db69a45" />
<img width="1365" height="386" alt="image" src="https://github.com/user-attachments/assets/ef298fe9-1ddf-4a06-9ff8-c84bb35dcb5f" />
<img width="1041" height="617" alt="image" src="https://github.com/user-attachments/assets/9dc77d1f-33e4-4db8-b571-422abea718fe" />
<img width="1357" height="570" alt="image" src="https://github.com/user-attachments/assets/6dea468e-345e-4dc6-addb-edde63b3fac2" />
<img width="1365" height="652" alt="image" src="https://github.com/user-attachments/assets/c8dd1598-0ba0-483f-b9e9-9c77f803615d" />
<img width="1352" height="639" alt="image" src="https://github.com/user-attachments/assets/dd0f44b9-2992-4a0f-a3bd-9eee09675ff7" />
<img width="1365" height="288" alt="image" src="https://github.com/user-attachments/assets/b1cbccfd-902d-43bb-a50a-7e28c04e7cb4" />
<img width="1038" height="705" alt="image" src="https://github.com/user-attachments/assets/4a6c99a0-95ce-441c-bd5d-de09e361af95" />
<img width="1361" height="621" alt="image" src="https://github.com/user-attachments/assets/b5bb0df7-2f4a-486a-9434-f8f72eb5e6b8" />












*(insert screenshots — suggested: API Gateway routes · Lambda config · DynamoDB tables · live curl output · CloudWatch alarms · CI green run · terraform apply)*
