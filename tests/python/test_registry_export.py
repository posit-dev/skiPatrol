"""
registry_export_model: the SDK needs an ExportMode enum and an existing target
directory. R sends a plain string and a path that may not exist yet. Before the
fix, sfr_export_model() failed with "'str' object has no attribute 'value'".
"""
from unittest import mock

import pytest

import sfr_registry_bridge as b


class _FakeVersion:
    def __init__(self):
        self.calls = []

    def export(self, target_path, *, export_mode):
        self.calls.append((target_path, export_mode))


def _export(tmp_path, mode):
    fake = _FakeVersion()
    target = tmp_path / "new" / "dir"          # does not exist yet
    with mock.patch.object(b, "_get_model_version", return_value=(None, None, fake)):
        b.registry_export_model(None, "M", "V1", str(target), export_mode=mode)
    return fake, target


def test_string_mode_becomes_enum_and_directory_is_created(tmp_path):
    from snowflake.ml.model import ExportMode

    fake, target = _export(tmp_path, "model")
    assert target.is_dir()
    assert fake.calls == [(str(target), ExportMode.MODEL)]


def test_mode_is_case_insensitive_and_full_is_accepted(tmp_path):
    from snowflake.ml.model import ExportMode

    fake, _ = _export(tmp_path, "FULL")
    assert fake.calls[0][1] is ExportMode.FULL


def test_unknown_mode_names_the_valid_ones(tmp_path):
    with pytest.raises(ValueError, match="'model', 'full'"):
        _export(tmp_path, "everything")
