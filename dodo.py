import json
import os
from contextlib import contextmanager
from importlib.machinery import SourceFileLoader
from itertools import chain
from logging import getLogger
from operator import attrgetter
from pathlib import Path
from typing import (
    Any,
    Callable,
    Generator,
    Iterable,
    NamedTuple,
    Optional,
    Self,
    TypedDict,
    Unpack,
)

from doit import tools
from doit.api import run_tasks
from doit.cmd_base import ModuleTaskLoader

logger = getLogger(__name__)

DOIT_CONFIG: dict = {
    "default_tasks": ["ls"],
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
def autoupgrade() -> dict:
    return {
        "actions": [
            tools.LongRunning(
                _pipe(
                    _find(".", type="f", name=".terraform.lock.hcl"),
                    _rp("dirname"),
                    _rp("pushd {0} && tofu init -upgrade", regex=r"^.*$", shell=None),
                )
            ),
        ],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }


@task
def build() -> Generator[dict, None, None]:
    """Build all (default) or given project(s).

    Filter subtasks with wildcards for `$LANGUAGE/$CATEGORY/$PROJECT`
    """

    def _build(*, project):
        project.doit(build=None)

    for project in Project.all():
        yield {
            "name": "/".join(
                map(
                    str.lower,
                    [
                        project.display_language,
                        project.category,
                        project.name,
                    ],
                ),
            ),
            "actions": [(_build, (), {"project": project})],
            "verbosity": 2,
        }


@task
def cleanpy() -> Generator[dict, None, None]:
    """Clean reproducible Python files."""
    cwd = Path.cwd()

    def cache():
        """Clean Python cache files."""
        for pycache_dir in cwd.rglob("__pycache__"):
            _rmtree(pycache_dir)

    for clean_func in [cache]:
        yield {
            "name": clean_func.__name__,
            "actions": [clean_func],
            "verbosity": 2,
        }


@task
def cwd() -> dict:
    """Print working directory for Doit dodo.py execution."""
    return {
        "actions": ["pwd"],
        "verbosity": 2,
    }


@task
def lint() -> dict:
    """Run linters using Pre-commit."""
    return {
        "actions": [
            tools.Interactive("git add --patch"),
            "pre-commit run --all-files --show-diff-on-failure",
        ],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }


@task
def ls() -> dict:
    """List all projects."""

    def _print_all_projects(
        sortby: list[str],
        category: str | None,
        language: str | None,
        name: str | None,
    ) -> None:
        sortby.append("name")
        projects = [
            p
            for p in Project.all()
            if (not category or category.lower() in p.cat.lower())
            and (not language or language.lower() in p.lang.lower())
            and (not name or name.lower() in p.name.lower())
        ]
        head_name = "project name"
        head_lang = "language"
        head_cat = "category"
        head_subtask = "sub-task name"

        def get_max(attr: str, header: str) -> int:
            return max(
                len(s)
                for s in chain(
                    (getattr(p, attr) for p in projects),
                    [header],
                )
            )

        max_cat = get_max("category", head_cat)
        max_lang = get_max("language", head_lang)
        max_name = get_max("name", head_name)
        max_subtask = get_max("subtask_name", head_subtask)

        def format_cat(v):
            return format(v, f"{max_cat}")

        def format_lang(v):
            return format(v, f"{max_lang}")

        def format_name(v):
            return format(v, f"{max_name}")

        def format_subtask(v):
            return format(v, f"{max_subtask}")

        # TODO(relative-path): cwd = Path.cwd()
        header = " | ".join(
            [
                format_name(head_name),
                format_lang(head_lang),
                format_cat(head_cat),
                format_subtask(head_subtask),
                # TODO(relative-path): f"relative path ({cwd})",
            ],
        )
        print(header)
        print("-" * len(header))
        for p in sorted(projects, key=attrgetter(*sortby)):
            row = " | ".join(
                [
                    format_name(p.name),
                    format_lang(p.display_lang),
                    format_cat(p.cat),
                    format_subtask(p.subtask_name),
                    # TODO(relative-path): f"{p.path.relative_to(cwd)}",
                ],
            )
            print(row)

    return {
        "actions": [_print_all_projects],
        "params": [
            {
                "name": "sortby",
                "long": "sortby",
                "short": "s",
                "type": list,
                "default": [],
                "choices": [
                    ("cat", "project category"),
                    ("lang", "project language"),
                    ("name", "project name"),
                ],
            },
            {
                "name": "category",
                "long": "cat",
                "short": "c",
                "type": str,
                "default": None,
                "help": "case-insensitive substring match on category",
            },
            {
                "name": "language",
                "long": "lang",
                "short": "l",
                "type": str,
                "default": None,
                "help": "case-insensitive substring match on language",
            },
            {
                "name": "name",
                "long": "name",
                "short": "n",
                "type": str,
                "default": None,
                "help": "case-insensitive substring match on name",
            },
        ],
        "verbosity": 2,
    }


@task
def setup() -> Generator[dict, None, None]:
    def _setup(*, project):
        project.doit(setup=None)

    yield {
        "name": "root",
        "actions": [
            "brew bundle",
            "pre-commit install",
        ],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }

    for project in Project.all():
        yield {
            "name": "/".join(
                map(
                    str.lower,
                    [
                        project.display_language,
                        project.category,
                        project.name,
                    ],
                ),
            ),
            "actions": [(_setup, (), {"project": project})],
            "verbosity": 2,
        }


@task
def start() -> Generator[dict, None, None]:
    """Run all (default) or given projects.

    Filter subtasks with wildcards for `$LANGUAGE/$CATEGORY/$PROJECT`
    """

    def _start(*, project):
        project.doit(start=None)

    for project in Project.all():
        yield {
            "name": "/".join(
                [
                    s.lower()
                    for s in [
                        project.display_language,
                        project.category,
                        project.name,
                    ]
                ],
            ),
            "actions": [(_start, (), {"project": project})],
            "verbosity": 2,
        }


class BuildParams(TypedDict, total=False):
    pass


class SetupParams(TypedDict, total=False):
    pass


class StartParams(TypedDict, total=False):
    pass


class ProjectTasks(TypedDict, total=False):
    build: Optional[BuildParams]
    setup: Optional[SetupParams]
    start: Optional[StartParams]


class Project(NamedTuple):
    name: str
    category: str  # functional-area
    language: str  # primary programming language
    path: Path

    @property
    def cat(self) -> str:
        return self.category

    @property
    def lang(self) -> str:
        return self.language

    @property
    def display_category(self) -> str:
        return self.category.title()

    @property
    def display_cat(self) -> str:
        return self.display_category

    @property
    def display_language(self) -> str:
        return {
            "clojure": "Clojure",
            "elixir": "Elixir",
            "elm": "Elm",
            "fsharp": "F#",
            "go": "Go",
            "haskell": "Haskell",
            "ocaml": "OCaml",
            "python": "Python",
            "reasonml": "ReasonML",
            "rust": "Rust",
            "terraform": "Terraform",  # HCL, TF
        }[self.language]

    @property
    def display_lang(self) -> str:
        return self.display_language

    @property
    def display_path(self) -> str:
        return str(self.path)

    @property
    def subtask_name(self) -> str:
        return "/".join(
            map(
                str.lower,
                [
                    self.display_language,
                    self.category,
                    self.name,
                ],
            ),
        )

    def __str__(self) -> str:
        return " ".join(
            [
                self.name,
                f"[{self.display_language}]",
                f"({self.display_category})",
                self.display_path,
            ],
        )

    def doit(
        self,
        *,
        verbosity: int = 2,  # TOOD(dfrank): support extra/global/build config?
        **tasks_to_params: Unpack[ProjectTasks],
    ) -> int:
        """Run tasks from this project's dodo.py."""
        dodo_path = self.path / "dodo.py"
        if not dodo_path.exists():
            return 1

        module_name = ".".join([self.lang, self.cat, self.name, "dodo"])
        module = SourceFileLoader(module_name, str(dodo_path)).load_module()
        supported_tasks_to_params = {
            task_name: params
            for task_name, params in tasks_to_params.items()
            if hasattr(module, task_name)
            and hasattr(getattr(module, task_name), "create_doit_tasks")
            or hasattr(module, f"task_{task_name}")
        }
        if not supported_tasks_to_params:
            return 2

        task_loader = ModuleTaskLoader(module)
        extra_config = {
            "GLOBAL": {
                "verbosity": verbosity,
            },
            # TODO(dmf): Support task config like "task:build"
        }
        with _chdir(self.path):
            return run_tasks(
                loader=task_loader,
                tasks=supported_tasks_to_params,
                extra_config=extra_config,
            )

    @classmethod
    def all(cls, root: Path = Path.cwd()) -> list[Self]:
        """Return a list of project instances for every project in this repo.

        References:
            https://www.rocketpoweredjetpants.com/2017/11/organising-a-monorepo/#blended-monorepos
        """
        part_ignores = {".git", "node_modules", "__pycache__"}
        projects = [
            cls(
                name=directory.name,
                category=directory.parent.name,
                language=directory.parent.parent.name,
                path=directory,
            )
            for directory in root.glob("*/*/*/")
            if not part_ignores & set(directory.parts)
            and (directory / "dodo.py").exists()
        ]
        return projects


@contextmanager
def _chdir(path: Path):
    cwd = os.getcwd()
    os.chdir(path)
    try:
        yield path
    finally:
        os.chdir(cwd)


def _find(*paths: str | Path, **options) -> str:
    pos_params = _positionize(paths)
    opt_params = _optize(options, long_prefix="-", separator=" ")
    return f"find {pos_params} {opt_params}"


def _pipe(*commands: str) -> str:
    return " | ".join(commands)


def _rp(command: str, *initial_args: str, **options) -> str:
    pos_params = _positionize(initial_args)
    opt_params = _optize(options)
    return f"rust-parallel {opt_params} -- '{command}' {pos_params}"


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


def _rmtree(path: Path) -> None:
    """Recursively delete a given path by walking and deleting the tree
    bottom-up. Allows for deleting non-empty directories, which is not
    supported by ``Path.rmdir()``. Essentially an implementation of
    ``shutil.rmtree`` for ``pathlib``.

    References:
        https://docs.python.org/3/library/pathlib.html#pathlib.Path.walk
        https://docs.python.org/3/library/shutil.html#shutil.rmtree
    """
    for root, dirs, files in path.walk(top_down=False):
        for name in files:
            (root / name).unlink()
        for name in dirs:
            (root / name).rmdir()
    if path.is_dir():
        path.rmdir()
    else:
        path.unlink()
