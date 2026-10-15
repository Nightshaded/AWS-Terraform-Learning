import os
from datetime import datetime, timezone, timedelta

import boto3 # type:ignore 

iam = boto3.client("iam")
table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
TAG_KEY = os.environ["REVOKE_TAG_KEY"]
MELBOURNE = timezone(timedelta(hours=10))


def is_opted_in(user):
    tags = iam.list_user_tags(UserName=user)["Tags"]
    return any(t["Key"] == TAG_KEY and t["Value"].lower() == "true" for t in tags)


def handler(event, context):
    user = event["user_name"]
    review_id = event["review_id"]
    removed = []

    if not is_opted_in(user):
        status = "SKIPPED_NOT_TAGGED"
    else:
        for p in iam.list_attached_user_policies(UserName=user)["AttachedPolicies"]:
            iam.detach_user_policy(UserName=user, PolicyArn=p["PolicyArn"])
            removed.append(p["PolicyName"])

        for name in iam.list_user_policies(UserName=user)["PolicyNames"]:
            iam.delete_user_policy(UserName=user, PolicyName=name)
            removed.append(f"inline:{name}")

        for g in iam.list_groups_for_user(UserName=user)["Groups"]:
            iam.remove_user_from_group(GroupName=g["GroupName"], UserName=user)
            removed.append(f"group:{g['GroupName']}")

        status = "REVOKED_AUTOMATICALLY"

    table.update_item(
        Key={"review_id": review_id, "user_name": user},
        UpdateExpression="SET revoke_status = :s, revoked_items = :r, revoked_at = :t",
        ExpressionAttributeValues={
            ":s": status,
            ":r": removed,
            ":t": datetime.now(MELBOURNE).isoformat(),
        },
    )

    print(f"{user}: {status} {removed}")
    return {"user_name": user, "revoke_status": status, "removed": removed}