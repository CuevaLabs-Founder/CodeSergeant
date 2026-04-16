"""Unit tests for configuration helpers."""

import inspect

from code_sergeant import config as config_module


def test_set_env_var_defaults_to_repo_env_file():
    """Secrets should default to the repo-root .env file, not cwd-relative paths."""
    signature = inspect.signature(config_module.set_env_var)
    assert signature.parameters["env_path"].default == str(config_module._ENV_FILE)
