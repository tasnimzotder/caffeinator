#!/usr/bin/env python3
"""Exercise real IOKit assertions and the Raycast protocol in isolated storage."""
import json
import os
from pathlib import Path
import socket
import sqlite3
import stat
import subprocess
import sys
import tempfile
import time

binary = str(Path(sys.argv[1]).resolve())
before = subprocess.check_output(['/usr/bin/pmset', '-g'], text=True)
with tempfile.TemporaryDirectory(prefix='caffeinator-native-') as directory:
    env = dict(os.environ, CAFFEINATOR_CONFIG_DIR=directory)
    log = tempfile.TemporaryFile()
    app = subprocess.Popen([binary, '--headless'], env=env, stdout=log, stderr=log)
    path = str(Path(directory) / 'control.sock')
    def request(message):
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(10)
            client.connect(path)
            client.sendall(json.dumps(message).encode() + b'\n')
            response = b''
            while not response.endswith(b'\n'):
                chunk = client.recv(4096)
                if not chunk:
                    raise RuntimeError('Unexpected socket EOF')
                response += chunk
            return json.loads(response)
    try:
        for _ in range(100):
            if app.poll() is not None:
                log.seek(0)
                raise RuntimeError(log.read().decode())
            try:
                status = request({'command': 'status'})
                break
            except (FileNotFoundError, ConnectionRefusedError):
                time.sleep(.1)
        else:
            raise RuntimeError('Control service did not start')
        assert status['ok'] and not status['status']['is_active']
        assert status['status']['remaining_seconds'] is None
        assert stat.S_IMODE(os.stat(path).st_mode) == 0o600
        duplicate = subprocess.run([binary, '--headless'], env=env, capture_output=True, text=True, timeout=10)
        assert duplicate.returncode != 0 and 'Another Caffeinator' in duplicate.stderr
        for mode in ['NoIdleSleep', 'NoDisplaySleep', 'NetworkActive', 'BackgroundTask']:
            start = request({'command': 'start', 'mode': mode, 'duration_secs': 3})
            assert start['ok'] and start['status']['is_active'], start
            assertions = subprocess.check_output(['/usr/bin/pmset', '-g', 'assertions'], text=True)
            assert any(f'pid {app.pid}(' in line and 'Caffeinator:' in line for line in assertions.splitlines()), assertions
            invalid = request({'command': 'start', 'mode': mode, 'duration_secs': 0})
            assert not invalid['ok'] and invalid['status']['is_active']
            assert not request({'command': 'status', 'extra': 'reject'})['ok']
            stop = request({'command': 'stop'})
            assert stop['ok'] and not stop['status']['is_active'], stop
        start = request({'command': 'start', 'mode': 'NoIdleSleep', 'duration_secs': 2})
        assert start['ok']
        for _ in range(50):
            if not request({'command': 'status'})['status']['is_active']:
                break
            time.sleep(.1)
        else:
            raise RuntimeError('Timed session did not expire')
        assert request({'command': 'preferences', 'mode': 'NoDisplaySleep', 'duration_secs': None})['ok']
        assert request({'command': 'toggle'})['status']['mode'] == 'NoDisplaySleep'
        assert not request({'command': 'toggle'})['status']['is_active']
        assert request({'command': 'show'})['ok']
        with sqlite3.connect(str(Path(directory) / 'caffeinator.sqlite3')) as db:
            assert db.execute('PRAGMA user_version').fetchone()[0] == 2
            assert db.execute("SELECT COUNT(*) FROM session_history WHERE end_reason='expired'").fetchone()[0] == 1
        app.terminate()
        assert app.wait(timeout=10) == 0
        app = subprocess.Popen([binary, '--headless'], env=env, stdout=log, stderr=log)
        for _ in range(100):
            try:
                response = request({'command': 'status'})
                if response['status']['selected_mode'] == 'NoDisplaySleep':
                    break
            except (FileNotFoundError, ConnectionRefusedError):
                pass
            time.sleep(.1)
        else:
            raise RuntimeError('Restart failed to preserve preferences')
        assert response['status']['selected_duration'] is None
        assert not response['status']['is_active']
        after = subprocess.check_output(['/usr/bin/pmset', '-g'], text=True)
        # Assertions change the sleep line's parenthetical; compare configured values.
        def settings(text):
            result = {}
            for line in text.splitlines():
                words = line.split()
                if len(words) >= 2 and words[1].isdigit():
                    result[words[0]] = words[1]
            return result
        assert settings(before) == settings(after), (before, after)
        print('PASS: four real IOKit modes, start/stop/toggle/show, timed expiry, protocol validation, private socket, single instance, persisted history/preferences, unchanged power settings')
    finally:
        if app.poll() is None:
            app.terminate()
            try:
                app.wait(timeout=10)
            except subprocess.TimeoutExpired:
                app.kill()
                app.wait()
        log.close()
