from logging import getLogger
from typing import Callable

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
            "dotnet build",
        ],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }


@task
def start() -> dict:
    return {
        "actions": [
            tools.LongRunning("dotnet watch run"),
        ],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }
