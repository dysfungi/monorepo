"""Dispatcher mode: find failing Renovate PRs and fan out triage Jobs.

Intent
------
Run as a Kubernetes CronJob. Discover OPEN Renovate PRs whose CI is RED and that
have not yet been triaged, then create one ephemeral k8s Job per PR (bounded by a
concurrency cap) to triage each in isolation.

Architecture
------------
1. Kill switch: if ``FRANKENBOT_ENABLED`` is false, log and exit 0 immediately.
2. Load ``Settings`` + ``repos.yaml``; mint a GitHub App installation token.
3. Per enabled repo: list OPEN PRs labeled ``frankenbot`` (Renovate PRs carry
   it); keep those whose head-SHA has >=1 failed/timed_out check-run AND that
   lack the ``triaged`` label.
4. Compute available slots = ``max_concurrent_jobs`` - active frankenbot Jobs in
   the namespace, and create up to that many triage Jobs.

Design decisions
----------------
- Errors are aggregated across repos: one repo's API failure does not abort the
  others, but the process exits non-zero if any repo failed (fail loud, but keep
  making progress).
- Job names are DNS-1123-safe: ``monster-<repo-slug>-triage-pr<N>`` truncated and
  hash-suffixed when necessary.
- Triage Jobs are pinned to the infrastructure node pool via REQUIRED
  nodeAffinity, and carry NO CPU limit (memory limit only) to avoid CFS
  throttling of the agent's bursty CLI workload.
"""

from __future__ import annotations

import hashlib
import logging
import os

from kubernetes import client as k8s_client
from kubernetes import config as k8s_config
from kubernetes.client.rest import ApiException

from frankenbot import githubapp, state
from frankenbot.config import (
    LABEL_FRANKENBOT,
    LABEL_TRIAGED,
    RepoConfig,
    Settings,
    load_settings,
)
from frankenbot.otel import maybe_span

log = logging.getLogger("frankenbot.dispatch")

# check-run conclusions that we treat as "CI is red" and worth triaging.
_FAILING_CONCLUSIONS = {"failure", "timed_out", "startup_failure", "action_required"}

# k8s object-name length ceiling (DNS-1123 label max is 63; Jobs allow 63).
_MAX_NAME_LEN = 63

# Label applied to spawned Jobs so we can count "active frankenbot Jobs".
_JOB_MANAGED_BY = "frankenbot"

# work_state status recorded when the dispatcher spawns a triage Job.
_STATUS_DISPATCHED = "dispatched"


def _db_enabled() -> bool:
    """Postgres state is active iff DATABASE_URL is set.

    The frankenbot-db Secret (dispatcher-only) provides it in cluster. When
    absent the dispatcher keeps its original PR-label-only dedup behavior — the
    MVP-safe fallback so a DB outage or a DB-less deploy degrades gracefully
    rather than failing.
    """
    return bool(os.environ.get("DATABASE_URL"))


def run() -> int:
    """Entry point for ``frankenbot dispatch``. Returns a process exit code."""
    settings = load_settings_or_killswitch()
    if settings is None:
        return 0  # disabled; kill switch already logged.

    with maybe_span(
        "frankenbot.dispatch", **{"frankenbot.namespace": settings.namespace}
    ):
        return _dispatch(settings)


def load_settings_or_killswitch() -> Settings | None:
    """Load settings, honoring the kill switch BEFORE any heavier work.

    Returns None (and logs) when disabled, so the caller exits 0.
    """
    settings = load_settings()
    if not settings.enabled:
        log.info("frankenbot is disabled via FRANKENBOT_ENABLED; exiting cleanly.")
        return None
    return settings


def _dispatch(settings: Settings) -> int:
    # discovery=auto is dormant scaffolding (see frankenbot.discovery). Fail LOUD
    # rather than silently ignore the setting and scan only the explicit list —
    # a silent no-op would hide a misconfiguration.
    # TODO (Phase 5): wire live installation-repo discovery here.
    if settings.discovery_is_auto():
        raise NotImplementedError(
            "discovery=auto not wired yet; set discovery=off / list repos explicitly"
        )

    token = githubapp.mint_installation_token().token

    k8s_config.load_incluster_config()
    batch_api = k8s_client.BatchV1Api()

    active = _count_active_jobs(batch_api, settings.namespace)
    available_slots = max(0, settings.max_concurrent_jobs - active)
    log.info(
        "dispatch starting",
        extra={"fb_active_jobs": active, "fb_available_slots": available_slots},
    )

    if available_slots == 0:
        log.info("no available slots; concurrency cap reached.")
        return 0

    had_error = False
    created = 0

    with githubapp.GitHubClient(token) as gh:
        for repo in settings.enabled_repos():
            if created >= available_slots:
                log.info("reached available slot budget; stopping dispatch.")
                break
            try:
                created += _dispatch_repo(
                    gh=gh,
                    batch_api=batch_api,
                    settings=settings,
                    repo=repo,
                    remaining_slots=available_slots - created,
                )
            except Exception:  # noqa: BLE001 - aggregate, keep going across repos
                had_error = True
                log.exception("dispatch failed for repo", extra={"fb_repo": repo.name})

    log.info("dispatch complete", extra={"fb_jobs_created": created})
    return 1 if had_error else 0


def _dispatch_repo(
    *,
    gh: githubapp.GitHubClient,
    batch_api: "k8s_client.BatchV1Api",
    settings: Settings,
    repo: RepoConfig,
    remaining_slots: int,
) -> int:
    """Dispatch triage Jobs for a single repo. Returns the number created."""
    pulls = gh.list_open_pulls(repo.name, label=LABEL_FRANKENBOT)
    candidates = [p for p in pulls if _is_triage_candidate(gh, repo.name, p)]
    log.info(
        "repo scanned",
        extra={
            "fb_repo": repo.name,
            "fb_open_frankenbot_prs": len(pulls),
            "fb_candidates": len(candidates),
        },
    )

    db_enabled = _db_enabled()
    created = 0
    for pull in candidates:
        if created >= remaining_slots:
            break
        pr_number = int(pull["number"])

        # Cross-run dedup key: the head ref (Renovate names one branch per
        # dependency-update stream) is the "surface"; the head SHA makes the
        # fingerprint change when new commits land (so a re-pushed PR is
        # re-triaged, but an unchanged one is not re-dispatched every tick).
        surface = pull.get("head", {}).get("ref") or f"pr{pr_number}"
        head_sha = pull.get("head", {}).get("sha") or ""
        content_fp = state.fingerprint(repo=repo.name, surface=surface, sha=head_sha)

        if db_enabled and state.already_done(repo.name, surface, content_fp):
            log.info(
                "skip: content already dispatched (db dedup)",
                extra={"fb_repo": repo.name, "fb_pr": pr_number, "fb_surface": surface},
            )
            continue

        job_name = _job_name(repo, pr_number)
        try:
            _create_triage_job(batch_api, settings, repo.name, pr_number, job_name)
            created += 1
            if db_enabled:
                state.record_run(
                    repo.name, surface, pr_number, _STATUS_DISPATCHED, content_fp, None
                )
            log.info(
                "triage job created",
                extra={"fb_repo": repo.name, "fb_pr": pr_number, "fb_job": job_name},
            )
        except ApiException as exc:
            if exc.status == 409:
                # Already exists (idempotent re-run within TTL window) — skip.
                log.info(
                    "triage job already exists; skipping",
                    extra={
                        "fb_repo": repo.name,
                        "fb_pr": pr_number,
                        "fb_job": job_name,
                    },
                )
                continue
            raise
    return created


def _is_triage_candidate(gh: githubapp.GitHubClient, repo: str, pull: dict) -> bool:
    """A PR is a candidate when it is red-CI and not yet labeled ``triaged``."""
    labels = {lbl.get("name") for lbl in pull.get("labels", [])}
    if LABEL_TRIAGED in labels:
        return False

    head_sha = pull.get("head", {}).get("sha")
    if not head_sha:
        return False

    check_runs = gh.list_check_runs(repo, head_sha)
    return any(cr.get("conclusion") in _FAILING_CONCLUSIONS for cr in check_runs)


def _job_is_terminal(status: object) -> bool:
    """True if a Job has reached a terminal state (succeeded or failed).

    Terminal = a ``completion_time`` is set (succeeded) OR a ``Complete``/``Failed``
    condition is present with status ``"True"``. Everything else — including a
    just-created Job that is still ``Pending`` with no active pod yet — is
    NON-terminal and must count toward the concurrency cap, otherwise a burst of
    ticks could over-dispatch past ``max_concurrent_jobs`` before pods start.
    """
    if status is None:
        return False
    if getattr(status, "completion_time", None) is not None:
        return True
    conditions = getattr(status, "conditions", None) or []
    return any(
        getattr(c, "type", None) in ("Complete", "Failed")
        and getattr(c, "status", None) == "True"
        for c in conditions
    )


def _count_active_jobs(batch_api: "k8s_client.BatchV1Api", namespace: str) -> int:
    """Count NON-TERMINAL frankenbot-managed Jobs in the namespace.

    Counts Pending as well as Running Jobs (anything not succeeded/failed) so the
    concurrency cap holds even for freshly-created Jobs whose pods have not yet
    become active.
    """
    jobs = batch_api.list_namespaced_job(
        namespace=namespace,
        label_selector=f"app.kubernetes.io/managed-by={_JOB_MANAGED_BY}",
    )
    return sum(1 for job in jobs.items if not _job_is_terminal(job.status))


def _job_name(repo: RepoConfig, pr_number: int) -> str:
    """Build a DNS-1123-safe Job name, hashing when the natural name is too long.

    Format: ``monster-<repo-slug>-triage-pr<N>`` truncated to 63 chars, with a
    short hash suffix to preserve uniqueness when truncation occurs.
    """
    natural = f"monster-{repo.slug()}-triage-pr{pr_number}"
    if len(natural) <= _MAX_NAME_LEN:
        return natural
    digest = hashlib.sha1(natural.encode("utf-8")).hexdigest()[:8]
    prefix = natural[: _MAX_NAME_LEN - len(digest) - 1].rstrip("-")
    return f"{prefix}-{digest}"


def _create_triage_job(
    batch_api: "k8s_client.BatchV1Api",
    settings: Settings,
    repo: str,
    pr_number: int,
    job_name: str,
) -> None:
    """Create one ephemeral triage Job for ``repo``#``pr_number``."""
    nodepool_key, nodepool_value = settings.nodepool_key_value()

    node_affinity = k8s_client.V1NodeAffinity(
        # REQUIRED (not preferred): triage must run on the infrastructure pool.
        required_during_scheduling_ignored_during_execution=k8s_client.V1NodeSelector(
            node_selector_terms=[
                k8s_client.V1NodeSelectorTerm(
                    match_expressions=[
                        k8s_client.V1NodeSelectorRequirement(
                            key=nodepool_key,
                            operator="In",
                            values=[nodepool_value],
                        )
                    ]
                )
            ]
        )
    )

    container = k8s_client.V1Container(
        name="triage",
        image=settings.image,
        args=["triage", "--repo", repo, "--pr", str(pr_number)],
        # NO cpu limit on purpose: the agent workload (git + claude CLI) is bursty
        # and a CPU limit would trigger CFS throttling and inflate wall time. We
        # bound memory only. A cpu *request* still guarantees a scheduling floor.
        resources=k8s_client.V1ResourceRequirements(
            requests={"cpu": "250m", "memory": "1Gi"},
            limits={"memory": "3Gi"},
        ),
        env=[
            k8s_client.V1EnvVar(name="WORKSPACE_DIR", value="/workspace"),
            # Pass the image through explicitly so a nested dispatch (should one
            # ever exist) inherits the same image the dispatcher itself ran.
            k8s_client.V1EnvVar(name="FRANKENBOT_IMAGE", value=settings.image),
        ],
        env_from=[
            # ESO-managed secrets + config (Phase 3 provisions these objects).
            k8s_client.V1EnvFromSource(
                secret_ref=k8s_client.V1SecretEnvSource(name="frankenbot-github-app")
            ),
            k8s_client.V1EnvFromSource(
                secret_ref=k8s_client.V1SecretEnvSource(name="frankenbot-anthropic")
            ),
            k8s_client.V1EnvFromSource(
                config_map_ref=k8s_client.V1ConfigMapEnvSource(name="frankenbot-config")
            ),
        ],
        volume_mounts=[
            k8s_client.V1VolumeMount(name="workspace", mount_path="/workspace"),
        ],
    )

    pod_spec = k8s_client.V1PodSpec(
        restart_policy="Never",
        service_account_name="frankenbot",
        affinity=k8s_client.V1Affinity(node_affinity=node_affinity),
        containers=[container],
        volumes=[
            k8s_client.V1Volume(
                name="workspace",
                empty_dir=k8s_client.V1EmptyDirVolumeSource(size_limit="8Gi"),
            )
        ],
    )

    labels = {
        "app.kubernetes.io/managed-by": _JOB_MANAGED_BY,
        "app.kubernetes.io/component": "triage",
    }

    job = k8s_client.V1Job(
        metadata=k8s_client.V1ObjectMeta(name=job_name, labels=labels),
        spec=k8s_client.V1JobSpec(
            backoff_limit=1,
            active_deadline_seconds=1800,
            ttl_seconds_after_finished=3600,
            template=k8s_client.V1PodTemplateSpec(
                metadata=k8s_client.V1ObjectMeta(labels=labels),
                spec=pod_spec,
            ),
        ),
    )

    batch_api.create_namespaced_job(namespace=settings.namespace, body=job)
