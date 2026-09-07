"""
Regression tests for backlog DB-4/U4: shared-session defect sweep.

Positron/Workbench keep this Python process alive across multiple
sfr_connect() calls, each producing a distinct Snowpark session -- unlike
the Jupyter per-kernel model these bridges were originally tested against.
A bare module-global cache (no session in the key) silently keeps serving
state bound to a previous, possibly disconnected session. These tests pin
the fix: every cache in the bridge layer must be keyed on session identity.
"""
from unittest import mock


def test_experiment_tracking_is_cached_per_session():
    import sfr_experiment_bridge as bridge
    bridge.reset_instance()

    session_a = object()
    session_b = object()

    with mock.patch("snowflake.ml.experiment.ExperimentTracking") as MockExp:
        MockExp.side_effect = lambda session: mock.Mock()

        exp_a1 = bridge._get_or_create_exp(session_a)
        exp_a2 = bridge._get_or_create_exp(session_a)
        exp_b = bridge._get_or_create_exp(session_b)

    assert exp_a1 is exp_a2, "same session must reuse the cached instance"
    assert exp_a1 is not exp_b, (
        "a different session must not reuse another session's instance"
    )
    assert MockExp.call_count == 2

    bridge.reset_instance()


def test_feature_store_is_cached_per_session():
    import sfr_features_bridge as bridge
    bridge._fs_cache.clear()

    session_a = object()
    session_b = object()

    with mock.patch("snowflake.ml.feature_store.FeatureStore") as MockFS, \
            mock.patch("snowflake.ml.feature_store.CreationMode") as MockMode:
        MockMode.FAIL_IF_NOT_EXIST = "FAIL_IF_NOT_EXIST"
        MockFS.side_effect = lambda **kwargs: mock.Mock()

        fs_a1 = bridge._get_feature_store(session_a, "DB", "SC", "WH")
        fs_a2 = bridge._get_feature_store(session_a, "DB", "SC", "WH")
        fs_b = bridge._get_feature_store(session_b, "DB", "SC", "WH")

    assert fs_a1 is fs_a2, "same session must reuse the cached FeatureStore"
    assert fs_a1 is not fs_b, (
        "a different session must not reuse another session's FeatureStore, "
        "even with identical database/schema/warehouse"
    )
    assert MockFS.call_count == 2

    bridge._fs_cache.clear()


def test_dataset_cache_is_scoped_by_session():
    import sfr_features_bridge as bridge
    bridge._DATASET_CACHE.clear()

    session_a = object()
    session_b = object()
    ds = mock.Mock()

    bridge._DATASET_CACHE[(session_a, "NAME", "V1")] = ds

    assert bridge.get_cached_dataset(session_a, "NAME", "V1") is ds
    assert bridge.get_cached_dataset(session_b, "NAME", "V1") is None, (
        "a dataset cached under one session must not be handed back to a "
        "lookup from a different session, even with the same name:version"
    )

    bridge._DATASET_CACHE.clear()
