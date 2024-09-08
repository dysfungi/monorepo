from logging import getLogger

logger = getLogger(__name__)

DOIT_CONFIG = {
    "default_tasks": [],
}


def task(func: callable) -> callable:
    """Decorate tasks.

    https://pydoit.org/task-creation.html#custom-task-definition
    """
    func.create_doit_tasks = func
    return func


@task
def build() -> dict:
    return {
        "actions": ["echo build successful - %(foobar)s"],
        "params": [
            {
                "name": "foobar",
                "default": "foobar"
            },
        ],
    }
