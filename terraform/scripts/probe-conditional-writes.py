#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["boto3"]
# ///
"""Probe whether Vultr Object Storage honors S3 conditional writes (If-None-Match: *).

WHY THIS EXISTS
---------------
OpenTofu's S3 backend gained native state locking in 1.10 via `use_lockfile = true`,
which writes a `<key>.tflock` object using an HTTP conditional write
(`If-None-Match: *`) to achieve atomic compare-and-swap locking — no DynamoDB
required. That guarantee only
holds if the object store actually *enforces* the conditional. On a store that ignores
`If-None-Match`, the second PutObject succeeds unconditionally: OpenTofu still prints
"Acquiring state lock" and creates the `.tflock`, but two runs can hold it at once —
FALSE SECURITY that is worse than no lock because it reads as protected.

Vultr Object Storage is Ceph RGW-based; Ceph added `If-None-Match: *` support in the
Squid release, and Vultr's published docs historically said it provides no locking — so
the only trustworthy answer is empirical. This script writes a throwaway object twice
with `If-None-Match: *`:

    - compliant store     -> HTTP 412 PreconditionFailed  (exit 0, WORKS)
    - non-compliant store -> HTTP 200  (exit 1, FALSE SECURITY)

It is kept (not throwaway) so it can be re-run later: if Vultr upgrades Ceph, re-running
this is how we'd know `use_lockfile` became real.

DESIGN NOTES
------------
- Credentials come from the environment (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY),
  populated by `mise` from 1Password — same creds the tofu S3 backend uses.
- Targets the live state bucket/endpoint so the test exercises the exact code path
  tofu would. The probe key is namespaced + deleted in a finally block; it never
  collides with a real `*.tfstate` object.
- Fails loudly: any unexpected ClientError is re-raised rather than swallowed.
"""

import sys

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

ENDPOINT = "https://sjc1.vultrobjects.com"
REGION = "us-west-1"
BUCKET = "frankenstructure"
KEY = "terraform/.conditional-write-probe"

s3 = boto3.client(
    "s3",
    endpoint_url=ENDPOINT,
    region_name=REGION,
    config=Config(s3={"addressing_style": "virtual"}),
)


def _clear() -> None:
    try:
        s3.delete_object(Bucket=BUCKET, Key=KEY)
    except ClientError:
        pass  # absent is fine — we only care that the slot is empty before the test


_clear()  # ensure a clean slot so the first conditional write is expected to succeed

# First write: object does not exist, so If-None-Match:* must succeed.
s3.put_object(Bucket=BUCKET, Key=KEY, Body=b"first", IfNoneMatch="*")

honors = False
try:
    # Second write: object now exists. A compliant store rejects with 412.
    s3.put_object(Bucket=BUCKET, Key=KEY, Body=b"second", IfNoneMatch="*")
    print("RESULT: DOES NOT honor conditional writes -> use_lockfile is FALSE SECURITY")
except ClientError as exc:
    status = exc.response["ResponseMetadata"]["HTTPStatusCode"]
    if status == 412:
        print("RESULT: HONORS conditional writes -> use_lockfile WORKS")
        honors = True
    else:
        _clear()
        raise  # unexpected failure — surface it, do not guess
finally:
    _clear()

sys.exit(0 if honors else 1)
