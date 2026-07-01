"""Unit tests for :mod:`frankenbot.classifier`.

These tests are the durable spec for the risk-tier model: the tier matrix
(T0-T4), reversibility from tofu actions, the worst-tier-wins combination, and
the infra auto-merge allowlist gate. Inputs are real ``tofu show -json``-shaped
plan dicts rather than mocks so the parser is exercised end to end.
"""

from __future__ import annotations

import json
from typing import Any

import pytest

from frankenbot.classifier import Classification, Tier, classify, load_plan


def _plan(*action_lists_with_types: tuple[list[str], str]) -> dict[str, Any]:
    """Build a minimal plan from (actions, resource_type) pairs."""
    return {
        "resource_changes": [
            {"type": rtype, "change": {"actions": actions}}
            for actions, rtype in action_lists_with_types
        ]
    }


def test_destroy_plan_is_t4_irreversible_human() -> None:
    result = classify(_plan((["delete"], "vultr_instance")))
    assert result.tier is Tier.T4
    assert result.reversible is False
    assert result.merge_policy == "human"
    assert result.auto_eligible is False
    assert result.ttl_hours is None


def test_replace_plan_is_t4() -> None:
    result = classify(_plan((["delete", "create"], "vultr_instance")))
    assert result.tier is Tier.T4
    assert result.reversible is False
    assert result.merge_policy == "human"


def test_create_delete_order_is_also_replace_t4() -> None:
    # tofu may emit the pair in either order; both are a replace (irreversible).
    result = classify(_plan((["create", "delete"], "vultr_instance")))
    assert result.tier is Tier.T4
    assert result.reversible is False


def test_allowlisted_infra_provider_bump_is_t1_auto() -> None:
    result = classify(
        _plan((["update"], "helm_release")),
        update_type="minor",
        changed_paths=["terraform/applications/foo/main.tf"],
    )
    assert result.tier is Tier.T1
    assert result.reversible is True
    assert result.auto_eligible is True
    assert result.allowlisted is True
    assert result.merge_policy == "auto"
    assert result.ttl_hours == 48


def test_non_allowlisted_infra_update_is_t1_but_not_auto() -> None:
    result = classify(
        _plan((["update"], "vultr_kubernetes")),
        update_type="minor",
        changed_paths=["terraform/infrastructure/frankenstructure/cluster.tf"],
    )
    assert result.tier is Tier.T1
    assert result.reversible is True
    assert result.auto_eligible is False
    assert result.allowlisted is False
    assert result.merge_policy == "human"
    assert any("allowlist" in r for r in result.reasons)


def test_major_bump_is_t3_human() -> None:
    result = classify(
        _plan((["update"], "helm_release")),
        update_type="major",
    )
    assert result.tier is Tier.T3
    assert result.merge_policy == "human"
    assert result.auto_eligible is False
    assert result.ttl_hours is None


def test_reversible_codemod_minor_is_t2() -> None:
    result = classify(
        {},
        update_type="minor",
        needs_codemod=True,
        changed_paths=["python/pipeline/foo/bar.py"],
    )
    assert result.tier is Tier.T2
    assert result.reversible is True
    assert result.auto_eligible is True
    assert result.merge_policy == "auto"
    assert result.ttl_hours == 72


def test_docs_only_is_t0() -> None:
    result = classify(
        {"resource_changes": []},
        changed_paths=["README.md", "docs/guide.md", ".editorconfig"],
    )
    assert result.tier is Tier.T0
    assert result.reversible is True
    assert result.auto_eligible is True
    assert result.merge_policy == "auto"
    assert result.ttl_hours == 24


def test_empty_plan_does_not_raise_and_is_reversible() -> None:
    # No resource_changes key at all → treated as no infra change.
    result = classify({})
    assert result.reversible is True
    assert isinstance(result, Classification)


def test_migration_path_forces_t4() -> None:
    # Even a reversible plan + minor bump is T4 if a DB migration is touched.
    result = classify(
        _plan((["create"], "helm_release")),
        update_type="minor",
        changed_paths=["services/api/db/migrations/0007_add_col.sql"],
    )
    assert result.tier is Tier.T4
    assert result.merge_policy == "human"


def test_secret_rotation_path_forces_t4() -> None:
    result = classify(
        {},
        changed_paths=["ops/rotate-db-secret.yaml"],
    )
    assert result.tier is Tier.T4


def test_registry_publish_workflow_forces_t4() -> None:
    result = classify(
        {},
        changed_paths=[".github/workflows/publish-image.yml"],
    )
    assert result.tier is Tier.T4


def test_infra_path_without_parseable_resources_is_not_auto() -> None:
    # Terraform files changed but the plan shows nothing to verify → conservative.
    result = classify(
        {"resource_changes": []},
        changed_paths=["terraform/modules/net/variables.tf"],
    )
    assert result.tier is Tier.T1
    assert result.auto_eligible is False
    assert result.allowlisted is False


def test_invalid_update_type_raises() -> None:
    with pytest.raises(ValueError):
        classify({}, update_type="megabump")


def test_malformed_resource_changes_raises() -> None:
    with pytest.raises(ValueError):
        classify({"resource_changes": "not-a-list"})


def test_to_dict_and_comment_roundtrip() -> None:
    result = classify(_plan((["delete"], "vultr_instance")))
    payload = result.to_dict()
    assert payload["tier"] == "T4"
    assert payload["reversible"] is False
    # Must be JSON-serializable.
    assert json.loads(json.dumps(payload))["merge_policy"] == "human"
    comment = result.to_comment()
    assert "Frankenbot risk classification" in comment
    assert "T4" in comment


def test_load_plan_roundtrip(tmp_path: Any) -> None:
    plan = _plan((["update"], "helm_release"))
    path = tmp_path / "plan.json"
    path.write_text(json.dumps(plan), encoding="utf-8")
    loaded = load_plan(str(path))
    assert loaded == plan


def test_load_plan_missing_file_raises(tmp_path: Any) -> None:
    with pytest.raises(FileNotFoundError):
        load_plan(str(tmp_path / "nope.json"))
