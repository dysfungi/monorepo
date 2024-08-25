from pathlib import Path
from typing import NamedTuple

DOIT_CONFIG = {
    "default_tasks": ["ls"],
}

LANGUAGE_DISPLAY_VALUES = {
    "clojure": "Clojure",
    "elixir": "Elixir",
    "elm": "Elm",
    "fsharp": "F#",
    "go": "Go",
    "haskell": "Haskell",
    "hcl": "HCL",
    "ocaml": "OCaml",
    "python": "Python",
    "reasonml": "ReasonML",
    "rust": "Rust",
}


def task(func: callable) -> callable:
    """Decorate tasks.

    https://pydoit.org/task-creation.html#custom-task-definition
    """
    func.create_doit_tasks = func
    return func


@task
def ls() -> dict:
    """List all projects."""

    def _print_all_projects():
        projects = _get_all_projects()
        for project in projects:
            print(project)

    return {"actions": [_print_all_projects], "verbosity": 2}


@task
def build() -> dict:
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
    category: str  # functional-area
    language: str  # primary programming language
    path: Path

    def __str__(self):
        return f"{self.name} [{self.language}] ({self.category}) {self.path}"


def _get_all_projects() -> list[Project]:
    # https://www.rocketpoweredjetpants.com/2017/11/organising-a-monorepo/#blended-monorepos
    cwd = Path.cwd()
    projects = sorted(
        Project(
            name=directory.name,
            category=directory.parent.name,
            language=LANGUAGE_DISPLAY_VALUES.get(
                directory.parent.parent.name,
                directory.parent.parent.name,
            ),
            path=directory,
        )
        for directory in cwd.glob("*/*/*/")
        if ".git" not in directory.parts
    )
    return projects
