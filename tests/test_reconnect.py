"""Exercise real IOC/asyn/ULDAQ code with the network device boundary fixture."""
import json
from pathlib import Path
import queue
import subprocess
import sys
import threading
import time

from tc32_simulator import TC32


def main():
    executable, dbd, template, log_path = sys.argv[1:]
    device = TC32()
    output = queue.Queue()
    checks = []
    process = subprocess.Popen([executable, dbd, template, device.address],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True, bufsize=1)
    log = open(log_path, "w")

    def collect():
        for line in process.stdout:
            log.write(line)
            log.flush()
            output.put(line.rstrip())

    reader = threading.Thread(target=collect, daemon=True)
    reader.start()

    def read(prefix, timeout=8):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            line = output.get(timeout=max(0.01, deadline-time.monotonic()))
            if line.startswith(prefix):
                return line
        raise TimeoutError(prefix)

    def command(line, prefix="RESULT"):
        process.stdin.write(line + "\n")
        process.stdin.flush()
        return read(prefix)

    def state():
        values = command("STATE", "STATE").split()[1:]
        return dict(zip(("connected", "auto", "enabled", "pact", "udf", "severity", "value",
                         "severity31", "value31"), map(float, values)))

    def wait_for(predicate, timeout=12):
        deadline = time.monotonic() + timeout
        observed = None
        while time.monotonic() < deadline:
            observed = state()
            if predicate(observed):
                return observed
            time.sleep(0.1)
        raise AssertionError(f"deadline exceeded; last state={observed}; simulator errors={device.errors}")

    def check(name, condition, evidence):
        checks.append({"name": name, "passed": bool(condition), "evidence": evidence})
        print(json.dumps(checks[-1]), flush=True)
        if not condition:
            raise AssertionError(name)

    def healthy(value):
        return wait_for(lambda s: s["connected"] == 1 and s["severity"] == 0 and
                        s["udf"] == 0 and abs(s["value"]-value) < 0.001 and
                        s["severity31"] == 0 and abs(s["value31"]-value) < 0.001)

    try:
        read("READY")
        initial = state()
        check("offline record initialized", initial["pact"] == 0 and initial["connected"] == 0 and
              initial["auto"] == 1 and initial["severity"] == 3, initial)
        device.online = True
        check("offline startup recovers", True, healthy(22.5))
        check("TC configuration write", command("TC 2") == "RESULT 0", device.types[0])
        check("bank configuration write", command("OTD31 0") == "RESULT 0", device.measure.hex())
        check("open detection write", command("OTD 1") == "RESULT 0", device.measure.hex())
        check("settings reached device", device.types[0] == 2 and not (device.measure[0] & 1),
              {"tc": device.types[0], "measurement": device.measure.hex()})

        for mode, command_id in (("eof", 0x12), ("short", 0x00), ("timeout", 0x12)):
            baseline = state()
            device.fault = (command_id, mode)
            failed = wait_for(lambda s: s["connected"] == 0 and s["severity"] == 3 and s["severity31"] == 3)
            check(mode + " preserves last valid value", abs(failed["value"]-baseline["value"]) < 0.001 and
                  abs(failed["value31"]-baseline["value31"]) < 0.001, failed)
            check(mode + " reached transport", device.fault is None and device.faults[-1][1] == mode,
                  device.faults[-1])
            if mode == "timeout":
                elapsed = time.monotonic() - device.faults[-1][2]
                check("timeout before fixture closes socket", 3 <= elapsed < 10, elapsed)
            device.types = bytes([1] * 64)
            device.measure = b"\x01\x01"
            device.temperature += 1.25
            device.online = True
            check(mode + " reconnects", True, healthy(device.temperature))
            check(mode + " restores settings", device.types[0] == 2 and not (device.measure[0] & 1),
                  {"tc": device.types[0], "measurement": device.measure.hex()})

        check("disable autoconnect", command("AUTO 0") == "RESULT 0", "AUTO 0")
        device.fault = (0x00, "eof")
        wait_for(lambda s: s["connected"] == 0 and s["severity"] == 3)
        connections = device.connections
        device.online = True
        deadline = time.monotonic() + 6
        while time.monotonic() < deadline:
            s = state()
            if s["connected"] != 0:
                raise AssertionError("autoconnect disabled but connected")
            time.sleep(0.1)
        check("autoconnect off prevents retries", device.connections == connections, device.connections)
        check("enable autoconnect", command("AUTO 1") == "RESULT 0", "AUTO 1")
        check("autoconnect on recovers", True, healthy(device.temperature))

        check("disable port", command("ENABLE 0") == "RESULT 0", "ENABLE 0")
        # An already running poll may finish after the administrative flag changes.
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            requests = device.requests
            time.sleep(0.1)
            if device.requests == requests:
                break
        requests = device.requests
        time.sleep(0.5)
        check("disabled port stops polling", device.requests == requests, device.requests)
        check("enable port", command("ENABLE 1") == "RESULT 0", "ENABLE 1")
        device.temperature += 1.25
        check("enabled port resumes polling", True, healthy(device.temperature))
        check("fixture commands supported", not device.errors, device.errors)
        process.stdin.write("QUIT\n")
        process.stdin.flush()
        check("IOC exits normally", process.wait(timeout=5) == 0, process.returncode)
        return 0
    finally:
        device.close()
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=5)
        reader.join(timeout=5)
        Path(log_path + ".json").write_text(json.dumps({"checks": checks, "faults": device.faults,
            "fixture_errors": device.errors, "ioc_exit": process.returncode}, indent=2) + "\n")
        log.close()


if __name__ == "__main__":
    raise SystemExit(main())
