from logging import getLogger
from pathlib import Path
from typing import Any, Callable, Generator, Iterable, Optional

from doit import tools

logger = getLogger(__name__)


DOIT_CONFIG: dict = {
    "default_tasks": [],
}


DEFAULT_STORAGE_LABEL = "frankenstorage"
DEFAULT_REGISTRY_NAME = "frankistry"


class task:
    """Decorate tasks with a special attribute to be found by Doit.
    This is a class instead of a function to prevent mypy
    [attr-defined] error.

    References:
        https://pydoit.org/task-creation.html#custom-task-definition
        https://mypy.readthedocs.io/en/stable/error_code_list.html#check-that-attribute-exists-attr-defined
    """

    def __init__(self, func: Callable):
        self.create_doit_tasks = func

    def __call__(self, *args, **kwargs):
        return self.create_doit_tasks(*args, **kwargs)


@task
def build() -> dict:
    return {
        "actions": [_tofu("plan")],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }


@task
def copy_k8s_id() -> dict:
    return {
        "actions": [
            " | ".join(
                [
                    _vultr("kubernetes", "list"),
                    _jq('.vke_clusters[] | select(.label == "frank8s").id'),
                ],
            ),
            "pbpaste",
        ],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }


@task
def copy_registry_id() -> dict:
    return {
        "actions": [
            " | ".join(
                [
                    _vultr("container-registry", "list"),
                    _jq('.registries[] | select(.name == "frankistry").id'),
                    "pbcopy",
                ],
            ),
            "pbpaste",
        ],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }


@task
def copy_storage_id() -> dict:
    return {
        "actions": [
            " | ".join(
                [
                    _vultr("object-storage", "list"),
                    _jq('.object_storages[] | select(.label == "frankenstorage").id'),
                    "pbcopy",
                ],
            ),
            "pbpaste",
        ],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }


@task
def deploy() -> dict:
    return {
        "actions": [_tofu("apply", auto_approve=None)],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }


@task
def setup() -> dict:
    return {
        "actions": [
            _tofu("init"),
        ],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }


@task
def test() -> Generator[dict, None, None]:
    cert_manager_testfile = Path("tests/test-cert-manager.yaml")
    assert cert_manager_testfile.exists()
    clean_cert_manager = _kubectl("delete", filename=cert_manager_testfile)
    yield {
        # https://cert-manager.io/docs/installation/kubectl/#verify
        "name": "cert-manager",
        "actions": [
            _kubectl("apply", filename=cert_manager_testfile),
            "sleep 10",
            _kubectl("describe", "certificate", n="cert-manager-test"),
            clean_cert_manager,
        ],
        "clean": [clean_cert_manager],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }


def _helm(command: str, *args, output: str = "json", **options) -> str:
    """Build a string for calling Helm in the CLI."""
    output = options.pop("o", output)
    if command not in {"repo"}:
        options["output"] = output
    pos_params = _positionize(args)
    opt_params = _optize(options)
    return f"helm {command} {pos_params} {opt_params}"


def _jq(script: str, *files, raw_output: bool = True, **options) -> str:
    """Build a string for calling JQ in the CLI."""
    if raw_output or raw_output is None:
        options["raw_output"] = None
    pos_params = _positionize(files)
    opt_params = _optize(options)
    return f"jq {opt_params} '{script}' {pos_params}"


def _kubectl(command: str, *args, **options) -> str:
    """Build a string for calling kubectl in the CLI."""
    pos_params = _positionize(args)
    opt_params = _optize(options)
    return f"kubectl {command} {pos_params} {opt_params}"


def _tofu(command: str, *args, **options) -> str:
    """Build a string for calling Tofu in the CLI."""
    pos_params = _positionize(args)
    opt_params = _optize(options, long_prefix="-")
    return f"tofu {command} {opt_params} {pos_params}"


def _vultr(resource: str, command: str, *args, output: str = "json", **options) -> str:
    """Build a string for calling Vultr in the CLI."""
    output = options.pop("o", output)
    pos_params = _positionize(args)
    opt_params = _optize(options)
    return f"vultr --output={output} {resource} {command} {opt_params} {pos_params}"


def _xargs(utility: str, *args, **options) -> str:
    """Build a string for calling Xargs in the CLI."""
    pos_params = _positionize(args)
    opt_params = _optize(options)
    return f"xargs {opt_params} {utility} {pos_params}"


def _positionize(args: Iterable) -> str:
    """Convert args to a CLI style positional parameter string where each
    argument is double quoted.
    """
    return " ".join(f'"{arg}"' for arg in args)


def _optize(options: dict[str, Any], *, long_prefix="--") -> str:
    """Convert a dictionary to a CLI style option parameters string. Single
    character names are treated as short options while anything else are treated as
    long options. Also, underscores are converted to dashes.
    """

    def fix_optname(name: str) -> str:
        name = name.replace("_", "-").strip("-")
        return f"-{name}" if len(name) == 1 else f"{long_prefix}{name}"

    def fix_optvalue(value: Any) -> Optional[str]:
        if value is None:
            return None
        if isinstance(value, bool):
            return str(value).lower()
        return f'"{value}"'

    optionized = (
        (fix_optname(name), fix_optvalue(value)) for name, value in options.items()
    )
    return " ".join(
        name if value is None else f"{name}={value}" for name, value in optionized
    )
