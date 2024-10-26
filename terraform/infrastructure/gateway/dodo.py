import json
from functools import partial
from logging import getLogger
from pathlib import Path
from typing import Any, Callable, Generator, Iterable, Optional, Self, TypedDict

from doit import task_params, tools

logger = getLogger(__name__)


DOIT_CONFIG: dict = {
    "default_tasks": [],
}
NAMESPACE = "gateway"


class task:
    """Decorate tasks with a special attribute to be found by Doit.
    This is a class instead of a function to prevent mypy
    [attr-defined] error.

    References:
        https://pydoit.org/task-creation.html#custom-task-definition
        https://mypy.readthedocs.io/en/stable/error_code_list.html#check-that-attribute-exists-attr-defined
    """

    def __init__(self, func: Callable, *, params: Optional[list[dict]] = None):
        self._params = params
        self.create_doit_tasks = func if params is None else task_params(params)(func)

    def __call__(self, *args, **kwargs):
        return self.create_doit_tasks(*args, **kwargs)

    @classmethod
    def with_params(cls, params: list[dict]) -> Callable[[Callable], Self]:
        # TODO: https://github.com/python/mypy/issues/17646#issuecomment-2281182505
        return partial(cls, params=params)  # type: ignore[misc]


@task
def build() -> dict:
    return {
        "actions": [_tofu("plan")],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }


@task
def get_config() -> Generator[dict, None, None]:
    yield {
        "name": "nginx",
        "actions": [
            "mkdir -p configs",
            " | ".join(
                [
                    _kubectl(
                        "exec",
                        "svc/nginx-gateway",
                        "--",
                        "nginx",
                        "-T",
                        container="nginx",
                        namespace=NAMESPACE,
                    ),
                    "tee configs/nginx.conf",
                ]
            ),
            "echo",
        ],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }


@task
def debug_staging_cert() -> Generator[dict, None, None]:
    yield {
        "name": "certificate",
        "actions": [
            _kubectl("get", "certificate", namespace=NAMESPACE),
            _kubectl("describe", "certificate", namespace=NAMESPACE),
            "echo",
        ],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }
    yield {
        "name": "certificaterequest",
        "actions": [
            _kubectl("get", "certificaterequest", namespace=NAMESPACE),
            _kubectl("describe", "certificaterequest", namespace=NAMESPACE),
            "echo",
        ],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }
    yield {
        "name": "order",
        "actions": [
            _kubectl("get", "order", namespace=NAMESPACE),
            _kubectl("describe", "order", namespace=NAMESPACE),
            "echo",
        ],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }
    yield {
        # https://cert-manager.io/docs/installation/kubectl/#verify
        "name": "challenge",
        "actions": [
            _kubectl("get", "challenge", namespace=NAMESPACE),
            _kubectl("describe", "challenge", namespace=NAMESPACE),
            "dig -t TXT _acme-challenge.letsencrypt-test.staging.api.frank.sh",
            "echo",
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


@task.with_params(
    [
        {
            "name": "all_containers",
            "long": "all-containers",
            "short": "a",
            "type": bool,
            "default": False,
            "help": "Get all containers' logs in the pod(s).",
        },
        {
            "name": "container",
            "long": "container",
            "short": "c",
            "type": str,
            "default": None,
            "help": "Print the logs of this container.",
        },
        {
            "name": "follow",
            "long": "follow",
            "short": "f",
            "type": bool,
            "default": False,
            "help": "Specify if the logs should be streamed.",
        },
        {
            "name": "prefix",
            "long": "prefix",
            "short": "p",
            "type": bool,
            "default": False,
            "help": "Prefix each log line with the log source (pod/container name).",
        },
        {
            "name": "previous",
            "long": "previous",
            "type": bool,
            "default": False,
            "help": "Print logs for the previous instance of the container in a pod.",
        },
        {
            "name": "since",
            "long": "since",
            "short": "s",
            "type": str,
            "default": "0s",
            "help": "Only return logs newer than a relative duration (e.g., 2m, 3h).",
        },
        {
            "name": "tail",
            "long": "tail",
            "short": "t",
            "type": int,
            "default": -1,
            "help": "Lines of recent log file to display.",
        },
    ]
)
def logs(
    *,
    all_containers: bool = False,
    container: Optional[str] = None,
    previous,
    **options,
) -> Generator[dict, None, None]:
    params = logs._params

    def _gen_extra(container: Optional[str] = None) -> LogsExtra:
        extra: LogsExtra = {}
        if all_containers:
            extra["all_containers"] = all_containers
        elif container:
            extra["container"] = container
        return extra

    yield {
        "name": "external-dns",
        "actions": [
            _kubectl(
                "logs",
                namespace=NAMESPACE,
                selector="app.kubernetes.io/name=external-dns",
                **options,
                **_gen_extra(container=container or "external-dns"),
            ),
        ],
        "params": params,
        "title": tools.title_with_actions,
        "verbosity": 2,
    }

    yield {
        "name": "nginx",
        "actions": [
            _kubectl(
                "logs",
                namespace=NAMESPACE,
                selector="app.kubernetes.io/name=nginx-gateway-fabric",
                **options,
                **_gen_extra(container=container or "nginx"),
            ),
        ],
        "params": params,
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


@task.with_params(
    [
        {
            "name": "command",
            "long": "command",
            "short": "c",
            "type": list,
            "default": [],
            "help": "Command to execute in container.",
        },
        {
            "name": "shell",
            "long": "shell",
            "short": "s",
            "type": str,
            "default": "/bin/sh",
            "help": "Path to or name of shell executable.",
        },
    ]
)
def shell(command: list[str], shell: str = "/bin/sh") -> Generator[dict, None, None]:
    command = command or [shell, "--interactive", "--login"]
    yield {
        "name": "nginx",
        "actions": [
            tools.Interactive(
                _kubectl(
                    "exec",
                    "deployment/nginx-gateway",
                    "--",
                    *command,
                    container="nginx",
                    namespace=NAMESPACE,
                    stdin=True,
                    tty=True,
                ),
            ),
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
            _kubectl("describe", "certificate", namespace="cert-manager-test"),
            clean_cert_manager,
        ],
        "clean": [clean_cert_manager],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }

    certificate_testfile = Path("tests/test-certificate.yaml")
    assert certificate_testfile.exists()
    clean_certificate = _kubectl("delete", filename=certificate_testfile)
    yield {
        "name": "certificate",
        "actions": [
            _kubectl("apply", filename=certificate_testfile),
            "sleep 10",
            _kubectl("describe", filename=certificate_testfile),
            clean_certificate,
        ],
        "clean": [clean_certificate],
        "title": tools.title_with_actions,
        "verbosity": 2,
    }

    for subtask in shell(command=["nginx", "-T"]):
        if subtask.pop("name") == "nginx-gateway":
            subtask["name"] = "nginx-config"
            yield subtask
            break


class LogsExtra(TypedDict, total=False):
    all_containers: bool
    container: str


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
    return f"kubectl {command} {opt_params} {pos_params}"


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
        return json.dumps(str(value) if isinstance(value, Path) else value)

    optionized = (
        (fix_optname(name), fix_optvalue(value)) for name, value in options.items()
    )
    return " ".join(
        name if value is None else f"{name}={value}" for name, value in optionized
    )
