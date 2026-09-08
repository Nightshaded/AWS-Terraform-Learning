import os
import urllib.request
import urllib.error
import boto3

sns = boto3.client("sns")

SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
SITES = [s.strip() for s in os.environ.get("SITES", "").split(",") if s.strip()]
TIMEOUT = int(os.environ.get("TIMEOUT_SECONDS", "10"))


def check_site(url):
    """Return (is_up, detail). Any 2xx/3xx status counts as up."""
    req = urllib.request.Request(url, headers={"User-Agent": "aws-uptime-checker"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            code = resp.getcode()
            return (200 <= code < 400), f"HTTP {code}"
    except urllib.error.HTTPError as e:
        return False, f"HTTP {e.code}"
    except Exception as e:
        return False, f"{type(e).__name__}: {e}"


def lambda_handler(event, context):
    down = []
    for url in SITES:
        is_up, detail = check_site(url)
        print(f"{url} -> {'UP' if is_up else 'DOWN'} ({detail})")
        if not is_up:
            down.append(f"{url}  —  {detail}")

    if down:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject="🚨 Homelab Server Down",
            Message="Your homelab server might be down:\n\n" + "\n".join(down),
        )
    return {"checked": len(SITES), "down": len(down)}