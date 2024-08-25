from pathlib import Path
from typing import NamedTuple

from doit import task_params

LANGUAGE_DISPLAY_VALUES = {
    "fsharp": "F#",
    "hcl": "HCL",
}


def task_ls() -> dict:
    """List all projects."""

    def _print_all_projects():
        projects = _get_all_projects()
        for project in projects:
            print(project)

    return {"actions": [_print_all_projects], "verbosity": 2}


def task_build() -> dict:
    """Build all (default) or given project(s)."""

    def _build(args):
        projects = _get_all_projects()
        given = set(args) if args else {project.name for project in projects}
        for project in projects:
            if project.name not in given:
                continue
            print(f"Building {project}")

    return {
        "actions": [_build],
        "pos_arg": "args",
        "verbosity": 2,
    }


class Project(NamedTuple):
    name: str
    language: str
    path: Path

    def __str__(self):
        return f"{self.name} ({self.language}) {self.path}"


def _get_all_projects() -> list[Project]:
    cwd = Path.cwd()
    projects = [
        Project(
            name=directory.name,
            path=directory,
            language=LANGUAGE_DISPLAY_VALUES.get(
                directory.parent.name,
                directory.parent.name,
            ),
        )
        for directory in cwd.glob("*/*/")
        if ".git" not in directory.parts
    ]
    return projects
