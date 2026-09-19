"""Read-only Body ECU inspection; generated bindings live outside env."""

from functools import lru_cache
from pathlib import Path
import importlib
import sys
import tempfile


@lru_cache(maxsize=1)
def _bindings():
    from grpc_tools import protoc

    proto_dir = Path(__file__).resolve().parents[3] / "env" / "proto"
    generated = tempfile.TemporaryDirectory(prefix="vehicle-robot-proto-")
    result = protoc.main([
        "protoc", f"-I{proto_dir}", f"--python_out={generated.name}",
        f"--grpc_python_out={generated.name}", str(proto_dir / "vehicle_ecu.proto"),
    ])
    if result:
        generated.cleanup()
        raise RuntimeError(f"Could not generate Body ECU bindings: protoc exit {result}")
    sys.path.insert(0, generated.name)
    try:
        pb = importlib.import_module("vehicle_ecu_pb2")
        rpc = importlib.import_module("vehicle_ecu_pb2_grpc")
    finally:
        sys.path.remove(generated.name)
    return pb, rpc, generated


def get_body_ecu_state(address: str):
    import grpc

    pb, rpc, _ = _bindings()
    with grpc.insecure_channel(address) as channel:
        state = rpc.BodyControlStub(channel).GetBodyState(pb.StateRequest(), timeout=2)
    return {
        "doors_locked": state.doors_locked,
        "climate_active": state.climate.active,
        "target_temp_c": state.climate.target_temp_raw / 2.0,
        "charging_state": pb.ChargingState.Name(state.charging.state),
    }
