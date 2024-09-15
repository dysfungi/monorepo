from logging import getLogger
from typing import Callable

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
        "actions": ["tofu plan"],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }


@task
def copy_registry_id() -> dict:
    return {
        "actions": [
            " | ".join(
                [
                    "vultr container-registry list --output=json",
                    _jq(
                        '.registries[] | select(.name == "frankistry").id',
                        raw_output=None,
                    ),
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
                    "vultr object-storage list --output=json",
                    _jq(
                        '.object_storages[] | select(.label == "frankenstorage").id',
                        raw_output=None,
                    ),
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
        "actions": ["tofu apply -auto-approve"],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }


@task
def setup() -> dict:
    return {
        "actions": ["tofu init"],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }


def _jq(script: str, *files, **options) -> str:
    opt_params = " ".join(
        optname if optvalue is None else f"{optname}={optvalue}"
        for optname, optvalue in (
            (
                (f"-{name}" if len(name) == 1 else f"--{name}").replace("_", "-"),
                value,
            )
            for name, value in options.items()
        )
    )
    params = " ".join(f'"{name}"' for name in files)
    return f"jq {opt_params} '{script}' {params}"
