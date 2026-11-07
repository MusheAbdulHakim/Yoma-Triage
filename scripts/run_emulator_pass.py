#!/usr/bin/env python3
"""Rerun the Yoma Triage emulator pass with one command.

    python3 scripts/run_emulator_pass.py                     # both AVDs, all scenarios
    python3 scripts/run_emulator_pass.py --avd yoma_api34 --scenarios 1 3 4

Boots each AVD, starts a throwaway Postgres and a development-mode backend with mock SMS
(no live Africa's Talking traffic), and runs mobile/integration_test on the device.
Results and screenshots go to mobile/build/emulator_pass/<avd>/.

Scenario 2 and the cold-start timings use a release APK driven through adb, not
integration_test, so they exercise exactly what would be installed.

Needs: Flutter 3.44.8 (YOMA_FLUTTER, default ~/flutter-3.44.8/bin/flutter), the Android SDK
(ANDROID_HOME, default ~/Android/sdk), PostgreSQL's initdb, and a Python with
requirements.txt installed (YOMA_PYTHON, default ~/.cache/yoma-emulator/venv/bin/python).
"""

from __future__ import annotations

import argparse
import contextlib
import glob
import json
import os
import re
import shutil
import signal
import statistics
import subprocess
import sys
import tempfile
import threading
import time
import traceback
import urllib.parse
import xml.etree.ElementTree as ET
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
MOBILE = REPO / "mobile"
HOME = Path.home()
FLUTTER = os.environ.get("YOMA_FLUTTER", str(HOME / "flutter-3.44.8/bin/flutter"))
SDK = Path(os.environ.get("ANDROID_HOME") or HOME / "Android/sdk")
ADB = str(SDK / "platform-tools/adb")
EMULATOR = str(SDK / "emulator/emulator")
PYTHON = os.environ.get("YOMA_PYTHON", str(HOME / ".cache/yoma-emulator/venv/bin/python"))
PACKAGE = "gh.yomatriage.yoma_triage"
ACTIVITY = f"{PACKAGE}/.MainActivity"
HARNESS_PORT = 8765
BACKEND_PORT = 8000
PG_PORT = 55490
TEST_CHO = "+233240000777"
SMALL_WIDTH_PX, SMALL_HEIGHT_PX, SMALL_DENSITY = 640, 1136, 320  # 320 x 568 dp

AVDS = {"yoma_api34": 5554, "yoma_api24_2gb": 5556}

# What each integration test file needs from the backend, and from the build.
SCENARIOS: dict[str, dict] = {
    "1": {"file": "s1_yamnet_test.dart", "defines": {"MOEWS_ONLY": "false"}},
    "3": {"file": "s3_setup_test.dart"},
    "4": {"file": "s4_full_referral_test.dart"},
    "5": {"file": "s5_skip_vitals_test.dart"},
    "6": {"file": "s6_offline_test.dart"},
    "7": {"file": "s7_stale_test.dart", "env": {"STALE_AFTER_MINUTES": "1"}},
    "8": {"file": "s8_restart_test.dart", "env": {"CASCADE_TIER_SECONDS": "30"}},
    "banners": {"file": "s9_home_banners_test.dart"},
    # The same test at the device's own size. It can fail there too: that's a finding.
    "banners_native": {"file": "s9_home_banners_test.dart"},
}
SMALL_SCREEN_SCENARIOS = ["3", "4", "5", "6", "7", "banners"]

# Read-only views the tests may ask for.
QUERIES = {
    "outbox": "select id, recipient, purpose, status, body, attempts, dispatch_id "
    "from outbound_messages order by id",
    "referrals": "select id, status, cho_id, queue_age_seconds, vitals_json::text as vitals_json, "
    "patient_hash, emergency_type from referrals order by id",
    "dispatches": "select id, referral_id, status, current_tier, driver_id from dispatches order by id",
    "audit": "select entity_type, entity_id, action from audit_logs order by id",
}


def log(message: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {message}", flush=True)


def run(cmd: list[str], *, check: bool = True, timeout: float = 120, **kwargs) -> str:
    done = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, **kwargs)
    if check and done.returncode != 0:
        raise RuntimeError(f"{' '.join(cmd)}\n{done.stdout}\n{done.stderr}")
    return done.stdout


class Device:
    def __init__(self, avd: str) -> None:
        self.avd = avd
        self.port = AVDS[avd]
        self.serial = f"emulator-{self.port}"
        self.process: subprocess.Popen | None = None
        self.api = 0
        self.out = MOBILE / "build/emulator_pass" / avd
        self.out.mkdir(parents=True, exist_ok=True)
        saved = self.out / "results.json"
        if saved.exists():
            RESULTS[avd] = json.loads(saved.read_text())

    def adb(self, *args: str, check: bool = True, timeout: float = 60) -> str:
        return run([ADB, "-s", self.serial, *args], check=check, timeout=timeout)

    def shell(self, command: str, check: bool = False, timeout: float = 60) -> str:
        return self.adb("shell", command, check=check, timeout=timeout)

    def boot(self) -> None:
        running = f"{self.serial}\tdevice" in run([ADB, "devices"])
        log(f"{'Reusing' if running else 'Booting'} {self.avd}")
        if running:
            self.process = None
        else:
            # The emulator keeps its own copy of the file handle.
            with open(self.out / "emulator.log", "w") as emulator_log:
                self.process = subprocess.Popen(
                    [
                        EMULATOR,
                        "-avd",
                        self.avd,
                        "-port",
                        str(self.port),
                        "-no-window",
                        "-no-audio",
                        "-no-boot-anim",
                        "-no-snapshot",
                        "-gpu",
                        "swiftshader_indirect",
                    ],
                    stdout=emulator_log,
                    stderr=subprocess.STDOUT,
                )
        self.wait_booted()
        self.api = int(self.shell("getprop ro.build.version.sdk").strip())
        if self.api < 30:
            # Before `cmd connectivity`, only root can change airplane mode.
            self.adb("root")
            time.sleep(2)
            self.adb("wait-for-device")
            self.wait_booted()
        self.shell("settings put global window_animation_scale 0")
        self.shell("settings put global transition_animation_scale 0")
        self.shell("settings put global animator_duration_scale 0")
        # An "isn't responding" dialog would sit over every screenshot.
        self.shell("settings put global hide_error_dialogs 1")
        # The verifier can hold an adb install on an old image for many minutes.
        self.shell("settings put global verifier_verify_adb_installs 0")
        self.shell("settings put global package_verifier_enable 0")
        self.keep_awake()
        self.reverse()
        self.reset_screen()
        self.record_details()
        self.settle()

    def settle(self, seconds: float = 150) -> None:
        """A fresh boot keeps optimising for minutes, and tests shouldn't compete with it."""
        deadline = time.time() + seconds
        while time.time() < deadline:
            load = float(self.shell("cat /proc/loadavg").split()[0] or 99)
            if load < 2.5:
                break
            time.sleep(5)
        log(f"Settled: {self.shell('cat /proc/loadavg').strip()}")

    def wait_booted(self) -> None:
        deadline = time.time() + 300
        while time.time() < deadline:
            if (
                self.shell("getprop sys.boot_completed").strip() == "1"
                # An install right after boot can hang until the package manager is up.
                and "package:" in self.shell("pm path android")
            ):
                return
            time.sleep(2)
        raise RuntimeError(f"{self.avd} did not boot")

    def keep_awake(self) -> None:
        self.shell("svc power stayon true")
        self.shell("input keyevent KEYCODE_WAKEUP")
        self.shell("wm dismiss-keyguard")

    def reverse(self) -> None:
        self.adb("reverse", f"tcp:{HARNESS_PORT}", f"tcp:{HARNESS_PORT}")

    def reset_screen(self) -> None:
        """Back to the device's own size. A reset just before shutdown can be lost, and would
        then leave the next run on the small profile, so this also runs at boot and is checked.
        """
        for _ in range(5):
            self.shell("wm size reset")
            self.shell("wm density reset")
            time.sleep(2)
            if "Override" not in self.shell("wm size") + self.shell("wm density"):
                self.shell("sync")
                return
        raise RuntimeError(f"{self.avd} is still on an overridden screen size")

    def record_details(self) -> None:
        memory = self.shell("cat /proc/meminfo").splitlines()[0]
        RESULTS.setdefault(self.avd, {})["device"] = {
            "avd": self.avd,
            "api": self.api,
            "abi": self.shell("getprop ro.product.cpu.abi").strip(),
            "memory": " ".join(memory.split()),
            "screen": self.shell("wm size").strip(),
            "density": self.shell("wm density").strip(),
            "model": self.shell("getprop ro.product.model").strip(),
        }

    def shutdown(self) -> None:
        if KEEP_RUNNING[0]:
            return
        run([ADB, "-s", self.serial, "emu", "kill"], check=False)
        if self.process:
            try:
                self.process.wait(timeout=30)
            except subprocess.TimeoutExpired:
                self.process.kill()

    def airplane(self, on: bool) -> dict:
        word = "enable" if on else "disable"
        if self.api >= 30:
            self.shell(f"cmd connectivity airplane-mode {word}")
        else:
            self.shell(f"settings put global airplane_mode_on {1 if on else 0}")
            self.shell(
                "am broadcast -a android.intent.action.AIRPLANE_MODE "
                f"--ez state {'true' if on else 'false'}"
            )
        # Confirm from the device itself, so a test can't pass while still online.
        deadline = time.time() + 45
        while time.time() < deadline:
            reachable = " 0% packet loss" in self.shell("ping -c 1 -W 2 10.0.2.2")
            if reachable != on:
                return {"airplane": on, "host_reachable": reachable}
            time.sleep(1)
        raise RuntimeError(f"Airplane mode {word}: host reachable is still {not on}")

    def screenshot(self, name: str) -> str:
        path = self.out / f"{SCREEN_PREFIX[0]}{name}.png"
        with open(path, "wb") as file:
            subprocess.run(
                [ADB, "-s", self.serial, "exec-out", "screencap", "-p"],
                stdout=file,
                check=True,
                timeout=60,
            )
        return str(path)

    def dump(self) -> list[dict]:
        """What's on screen, through Android's accessibility tree."""
        for _ in range(5):
            self.shell("rm -f /sdcard/u.xml")
            self.shell("uiautomator dump /sdcard/u.xml", timeout=60)
            raw = self.shell("cat /sdcard/u.xml", timeout=30)
            if "<hierarchy" in raw:
                root = ET.fromstring(raw[raw.index("<hierarchy") :])
                return [dict(n.attrib) for n in root.iter("node")]
            time.sleep(1)
        return []

    def install(self, apk: Path) -> None:
        """Replaces whatever is there. An install can hang on the small emulator, so retry."""
        for attempt in range(3):
            self.adb("uninstall", PACKAGE, check=False, timeout=120)
            try:
                self.adb("install", str(apk), timeout=240)
                return
            except subprocess.TimeoutExpired:
                log(f"  adb install hung (attempt {attempt + 1}). Reconnecting.")
                run([ADB, "-s", self.serial, "reconnect"], check=False)
                time.sleep(10)
                self.wait_booted()
                self.reverse()
        raise RuntimeError(f"Could not install {apk}")

    def foreground(self) -> str:
        """The app on top, from the same accessibility read as the text a check then looks at."""
        nodes = self.dump()
        return nodes[0].get("package", "") if nodes else ""

    def external_app(self, name: str) -> dict:
        """Report the app Call or SMS opened, photograph it, and return to Yoma."""
        deadline = time.time() + 25
        package = PACKAGE
        while time.time() < deadline:
            package = self.foreground()
            if package and package != PACKAGE:
                break
            time.sleep(0.5)
        time.sleep(3)
        nodes = self.dump()
        # With two SMS apps, Android asks which to use. A real phone can do this too.
        if find_node(nodes, "Open with"):
            self.screenshot(f"{name}_chooser")
            record("notes", "Android showed an 'Open with' chooser for the SMS button")
            choice = find_node(nodes, "Messenger") or find_node(nodes, "Messages")
            if choice:
                tap_node(self, choice)
                time.sleep(1)
            once = find_node(self.dump(), "JUST ONCE") or find_node(self.dump(), "Just once")
            if once:
                tap_node(self, once)
            time.sleep(4)
            package = self.foreground()
            nodes = self.dump()
            # First run of Messenger on an old image can show its own welcome screen.
            for label in ("SKIP", "Skip", "NOT NOW", "Not now", "OK", "ALLOW"):
                node = find_node(nodes, label, exact=True)
                if node:
                    tap_node(self, node)
                    time.sleep(3)
                    nodes = self.dump()
        text = " | ".join(n["text"] for n in nodes if n.get("text"))
        self.screenshot(name)
        for _ in range(3):
            if self.foreground() == PACKAGE:
                break
            self.shell("input keyevent KEYCODE_BACK")
            time.sleep(1.2)
        self.shell(f"am start -n {ACTIVITY}")
        time.sleep(1.5)
        return {"package": package, "text": text}


class Backend:
    """A throwaway Postgres, reset for each test, and the real app in development mode."""

    def __init__(self) -> None:
        self.dir = tempfile.mkdtemp(prefix="yoma-emulator-pg-")
        self.pg_bin = Path(sorted(glob.glob("/usr/lib/postgresql/*/bin"))[-1])
        self.process: subprocess.Popen | None = None
        self.extra_env: dict[str, str] = {}
        self.log_path = Path(self.dir) / "server.log"
        run(
            [
                str(self.pg_bin / "initdb"),
                "-D",
                f"{self.dir}/c",
                "-U",
                "postgres",
                "--auth=trust",
                "-E",
                "UTF8",
            ]
        )
        run(
            [
                str(self.pg_bin / "pg_ctl"),
                "-D",
                f"{self.dir}/c",
                "-o",
                f"-p {PG_PORT} -k {self.dir} -c listen_addresses=127.0.0.1",
                "-l",
                f"{self.dir}/pg.log",
                "-w",
                "start",
            ]
        )

    @property
    def env(self) -> dict[str, str]:
        return {
            **os.environ,
            "DATABASE_URL": f"postgresql+asyncpg://postgres@127.0.0.1:{PG_PORT}/yoma",
            "ENVIRONMENT": "development",
            "PYTHONPATH": ".",
            "PYTHONDONTWRITEBYTECODE": "1",
            # Empty key: the gateway only logs "MOCK SMS". Nothing can reach Africa's Talking.
            "AT_API_KEY": "",
            "AT_USERNAME": "",
            "API_KEY": "",
            "AT_WEBHOOK_SECRET": "",
            "AT_USSD_SERVICE_CODE": "",
            **self.extra_env,
        }

    def psql(self, sql: str, database: str = "yoma") -> str:
        return run(
            [
                str(self.pg_bin / "psql"),
                "-h",
                "127.0.0.1",
                "-p",
                str(PG_PORT),
                "-U",
                "postgres",
                "-d",
                database,
                "-At",
                "-c",
                sql,
            ]
        )

    def reset(self, extra_env: dict[str, str] | None = None) -> None:
        self.kill()
        self.extra_env = extra_env or {}
        self.psql("drop database if exists yoma with (force)", "postgres")
        self.psql("create database yoma", "postgres")
        alembic = str(Path(PYTHON).parent / "alembic")
        run([alembic, "upgrade", "head"], cwd=REPO, env=self.env)
        run([PYTHON, "-m", "src.db.seed"], cwd=REPO, env=self.env)
        # The provisioning CLI, as an administrator would register a real CHO.
        run(
            [
                PYTHON,
                "-m",
                "src.admin.add_cho",
                "--name",
                "Emulator CHO",
                "--phone",
                TEST_CHO,
                "--compound-id",
                "1",
            ],
            cwd=REPO,
            env=self.env,
        )
        self.log_path.write_text("")
        self.start()

    def start(self) -> None:
        with open(self.log_path, "a") as output:
            self.process = subprocess.Popen(
                [
                    PYTHON,
                    "-m",
                    "uvicorn",
                    "main:app",
                    "--host",
                    "127.0.0.1",
                    "--port",
                    str(BACKEND_PORT),
                    "--log-level",
                    "info",
                ],
                cwd=REPO,
                env=self.env,
                stdout=output,
                stderr=subprocess.STDOUT,
            )
        deadline = time.time() + 30
        while time.time() < deadline:
            done = subprocess.run(
                ["curl", "-s", "-o", "/dev/null", f"http://127.0.0.1:{BACKEND_PORT}/"],
                capture_output=True,
            )
            if done.returncode == 0:
                return
            time.sleep(0.2)
        raise RuntimeError(f"Backend did not start:\n{self.log_path.read_text()[-2000:]}")

    def kill(self) -> None:
        """SIGKILL, because a crash gets no chance to tidy up."""
        if self.process and self.process.poll() is None:
            self.process.send_signal(signal.SIGKILL)
            self.process.wait(timeout=10)
        self.process = None

    def rows(self, name: str) -> list:
        sql = f"select coalesce(json_agg(t), '[]') from ({QUERIES[name]}) t"
        return json.loads(self.psql(sql))

    def stop(self) -> None:
        self.kill()
        run([str(self.pg_bin / "pg_ctl"), "-D", f"{self.dir}/c", "-m", "fast", "stop"], check=False)
        shutil.rmtree(self.dir, ignore_errors=True)


RESULTS: dict[str, dict] = {}
KEEP_RUNNING = [False]
SCREEN_PREFIX = [""]
CURRENT: dict = {"device": None, "backend": None, "scenario": ""}


def record(section: str, value) -> None:
    device = CURRENT["device"]
    entry = RESULTS.setdefault(device.avd, {}).setdefault(CURRENT["scenario"], {})
    if section == "metrics":
        entry.setdefault("metrics", {}).update(value)
    else:
        entry.setdefault(section, []).append(value)


def fixture_bytes(name: str) -> bytes | None:
    path = REPO / "data/lab_set/synthetic_smoke" / Path(name).name
    return path.read_bytes() if path.is_file() else None


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args) -> None:
        pass

    def _send(self, code: int, body: bytes, kind: str = "application/json") -> None:
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        url = urllib.parse.urlparse(self.path)
        query = {k: v[0] for k, v in urllib.parse.parse_qs(url.query).items()}
        try:
            if url.path.startswith("/fixture/"):
                data = fixture_bytes(url.path.removeprefix("/fixture/"))
                self._send(200 if data else 404, data or b"", "application/octet-stream")
                return
            result = self.route(url.path, query)
            self._send(200, json.dumps(result).encode())
        except Exception as exc:
            traceback.print_exc()
            self._send(500, str(exc).encode())

    def route(self, path: str, query: dict):
        device: Device = CURRENT["device"]
        backend: Backend = CURRENT["backend"]
        if path == "/screenshot":
            return {"path": device.screenshot(query["name"])}
        if path == "/airplane":
            return device.airplane(query["on"] == "1")
        if path == "/backend/kill":
            backend.kill()
            return {}
        if path == "/backend/start":
            backend.start()
            return {}
        if path == "/db":
            return backend.rows(query["q"])
        if path == "/external-app":
            return device.external_app(query["name"])
        if path == "/metric":
            record("metrics", {query["name"]: float(query["value"])})
            return {}
        if path == "/note":
            record("notes", query["text"])
            log(f"  note: {query['text']}")
            return {}
        if path == "/problem":
            record("problems", query["text"])
            log(f"  PROBLEM: {query['text']}")
            return {}
        if path == "/check-server-log":
            if query["contains"] not in backend.log_path.read_text():
                raise AssertionError(f"Not in the server log: {query['contains']}")
            record("notes", f"Server log has: {query['contains']}")
            return {}
        raise ValueError(f"Unknown harness route {path}")


def run_until_done(command: list[str], limit: float = 900) -> tuple[bool, str]:
    """`flutter test` can hang after a failure, so stop soon after the first one."""
    process = subprocess.Popen(
        command,
        cwd=MOBILE,
        stdout=subprocess.PIPE,
        text=True,
        stderr=subprocess.STDOUT,
        env={**os.environ, "CI": "true"},
    )
    lines: list[str] = []
    failed_at: list[float] = []

    def read() -> None:
        for line in process.stdout:
            lines.append(line)
            if line.rstrip().endswith("[E]") and not failed_at:
                failed_at.append(time.time())

    reader = threading.Thread(target=read, daemon=True)
    reader.start()
    started = time.time()
    while process.poll() is None:
        if time.time() - started > limit or (failed_at and time.time() - failed_at[0] > 45):
            process.kill()
            lines.append("\nSTOPPED BY THE RUNNER\n")
            break
        time.sleep(1)
    process.wait(timeout=30)
    reader.join(timeout=5)
    return process.returncode == 0, "".join(lines)


def run_integration(device: Device, scenario: str, *, small: bool = False) -> bool:
    spec = SCENARIOS.get(scenario) or {"file": scenario}
    label = f"s{scenario}{'_small' if small else ''}"
    CURRENT["scenario"] = label
    RESULTS.setdefault(device.avd, {})[label] = {}
    SCREEN_PREFIX[0] = "small_" if small else ""
    CURRENT["backend"].reset(spec.get("env"))
    device.adb("uninstall", PACKAGE, check=False)
    device.keep_awake()
    device.reverse()
    defines = {"API_BASE_URL": f"http://10.0.2.2:{BACKEND_PORT}", **spec.get("defines", {})}
    if small:
        defines["SMALL_SCREEN"] = "true"
    command = [
        FLUTTER,
        "test",
        f"integration_test/{spec['file']}",
        "-d",
        device.serial,
        "-r",
        "expanded",
    ]
    command += [f"--dart-define={k}={v}" for k, v in defines.items()]
    log(f"{device.avd} {label}: {spec['file']}")
    started = time.time()
    log_file = device.out / f"{label}.log"
    passed, output = run_until_done(command)
    if not passed and "Installing" in output and "+0" not in output.split("Installing")[-1]:
        log("  The install hung before any test ran. Retrying once.")
        device.adb("uninstall", PACKAGE, check=False, timeout=120)
        passed, output = run_until_done(command)
    log_file.write_text(output)
    if CURRENT["backend"].log_path.exists():
        shutil.copy(CURRENT["backend"].log_path, device.out / f"{label}.server.log")
    entry = RESULTS.setdefault(device.avd, {}).setdefault(label, {})
    entry["passed"] = passed
    entry["seconds"] = round(time.time() - started)
    log(f"  {'PASS' if passed else 'FAIL'} in {entry['seconds']} s (log: {log_file})")
    if not passed:
        failure = [
            line
            for line in output.splitlines()
            if "EXCEPTION" in line
            or "Expected:" in line
            or "Actual:" in line
            or "TestFailure" in line
            or "Timed out" in line
            or "Which:" in line
            or "Error:" in line
            or "FAILED" in line
            or "Exception" in line
        ]
        entry["failure"] = failure[:12]
        for line in failure[:12]:
            log(f"    {line[:170]}")
    with contextlib.suppress(RuntimeError):
        device.airplane(False)
    save_results(device)
    return passed


def save_results(device: Device) -> None:
    (device.out / "results.json").write_text(json.dumps(RESULTS.get(device.avd, {}), indent=2))


# --- Scenario 2 and cold start: the release APK, driven through adb -------------------


RELEASE_APK = MOBILE / "build/app/outputs/flutter-apk/app-release.apk"
DEMO_STRINGS = ["Demo Normal", "Demo Code Red", "Web demo simulator", "Stub classifier"]


def build_release() -> dict:
    log("Building release APK with MOEWS_ONLY=false")
    # Not --no-pub, here or below: the step it skips regenerates the plugin list, and a
    # release build fails if the list still names integration_test from a debug build.
    run(
        [
            FLUTTER,
            "build",
            "apk",
            "--release",
            "--dart-define=MOEWS_ONLY=false",
            f"--dart-define=API_BASE_URL=http://10.0.2.2:{BACKEND_PORT}",
        ],
        cwd=MOBILE,
        timeout=1800,
    )
    info = {
        "bytes": RELEASE_APK.stat().st_size,
        "megabytes": round(RELEASE_APK.stat().st_size / 1024 / 1024, 1),
    }
    listing = run(["unzip", "-l", str(RELEASE_APK)])
    largest = []
    for line in listing.splitlines():
        parts = line.split()
        if len(parts) == 4 and parts[0].isdigit():
            largest.append((int(parts[0]), parts[3]))
    info["largest"] = [
        f"{size / 1024 / 1024:.1f} MB {name}" for size, name in sorted(largest, reverse=True)[:12]
    ]
    # The strings a demo button or stub would need, in the compiled Dart of any ABI.
    found = {}
    with tempfile.TemporaryDirectory() as tmp:
        run(["unzip", "-q", "-o", str(RELEASE_APK), "lib/*/libapp.so", "-d", tmp])
        for lib in glob.glob(f"{tmp}/lib/*/libapp.so"):
            blob = Path(lib).read_bytes()
            for text in DEMO_STRINGS:
                found.setdefault(text, False)
                found[text] = found[text] or text.encode() in blob
    info["demo_strings_in_compiled_dart"] = found
    return info


def screen_text(nodes: list[dict]) -> str:
    return " | ".join(v for n in nodes for v in (n.get("text"), n.get("content-desc")) if v)


def find_node(nodes: list[dict], text: str, *, exact: bool = False) -> dict | None:
    for node in nodes:
        for value in (node.get("content-desc") or "", node.get("text") or ""):
            if (exact and value == text) or (not exact and text in value):
                return node
    return None


def tap_node(device: Device, node: dict) -> None:
    numbers = [int(v) for v in re.findall(r"\d+", node["bounds"])]
    x, y = (numbers[0] + numbers[2]) // 2, (numbers[1] + numbers[3]) // 2
    device.shell(f"input tap {x} {y}")


def wait_screen(device: Device, text: str, timeout: float = 45) -> list[dict]:
    deadline = time.time() + timeout
    while time.time() < deadline:
        nodes = device.dump()
        if find_node(nodes, text):
            return nodes
        time.sleep(0.5)
    raise RuntimeError(f"'{text}' never appeared. Screen: {screen_text(device.dump())[:600]}")


def tap_text(device: Device, text: str, timeout: float = 45) -> None:
    tap_node(device, find_node(wait_screen(device, text, timeout), text))


def release_setup(device: Device) -> None:
    device.shell(f"pm clear {PACKAGE}")
    device.shell(f"am start -n {ACTIVITY}")
    nodes = wait_screen(device, "Set up this phone", 90)
    field = next((n for n in nodes if n.get("class") == "android.widget.EditText"), None)
    if field is None:
        raise RuntimeError(f"No phone field. Screen: {screen_text(nodes)[:500]}")
    tap_node(device, field)
    time.sleep(1)
    device.shell(f"input text '{TEST_CHO}'")
    time.sleep(1)
    device.shell("input keyevent KEYCODE_BACK")
    time.sleep(1)
    tap_text(device, "Continue")
    wait_screen(device, "Community Health Officer", 45)


def tap_permission(device: Device, allow: bool) -> str:
    """Answer the system's permission dialog, if it asks."""
    deadline = time.time() + 20
    while time.time() < deadline:
        nodes = device.dump()
        ids = {n.get("resource-id", ""): n for n in nodes}
        names = (
            ["permission_allow_foreground_only_button", "permission_allow_button"]
            if allow
            else ["permission_deny_button", "permission_deny_and_dont_ask_again_button"]
        )
        for key, node in ids.items():
            if any(key.endswith(name) for name in names):
                tap_node(device, node)
                return key
        if find_node(nodes, "Hold phone near chest"):
            time.sleep(1)
            again = device.dump()
            if not any("permission" in n.get("resource-id", "") for n in again):
                return "no dialog"
        time.sleep(0.5)
    return "no dialog"


def to_result_screen(device: Device) -> None:
    """Mark every vital Not measured, which needs no typing, then continue to the result."""
    wait_screen(device, "Record Vitals", 90)
    for _ in range(10):
        boxes = [
            n for n in device.dump() if n.get("checkable") == "true" and n.get("checked") != "true"
        ]
        if not boxes:
            nodes = device.dump()
            if find_node(nodes, "AVPU"):
                break
        for box in boxes:
            tap_node(device, box)
            time.sleep(0.3)
        nodes = device.dump()
        if find_node(nodes, "AVPU") and not any(
            n.get("checkable") == "true" and n.get("checked") != "true" for n in nodes
        ):
            break
        device.shell("input swipe 300 1000 300 500 400")
        time.sleep(0.7)
    tap_node(device, find_node(device.dump(), "AVPU"))
    time.sleep(1)
    # The menu lists the options; its own "Not measured" is the last of them on screen.
    options = [
        n
        for n in device.dump()
        if (n.get("content-desc") or n.get("text")) == "Not measured"
        and n.get("clickable") == "true"
    ]
    if not options:
        raise RuntimeError(f"No AVPU option. Screen: {screen_text(device.dump())[:500]}")
    tap_node(device, options[-1])
    time.sleep(1)


def scenario_2(device: Device, apk: dict) -> bool:
    CURRENT["scenario"] = "s2"
    SCREEN_PREFIX[0] = ""
    CURRENT["backend"].reset()
    entry = RESULTS.setdefault(device.avd, {})["s2"] = {}
    entry["apk"] = apk
    device.install(RELEASE_APK)
    device.keep_awake()
    passed = True
    notes = entry.setdefault("notes", [])
    try:
        release_setup(device)
        device.screenshot("s2_1_release_home")
        text = screen_text(device.dump())
        notes.append(f"Release Home: {text[:300]}")
        shown = [s for s in DEMO_STRINGS if s in text]
        if shown:
            notes.append(f"Demo strings visible on Home: {shown}")
            passed = False

        # Mic denied.
        device.shell(f"pm revoke {PACKAGE} android.permission.RECORD_AUDIO")
        tap_text(device, "Screen Breathing")
        answered = tap_permission(device, allow=False)
        notes.append(f"Mic dialog answered with: {answered}")
        time.sleep(2)
        device.screenshot("s2_2_mic_denied")
        denied = screen_text(device.dump())
        notes.append(f"Screen after denying the mic: {denied[:400]}")
        for text_value in DEMO_STRINGS:
            if text_value in denied:
                notes.append(f"Demo string visible after denial: {text_value}")
                passed = False
        tap_text(device, "Stop & Analyze Early", 20)
        to_result_screen(device)
        device.screenshot("s2_3_vitals_after_denial")
        tap_text(device, "Continue to Result", 20)
        result = wait_screen(device, "Screening Result", 20)
        device.screenshot("s2_4_result_after_denial")
        denied_result = screen_text(result)
        notes.append(f"Result after denying the mic: {denied_result[:500]}")
        entry["mic_denied_inconclusive"] = "INCONCLUSIVE" in denied_result.upper()
        entry["mic_denied_green"] = "GREEN" in denied_result.upper()
        if not entry["mic_denied_inconclusive"] or entry["mic_denied_green"]:
            passed = False

        # Mic allowed: the release build's own native library and model, end to end.
        device.shell(f"am force-stop {PACKAGE}")
        device.shell(f"pm grant {PACKAGE} android.permission.RECORD_AUDIO")
        device.shell(f"am start -n {ACTIVITY}")
        tap_text(device, "Screen Breathing", 60)
        wait_screen(device, "Listening", 20)
        device.screenshot("s2_5_listening")
        # Leave the screen alone until the countdown ends and the analysis finishes. A touch
        # during analysis is what anr_probe tests.
        to_result_screen(device)
        tap_text(device, "Continue to Result", 20)
        allowed = screen_text(wait_screen(device, "Screening Result", 30))
        device.screenshot("s2_6_result_mic_allowed")
        notes.append(f"Result with the mic allowed: {allowed[:500]}")
        entry["mic_allowed_green"] = "GREEN" in allowed.upper()
        entry["mic_allowed_unavailable"] = "unavailable" in allowed.lower()
        if entry["mic_allowed_green"]:
            passed = False
    except Exception as exc:
        passed = False
        entry["failure"] = [str(exc)[:900]]
        log(f"  s2 failed: {str(exc)[:600]}")
        with contextlib.suppress(Exception):
            device.screenshot("s2_failure")
    try:
        anr_probe(device, entry)
    except Exception as exc:
        entry["anr_probe_error"] = str(exc)[:500]
        log(f"  ANR probe did not finish: {str(exc)[:300]}")
    entry["passed"] = passed
    log(f"  s2 {'PASS' if passed else 'FAIL'}")
    save_results(device)
    return passed


def close_anr_dialog(device: Device) -> bool:
    """Android's "isn't responding" dialog stays up until answered, even over other apps."""
    nodes = device.dump()
    if not find_node(nodes, "isn't responding"):
        return False
    device.screenshot("s2_7_anr_dialog")
    button = find_node(nodes, "Close app") or find_node(nodes, "Close") or find_node(nodes, "OK")
    if button:
        tap_node(device, button)
        time.sleep(2)
    return True


def anr_probe(device: Device, entry: dict, runs: int = 3) -> None:
    """A full capture with touches during analysis, with Android's error dialog showing, as a
    CHO would see it. Evidence for the report: it doesn't decide the scenario's pass.
    """
    # The harness hides error dialogs so a System UI ANR can't block a run. With them hidden,
    # Android kills an app that stops responding, instead of asking.
    device.shell("settings put global hide_error_dialogs 0")
    device.shell(f"pm grant {PACKAGE} android.permission.RECORD_AUDIO")
    results = []
    try:
        for attempt in range(runs):
            device.shell(f"am force-stop {PACKAGE}")
            device.shell("logcat -b events -c")
            device.shell(f"am start -n {ACTIVITY}")
            tap_text(device, "Screen Breathing", 60)
            wait_screen(device, "Listening", 20)
            # Touch the app bar, which has no action, once a second until analysis is over.
            started = time.monotonic()
            dialog = False
            while time.monotonic() - started < 40:
                device.shell("input tap 600 200", timeout=30)
                time.sleep(1)
                events = device.shell("logcat -d -b events", timeout=30)
                if re.search(rf"am_anr.*{re.escape(PACKAGE)}", events):
                    break
                # Past the countdown and off the screening page: analysis has finished.
                if time.monotonic() - started > 12 and find_node(device.dump(), "Record Vitals"):
                    break
            events = device.shell("logcat -d -b events", timeout=30)
            anr = bool(re.search(rf"am_anr.*{re.escape(PACKAGE)}", events))
            if anr:
                for _ in range(15):
                    dialog = close_anr_dialog(device)
                    if dialog:
                        break
                    time.sleep(1)
            results.append({"anr": anr, "dialog_shown": dialog})
            log(f"  ANR probe {attempt + 1}: {results[-1]}")
    finally:
        entry["anr_probe"] = results
        close_anr_dialog(device)
        device.shell(f"am force-stop {PACKAGE}")
        device.shell("settings put global hide_error_dialogs 1")
        time.sleep(1)
        # A dialog that came up late, once hidden dialogs no longer apply.
        close_anr_dialog(device)


def cold_start(device: Device, runs: int = 5) -> None:
    """`am start -W` gives the first frame. Home is timed by polling, so it is an upper bound."""
    CURRENT["scenario"] = "timings"
    CURRENT["backend"].reset()
    device.install(RELEASE_APK)
    release_setup(device)
    first_frame, to_home = [], []
    for _ in range(runs):
        device.shell(f"am force-stop {PACKAGE}")
        time.sleep(2)
        started = time.monotonic()
        output = device.shell(f"am start -W -n {ACTIVITY}", timeout=90)
        match = re.search(r"TotalTime:\s*(\d+)", output)
        if match:
            first_frame.append(int(match.group(1)))
        wait_screen(device, "Community Health Officer", 60)
        to_home.append(round((time.monotonic() - started) * 1000))
    RESULTS[device.avd].setdefault("timings", {}).update(
        {
            "cold_start_first_frame_ms": first_frame,
            "cold_start_first_frame_median_ms": statistics.median(first_frame)
            if first_frame
            else None,
            "cold_start_home_seen_ms": to_home,
            "cold_start_home_seen_median_ms": statistics.median(to_home),
        }
    )
    log(f"  cold start first frame {first_frame}, Home seen {to_home}")
    save_results(device)


def tap_scrolling(device: Device, text: str, *, exact: bool = False) -> None:
    for _ in range(14):
        node = find_node(device.dump(), text, exact=exact)
        if node:
            tap_node(device, node)
            return
        device.shell("input swipe 300 1000 300 500 300")
        time.sleep(0.5)
    raise RuntimeError(f"Could not scroll to '{text}'. Screen: {screen_text(device.dump())[:500]}")


def release_confirm_timing(device: Device, runs: int = 3) -> None:
    """Confirm Referral to "TIER1_NOTIFIED" on the release APK. Read through the accessibility
    tree, so each figure is an upper bound: it includes the time one read of the screen takes.
    """
    CURRENT["scenario"] = "timings"
    samples = []
    device.shell(f"pm grant {PACKAGE} android.permission.RECORD_AUDIO")
    for run_number in range(runs):
        # Fresh each time, so a driver offered once isn't busy with the last referral.
        CURRENT["backend"].reset()
        device.shell(f"am force-stop {PACKAGE}")
        device.shell(f"am start -n {ACTIVITY}")
        tap_text(device, "Screen Breathing", 60)
        tap_text(device, "Stop & Analyze Early", 30)
        to_result_screen(device)
        tap_text(device, "Continue to Result", 20)
        wait_screen(device, "Screening Result", 30)
        tap_scrolling(device, "Confirm Referral", exact=True)
        tap_text(device, "tap to confirm facility", 30)
        tap_text(device, "Tamale Teaching Hospital", 20)
        wait_screen(device, "(confirmed)", 20)
        tap_text(device, "Emergency type", 20)
        tap_text(device, "Postpartum hemorrhage", 20)
        time.sleep(1)
        # Every vital is marked Not measured, so the name is the only field still enabled.
        field = None
        for _ in range(8):
            field = next(
                (
                    n
                    for n in device.dump()
                    if n.get("class") == "android.widget.EditText" and n.get("enabled") == "true"
                ),
                None,
            )
            if field:
                break
            device.shell("input swipe 300 900 300 600 300")
            time.sleep(0.5)
        if field is None:
            raise RuntimeError(f"No name field. Screen: {screen_text(device.dump())[:500]}")
        tap_node(device, field)
        time.sleep(1)
        device.shell("input text 'Unknown'")
        time.sleep(0.5)
        device.shell("input keyevent KEYCODE_BACK")
        time.sleep(1)
        confirm = None
        for _ in range(12):
            nodes = device.dump()
            confirm = find_node(nodes, "Confirm Referral", exact=True)
            if confirm:
                break
            device.shell("input swipe 300 1000 300 300 300")
            time.sleep(0.5)
        if confirm is None:
            raise RuntimeError(f"No Confirm Referral. Screen: {screen_text(device.dump())[:500]}")
        started = time.monotonic()
        tap_node(device, confirm)
        wait_screen(device, "TIER1_NOTIFIED", 45)
        samples.append(round((time.monotonic() - started) * 1000))
        if run_number == 0:
            device.screenshot("timing_release_tier1")
    RESULTS[device.avd].setdefault("timings", {}).update(
        {
            "confirm_to_notified_release_ms": samples,
            "confirm_to_notified_release_median_ms": statistics.median(samples),
        }
    )
    log(f"  Confirm Referral to notified, release: {samples}")
    save_results(device)


def serve() -> ThreadingHTTPServer:
    server = ThreadingHTTPServer(("127.0.0.1", HARNESS_PORT), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--avd", action="append", choices=sorted(AVDS), help="Default: both")
    parser.add_argument(
        "--scenarios",
        nargs="*",
        default=["1", "2", "3", "4", "5", "6", "7", "8", "9", "banners_native", "timings"],
        help="1-9, banners, banners_native and timings",
    )
    parser.add_argument(
        "--keep-running",
        action="store_true",
        help="Leave the emulator up, and reuse one that is already up",
    )
    args = parser.parse_args()
    KEEP_RUNNING[0] = args.keep_running

    for tool in (FLUTTER, ADB, EMULATOR, PYTHON):
        if not Path(tool).exists():
            print(f"Missing {tool}", file=sys.stderr)
            return 2
    if "3.44.8" not in run([FLUTTER, "--version"]):
        print(f"{FLUTTER} is not Flutter 3.44.8", file=sys.stderr)
        return 2

    run([FLUTTER, "pub", "get", "--enforce-lockfile"], cwd=MOBILE, timeout=300)
    server = serve()
    backend = Backend()
    CURRENT["backend"] = backend
    all_passed = True
    apk: dict | None = None
    try:
        for avd in args.avd or list(AVDS):
            device = Device(avd)
            CURRENT["device"] = device
            device.boot()
            try:
                for scenario in args.scenarios:
                    if scenario == "2" or (scenario == "timings" and apk is None):
                        apk = apk or build_release()
                    if scenario == "2":
                        all_passed &= scenario_2(device, apk)
                    elif scenario == "timings":
                        cold_start(device)
                        release_confirm_timing(device)
                    elif scenario in ("9", "banners"):
                        device.shell(f"wm size {SMALL_WIDTH_PX}x{SMALL_HEIGHT_PX}")
                        device.shell(f"wm density {SMALL_DENSITY}")
                        try:
                            inner = SMALL_SCREEN_SCENARIOS if scenario == "9" else ["banners"]
                            for name in inner:
                                all_passed &= run_integration(device, name, small=True)
                        finally:
                            device.reset_screen()
                    else:
                        all_passed &= run_integration(device, scenario)
            finally:
                save_results(device)
                device.shutdown()
    finally:
        backend.stop()
        server.shutdown()
    log("All passed" if all_passed else "Some scenarios FAILED")
    return 0 if all_passed else 1


if __name__ == "__main__":
    sys.exit(main())
