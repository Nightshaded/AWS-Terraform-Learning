import html
import json
import os
from datetime import datetime, timezone, timedelta
from urllib.parse import parse_qs

import boto3

sfn = boto3.client("stepfunctions")
table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
MELBOURNE = timezone(timedelta(hours=10))
VALID_DECISIONS = {"APPROVED", "REVOKED"}


def page(status, title, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "text/html"},
        "body": (
            "<html><body style='font-family:sans-serif;margin:40px'>"
            f"<h2>{html.escape(title)}</h2><p>{html.escape(body)}</p>"
            "</body></html>"
        ),
    }


def handler(event, context):
    params = {k: v[0] for k, v in parse_qs(event.get("rawQueryString", "")).items()}
    review_id = params.get("review_id")
    user = params.get("user")
    token = params.get("token")
    decision = (params.get("decision") or "").upper()

    if not (review_id and user and token) or decision not in VALID_DECISIONS:
        return page(400, "Invalid link", "This review link is incomplete or invalid.")

    try:
        sfn.send_task_success(
            taskToken=token,
            output=json.dumps({"user_name": user, "decision": decision}),
        )
    except (sfn.exceptions.TaskTimedOut,
            sfn.exceptions.TaskDoesNotExist,
            sfn.exceptions.InvalidToken):
        return page(410, "Link no longer valid",
                    "This review has already been answered or has expired.")

    table.update_item(
        Key={"review_id": review_id, "user_name": user},
        UpdateExpression="SET decision = :d, decided_at = :t",
        ExpressionAttributeValues={
            ":d": decision,
            ":t": datetime.now(MELBOURNE).isoformat(),
        },
    )

    return page(200, "Decision recorded",
                f"{user} has been marked as {decision} for review {review_id}.")