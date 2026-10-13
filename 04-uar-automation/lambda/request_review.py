import os
from urllib.parse import urlencode

import boto3

sns = boto3.client("sns")
table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
TOPIC_ARN = os.environ["TOPIC_ARN"]
DECISION_URL = os.environ["DECISION_URL"].rstrip("/")


def handler(event, context):
    user = event["user_name"]
    review_id = event["review_id"]
    token = event["task_token"]

    item = table.get_item(Key={"review_id": review_id, "user_name": user}).get("Item", {})
    policies = ", ".join(item.get("attached_policies", [])) or "None"
    inline = ", ".join(item.get("inline_policies", [])) or "None"
    groups = ", ".join(item.get("groups", [])) or "None"

    def link(decision):
        query = urlencode({
            "review_id": review_id,
            "user": user,
            "decision": decision,
            "token": token,
        })
        return f"{DECISION_URL}/?{query}"

    message = (
        f"User Access Review {review_id}\n\n"
        f"User:              {user}\n"
        f"Attached policies: {policies}\n"
        f"Inline policies:   {inline}\n"
        f"Groups:            {groups}\n\n"
        f"Does this user still need this access?\n\n"
        f"KEEP access:\n{link('APPROVED')}\n\n"
        f"REVOKE access:\n{link('REVOKED')}\n"
    )

    sns.publish(
        TopicArn=TOPIC_ARN,
        Subject=f"Access review {review_id}: {user}"[:100],
        Message=message,
    )
    return {"status": "sent", "user_name": user}