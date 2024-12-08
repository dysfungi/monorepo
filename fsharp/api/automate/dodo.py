import datetime as dt
import json
import os
import platform
import re
from functools import partial
from logging import getLogger
from pathlib import Path
from typing import Any, Callable, Generator, Iterable, Optional

from doit import tools

logger = getLogger(__name__)


DOIT_CONFIG: dict = {
    "default_tasks": [],
}

APP_FSPROJ = Path("./AutoMate/AutoMate.fsproj").absolute()
TESTS_FSPROJ = Path("./AutoMate.Tests/AutoMate.Tests.fsproj").absolute()


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
        "actions": [
            tools.LongRunning(compose("build")),
            tools.LongRunning(compose("push")),
            tools.LongRunning(tofu("init", migrate_state=None)),
            tools.LongRunning(tofu("apply", auto_approve=None)),
        ],
        "setup": [
            "_setup:app_version",
        ],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }


@task
def dockerwatch() -> Generator[dict, None, None]:
    yield {
        "name": "run",
        "actions": [
            tools.LongRunning(
                compose("run", "api-debug", build=None, rm=None, remove_orphans=None)
            ),
        ],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }
    yield {
        "name": "test",
        "actions": [
            tools.LongRunning(
                compose("run", "api-tests", build=None, rm=None, remove_orphans=None)
            ),
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
def gen_version() -> dict:
    return {
        "actions": [
            'echo "$APP_VERSION"',
        ],
        "setup": [
            "_setup:app_version",
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
def test() -> dict:
    return {
        "actions": [
            tools.LongRunning(dotnet("test", TESTS_FSPROJ)),
        ],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }


tests = test


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
def watch() -> Generator[dict, None, None]:
    yield {
        "name": "run",
        "actions": [
            tools.LongRunning(dotnet("watch", "run", project=APP_FSPROJ)),
        ],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }
    yield {
        "name": "test",
        "actions": [
            tools.LongRunning(dotnet("watch", "test", project=TESTS_FSPROJ)),
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


@task
def _setup() -> Generator[dict, None, None]:
    app_version = _app_version()
    branch_name = _git_branch_name(safe=True)
    epoch = dt.datetime.utcnow().strftime("%s")
    version_suffix = f"{branch_name}.{epoch}"
    old_app_version = os.environ.get("APP_VERSION", app_version)
    new_app_version = f"{app_version}-{version_suffix}"

    yield {
        "name": "app_version",
        "actions": [
            partial(os.environ.__setitem__, "APP_VERSION", new_app_version),
            partial(os.environ.__setitem__, "TF_VAR_app_version", new_app_version),
        ],
        "teardown": [
            partial(os.environ.__setitem__, "APP_VERSION", old_app_version),
            partial(os.environ.__setitem__, "TF_VAR_app_version", old_app_version),
        ],
        "title": tools.title_with_actions,
    }


def compose(command, *args, **options) -> str:
    posargs = _positionize(args)
    optargs = _optize(options)
    return f"docker compose {command} {optargs} {posargs}"


def date(*args, **options) -> str:
    posargs = _positionize(args)
    optargs = _optize(options)
    gnudate = "gdate" if platform.system() == "Darwin" else "date"
    return f"{gnudate} {optargs} {posargs}"


def dotnet(command, *args, **options) -> str:
    posargs = _positionize(args)
    optargs = _optize(options)
    return f"dotnet {command} {posargs} {optargs}"


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
    with open(APP_FSPROJ) as fp:
        for line in fp:
            if "<Version>" not in line:
                continue
            return line.strip().removeprefix("<Version>").removesuffix("</Version>")
        else:
            raise RuntimeError("Could not find version")


def _git_branch_name(*, safe: bool = False) -> str:
    cwd = Path.cwd()
    git_head = next(
        git_head for parent in cwd.parents for git_head in parent.glob(".git/HEAD")
    )
    with git_head.open("rt") as fp:
        name = next(
            line.strip().partition("refs/heads/")[-1]
            for line in fp
            if line.startswith("ref:")
        )

    return re.sub(r"[^a-z0-9_.-]+", "-", name, flags=re.IGNORECASE) if safe else name
