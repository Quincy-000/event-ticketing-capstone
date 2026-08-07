"""
tests/conftest.py

One real gotcha this project runs into: both Lambda handlers are named
`handler.py`, but they live in different folders. If two test files both
did `import handler`, Python's module cache would only keep ONE of them.
This helper loads each handler.py by its exact file path instead.
"""

import importlib.util
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent


def load_handler(folder_name: str):
    """Load lambdas/<folder_name>/handler.py as a uniquely-named module."""
    path = PROJECT_ROOT / "lambdas" / folder_name / "handler.py"
    module_name = f"{folder_name}_handler"
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module
