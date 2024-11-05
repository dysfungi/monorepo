import json
import platform
from logging import getLogger
from pathlib import Path
from typing import Any, Callable, Iterable, Optional

from doit import tools

logger = getLogger(__name__)


DOIT_CONFIG: dict = {
    "default_tasks": [],
}


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
        "actions": [
            tools.LongRunning(compose("build")),
        ],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }


@task
def cleandocker() -> dict:
    return {
        "actions": [
            compose("down", remove_orphans=None, volumes=None),
        ],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }


@task
def deploy() -> dict:
    return {
        "task_dep": ["build", "push"],
        "actions": [
            tools.LongRunning(tofu("apply", auto_approve=None)),
        ],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }


@task
def down() -> dict:
    return {
        "actions": [
            tools.LongRunning(compose("down", remove_orphans=None)),
        ],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }


@task
def plan() -> dict:
    return {
        "actions": [
            tools.LongRunning(tofu("plan")),
        ],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }


@task
def push() -> dict:
    return {
        "actions": [
            tools.LongRunning(compose("push")),
        ],
        "task_dep": ["build"],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }


@task
def setup() -> dict:
    return {
        "actions": [
            tools.LongRunning(tofu("init")),
        ],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }


@task
def up() -> dict:
    return {
        "actions": [
            tools.LongRunning(compose("up", detach=None, wait=None)),
        ],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }


@task
def version() -> dict:
    def _show_version():
        print(_app_version())

    return {
        "actions": [
            _show_version,
        ],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }


@task
def web() -> dict:
    return {
        "actions": [
            'python -m webbrowser -t "http://$(docker compose port api 8080)"',
        ],
        "task_dep": ["up"],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }


def compose(command, *args, **options) -> str:
    posargs = _positionize(args)
    optargs = _optize(options)
    return f"docker compose {optargs} {command} {posargs}"


def date(*args, **options) -> str:
    posargs = _positionize(args)
    optargs = _optize(options)
    gnudate = "gdate" if platform.system() == "Darwin" else "date"
    return f"{gnudate} {optargs} {posargs}"


def tofu(command, *args, **options) -> str:
    posargs = _positionize(args)
    optargs = _optize(options, long_prefix="-")
    return f"tofu -chdir=terraform {command} {optargs} {posargs}"


def _optize(options: dict[str, Any], *, long_prefix="--", separator="=") -> str:
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
        return json.dumps(str(value) if isinstance(value, Path) else value)

    optionized = (
        (fix_optname(name), fix_optvalue(value)) for name, value in options.items()
    )
    return " ".join(
        name if value is None else f"{name}{separator}{value}"
        for name, value in optionized
    )


def _positionize(args: Iterable) -> str:
    """Convert args to a CLI style positional parameter string where each
    argument is double quoted.
    """
    return " ".join(f'"{arg}"' for arg in args)


def _app_version() -> str:
    cwd = Path.cwd()
    fsproj, *more = cwd.glob("*.fsproj")
    assert not more, more
    with open(fsproj) as fp:
        for line in fp:
            if "<Version>" not in line:
                continue
            return line.strip().removeprefix("<Version>").removesuffix("</Version>")
        else:
            raise RuntimeError("Could not find version")
