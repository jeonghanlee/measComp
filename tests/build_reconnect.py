"""Build the real Linux IOC used by the reconnect transport test."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for option, variable in (("base", "BASE"), ("asyn", "ASYN"),
                             ("uldaq-include", "ULDAQ_INCLUDE"),
                             ("uldaq-lib", "ULDAQ_LIB"), ("build", "BUILD")):
        default = os.environ.get(variable)
        parser.add_argument("--" + option, type=Path, default=default, required=not default)
    parser.add_argument("--arch", default="linux-x86_64")
    args = parser.parse_args()
    source = Path(__file__).resolve().parent
    repository = source.parent
    build = args.build.resolve()
    build.mkdir(parents=True, exist_ok=False)
    base, asyn = args.base.resolve(), args.asyn.resolve()
    include, library = args.uldaq_include.resolve(), args.uldaq_lib.resolve()
    binaries = base / "bin" / args.arch
    dbd = build / "reconnect.dbd"
    registrar = build / "reconnect_register.cpp"
    definition = build / "reconnectInclude.dbd"
    definition.write_text('include "base.dbd"\ninclude "asyn.dbd"\nregistrar(drvMultiFunctionRegister)\n')
    sources = [source / "reconnect_ioc.cpp", registrar,
               repository / "measCompApp/src/drvMultiFunction.cpp",
               repository / "measCompApp/src/measCompDiscover.cpp"]
    includes = [base / "include", base / "include/os/Linux", base / "include/compiler/gcc",
                asyn / "include", include, repository / "measCompApp/src"]
    libraries = [asyn / "lib" / args.arch, base / "lib" / args.arch, library]
    commands = [
        ["perl", str(binaries / "dbdExpand.pl"), "-I", str(base / "dbd"),
         "-I", str(asyn / "dbd"), "-o", str(dbd), str(definition)],
        ["perl", str(binaries / "registerRecordDeviceDriver.pl"), "-o", str(registrar),
         str(dbd), "review_registerRecordDeviceDriver"],
        ["g++", "-std=gnu++11", "-O0", "-g", "-Wno-write-strings"] +
        ["-I" + str(path) for path in includes] + [str(path) for path in sources] +
        ["-L" + str(path) for path in libraries] +
        ["-Wl,-rpath," + str(path) for path in libraries] +
        ["-lasyn", "-ldbRecStd", "-ldbCore", "-lca", "-lCom", "-luldaq", "-lpthread",
         "-o", str(build / "reconnect-ioc")]]
    (build / "commands.json").write_text(json.dumps(commands, indent=2) + "\n")
    with (build / "build.log").open("w") as log:
        for command in commands:
            subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
    members = sources + [repository / "measCompApp/src/measCompDiscover.h",
        repository / "measCompApp/Db/measCompTemperatureIn.template",
        source / "test_reconnect.py", source / "tc32_simulator.py", Path(__file__).resolve(),
        asyn / "include/asynDriver.h", include / "uldaq.h", library / "libuldaq.so"]
    hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in members}
    (build / "inputs.json").write_text(json.dumps(hashes, indent=2) + "\n")
    print(build / "reconnect-ioc")


if __name__ == "__main__":
    main()
