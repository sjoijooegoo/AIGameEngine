"""Reusable real-engine assertions for adapters, checkpoint continuity and animation time."""
import json
from lab import Client, atomic_json


def close_numeric(actual, expected, path="state"):
    if isinstance(expected, dict):
        for key, value in expected.items():
            # Physics contact caches are recomputed by Godot; not serialized gameplay state.
            if key != "on_floor":
                close_numeric(actual[key], value, path + "." + key)
    elif isinstance(expected, list):
        assert len(actual) == len(expected), path
        for i, value in enumerate(expected):
            close_numeric(actual[i], value, path + f"[{i}]")
    elif isinstance(expected, (int, float)) and not isinstance(expected, bool):
        assert abs(actual - expected) < 0.002, f"{path}: {actual} != {expected}"
    else:
        assert actual == expected, f"{path}: {actual} != {expected}"


def snapshot_restore_replay(client):
    client.call("reset", fixture="npc_chase", seed=731)
    client.call("step", frames=135)
    before = client.call("state")
    assert before["npc"]["cooldown"] > 0, "Fixture must checkpoint mid-attack cooldown"
    client.call("checkpoint", name="combat_checkpoint")
    expected = client.call("step", frames=95)
    # Change everything that a partial restore might accidentally inherit.
    client.call("reset", fixture="npc_occluded", seed=99)
    client.call("step", frames=24)
    restored = client.call("restore", name="combat_checkpoint")
    close_numeric(restored, before)
    actual = client.call("step", frames=95)
    close_numeric(actual, expected)
    return "Cooldown, home/target, velocity, animation and subsequent damage match after restore"


def invalid_checkpoint_is_atomic(client):
    client.call("reset")
    result = client.call("checkpoint", name="invalid_checkpoint")
    path = client.session / "invalid_checkpoint.checkpoint.json"
    valid = json.loads(path.read_text(encoding="utf-8"))
    before = result["state"]
    for field in ("build_id", "game_id", "payload"):
        corrupted = json.loads(json.dumps(valid))
        if field == "payload":
            corrupted["payload"]["player"]["hp"] = 1
            corrupted["payload"]["npc"]["home"] = [0]
        else:
            corrupted[field] = "different"
        atomic_json(path, corrupted)
        try:
            client.call("restore", name="invalid_checkpoint")
        except RuntimeError:
            pass
        else:
            raise AssertionError("Invalid checkpoint was accepted")
        close_numeric(client.call("state"), before)
    return "Corrupt/mismatched checkpoints are rejected before mutation"


def adapter_contract():
    client = Client.launch(rendered=False, scene="probe")
    try:
        description = client.call("describe")
        assert description["game_id"] == "counter_probe"
        client.call("reset", seed=41)
        client.call("act", keys=["SPACE"], frames=2)
        client.call("checkpoint", name="rng")
        expected = client.call("act", keys=["SPACE"], frames=2)
        client.call("act", keys=["SPACE"], frames=2)
        client.call("restore", name="rng")
        actual = client.call("act", keys=["SPACE"], frames=2)
        assert actual == expected, "RNG continuation differs"
        client.call("reset", seed=41)
        client.call("act", keys=["SPACE"], frames=2)
        assert client.call("act", keys=["SPACE"], frames=2) == expected
        for command in ("view", "animation"):
            try:
                client.call(command)
            except RuntimeError:
                pass
            else:
                raise AssertionError("Unsupported capability was accepted")
        return "Second independent world; alternate key mapping; seeded RNG restore and unsupported capabilities verified"
    finally:
        client.close()


def animation_time_control(client):
    client.call("reset")
    sample = client.call("animation", entity="player", clip="walk", time=0.25)
    assert abs(sample["player"]["animation"]["time"] - 0.25) < 0.0001
    sample = client.call("step", frames=15)
    assert abs(sample["player"]["animation"]["time"] - 0.5) < 0.0001
    client.call("checkpoint", name="animation_pose")
    client.call("step", frames=10)
    restored = client.call("restore", name="animation_pose")
    assert abs(restored["player"]["animation"]["time"] - 0.5) < 0.0001
    client.call("reset")
    return "AnimationPlayer seek, manual advance and pose restore verified"


def save_load_continuity(client):
    client.call("reset", fixture="npc_chase")
    client.call("step", frames=135)
    client.call("act", keys=["ESC"], frames=1)
    saved = client.call("state")
    client.call("click", control="save")
    client.call("click", control="resume")
    expected = client.call("step", frames=95)
    client.call("act", keys=["ESC"], frames=1)
    loaded = client.call("click", control="load")
    # Loading adds a diagnostic event; compare gameplay data and timers.
    for field in ("player", "npc", "inventory", "tick", "paused"):
        close_numeric(loaded[field], saved[field], field)
    client.call("click", control="resume")
    actual = client.call("step", frames=95)
    for field in ("player", "npc", "inventory", "tick"):
        close_numeric(actual[field], expected[field], field)
    return "Actual save/load GUI preserves NPC cooldown and future combat, using atomic save replacement"
