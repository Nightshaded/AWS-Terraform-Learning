import os
from datetime import datetime, timezone, timedelta

import boto3

iam = boto3.client("iam")
table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])

MELBOURNE = timezone(timedelta(hours=10))


def current_review_id():
    now = datetime.now(MELBOURNE)
    quarter = (now.month - 1) // 3 + 1
    return f"{now.year}-Q{quarter}"


def handler(event, context):
    review_id = (event or {}).get("review_id") or current_review_id()
    created_at = datetime.now(MELBOURNE).isoformat()
    users = []

    for page in iam.get_paginator("list_users").paginate():
        for user in page["Users"]:
            name = user["UserName"]

            attached = [
                p["PolicyName"]
                for p in iam.list_attached_user_policies(UserName=name)["AttachedPolicies"]
            ]
            inline = iam.list_user_policies(UserName=name)["PolicyNames"]
            groups = [
                g["GroupName"]
                for g in iam.list_groups_for_user(UserName=name)["Groups"]
            ]

            table.put_item(Item={
                "review_id": review_id,
                "user_name": name,
                "attached_policies": attached,
                "inline_policies": inline,
                "groups": groups,
                "decision": "PENDING",
                "created_at": created_at,
            })
            users.append(name)

    print(f"Review {review_id}: recorded {len(users)} users")
    return {"review_id": review_id, "user_count": len(users), "users": users}