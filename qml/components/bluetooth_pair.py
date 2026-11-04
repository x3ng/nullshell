"""On-demand bridge to BlueZ's KeyboardDisplay agent; stdlib only.

JSON lines in/out. Never becomes the default agent or polls device state.
bluetoothctl owns the Agent1 registration for its own Pair request. Its fixed
English prompts (BlueZ client/agent.c) are the only text interpreted here.
Pairing answers use stdin, never argv, files or diagnostic output.
"""

import codecs
import json
import os
import pty
import re
import selectors
import signal
import subprocess
import sys
import termios
import time


class AgentParser:
    ansi = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07]*(?:\x07|\x1b\\)")
    patterns = [
        ("ready", re.compile(r"(?:^|[\r\n])Agent registered[\r\n]")),
        ("confirm", re.compile(r"\[agent\] Confirm passkey (\d{6}) \(yes/no\):")),
        ("authorize", re.compile(r"\[agent\] (?:Accept pairing|Authorize service [0-9a-fA-F-]+) \(yes/no\):")),
        ("pin", re.compile(r"\[agent\] Enter PIN code:")),
        ("passkey", re.compile(r"\[agent\] Enter passkey \(number in 0-999999\):")),
        ("display", re.compile(r"\[agent\] (?:Passkey|PIN code): ([^\r\n]+)[\r\n]")),
        ("success", re.compile(r"(?:^|[\r\n])Pairing successful[\r\n]")),
        ("error", re.compile(r"(?:^|[\r\n])((?:Failed to pair|Failed to register agent|Device .* not available|Controller .* not available|No default controller available)[^\r\n]*)[\r\n]")),
        ("cancelled", re.compile(r"(?:^|[\r\n])Request canceled[\r\n]")),
    ]

    def __init__(self):
        self.buffer = ""
        self.decoder = codecs.getincrementaldecoder("utf-8")("replace")

    def feed(self, data):
        self.buffer += self.decoder.decode(data)
        events = []
        while True:
            clean = self.ansi.sub("", self.buffer)
            candidates = [(match.start(), kind, match) for kind, pattern in self.patterns
                          if (match := pattern.search(clean))]
            if not candidates:
                # Keep incomplete prompts/escape sequences across read boundaries.
                self.buffer = self.buffer[-32768:]
                return events
            _, kind, match = min(candidates, key=lambda item: item[0])
            self.buffer = clean[match.end():]
            events.append((kind, match.group(1) if match.lastindex else ""))


def valid_answer(kind, answer):
    if not isinstance(answer, str):
        return False
    if kind in ("confirm", "authorize"):
        return answer in ("yes", "no")
    if kind == "passkey":
        return re.fullmatch(r"[0-9]{1,6}", answer) is not None
    return kind == "pin" and 1 <= len(answer) <= 16 and not re.search(r"[\x00-\x1f\x7f]", answer)


def emit(**event):
    print(json.dumps(event), flush=True)


def run(address, adapter):
    if not re.fullmatch(r"(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}", address):
        raise ValueError("Invalid Bluetooth address")
    if not re.fullmatch(r"hci[0-9]+", adapter):
        raise ValueError("Invalid Bluetooth adapter")
    # bluetoothctl's select command takes a controller MAC, not its hci name.
    reply = subprocess.run(
        ["busctl", "--system", "--timeout=2", "--json=short", "get-property", "org.bluez",
         "/org/bluez/" + adapter, "org.bluez.Adapter1", "Address"],
        capture_output=True, text=True, timeout=3, check=True,
    )
    controller = json.loads(reply.stdout)
    controller_address = controller.get("data", "")
    if controller.get("type") != "s" or not re.fullmatch(r"(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}", controller_address):
        raise ValueError("Invalid Bluetooth controller address")
    master, slave = pty.openpty()
    settings = termios.tcgetattr(slave)
    settings[3] &= ~termios.ECHO
    termios.tcsetattr(slave, termios.TCSANOW, settings)
    process = None
    try:
        process = subprocess.Popen(
            ["bluetoothctl", "--agent", "KeyboardDisplay"], stdin=slave, stdout=slave,
            stderr=slave, env={**os.environ, "LC_ALL": "C", "TERM": "dumb"}, close_fds=True,
        )
        os.close(slave)
        slave = -1
        parser = AgentParser()
        pending = ""
        requested = False
        input_buffer = b""
        deadline = time.monotonic() + 90
        with selectors.DefaultSelector() as selector:
            selector.register(master, selectors.EVENT_READ, "agent")
            selector.register(sys.stdin, selectors.EVENT_READ, "input")
            while process.poll() is None and time.monotonic() < deadline:
                for key, _ in selector.select(timeout=0.5):
                    if key.data == "input":
                        chunk = os.read(sys.stdin.fileno(), 4096)
                        if not chunk:
                            return
                        input_buffer += chunk
                        if len(input_buffer) > 4096:
                            raise ValueError("Invalid pairing response")
                        while b"\n" in input_buffer:
                            line, input_buffer = input_buffer.split(b"\n", 1)
                            response = json.loads(line)
                            if response.get("cancel"):
                                return
                            answer = response.get("answer")
                            if valid_answer(pending, answer):
                                os.write(master, (answer + "\n").encode())
                                pending = ""
                        continue
                    try:
                        chunk = os.read(master, 4096)
                    except OSError:
                        chunk = b""
                    if not chunk:
                        emit(type="done", success=False, error="Bluetooth agent stopped.")
                        return
                    for kind, value in parser.feed(chunk):
                        if kind == "ready" and not requested:
                            # Select is local to this bluetoothctl client. Pair runs
                            # after select in the same ordered command stream.
                            os.write(master, f"select {controller_address}\npair {address}\n".encode())
                            requested = True
                        elif kind in ("confirm", "authorize", "pin", "passkey", "display") and requested:
                            pending = kind
                            emit(type="prompt", kind=kind, code=value)
                        elif kind == "success" and requested:
                            emit(type="done", success=True)
                            return
                        elif kind in ("error", "cancelled"):
                            emit(type="done", success=False, error=value or "Pairing was cancelled by the device.")
                            return
        emit(type="done", success=False, error="Pairing timed out. Put the device in pairing mode and try again.")
    finally:
        # Closing this agent's bus connection cancels unanswered requests, even
        # when the panel closes or the helper receives SIGTERM.
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        os.close(master)
        if slave >= 0:
            os.close(slave)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    try:
        run(*sys.argv[1:])
    except (OSError, ValueError, TypeError, subprocess.SubprocessError):
        emit(type="done", success=False, error="Cannot start the Bluetooth pairing agent. Check python3 and bluetoothctl.")
