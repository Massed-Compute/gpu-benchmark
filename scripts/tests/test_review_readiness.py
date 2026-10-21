"""Local regressions for the two standalone Linux benchmark runners.

Run: python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v
No GPU, server, network connection, or benchmark is started.
"""
import io
import json
import re
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SLUGS = ('lfm2.5-24b-a2b', 'minicpm-v-4.7-35b-a3b')


class ReadinessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.proc = Path(self.temp.name)
        (self.proc / '123' / 'fd').mkdir(parents=True)
        (self.proc / 'net').mkdir()
        (self.proc / '123' / 'fd' / '7').symlink_to('socket:[456]')
        self.table()

    def table(self, inode='456', port='1F40', state='0A', protocol='tcp'):
        # /proc/net/tcp uses hexadecimal ports/states; field 9 is the inode.
        (self.proc / 'net' / protocol).write_text(
            'sl local_address rem_address st tx_queue rx tr tm retrnsmt uid timeout inode\n'
            f'0: 00000000:{port} 00000000:0000 {state} 0:0 0:0 0 0 0 {inode}\n'
        )

    def probe(self, slug, payload=None, error=None):
        source = (ROOT / 'scripts' / slug / 'remote.sh').read_text()
        code = re.search(
            r'python - "\$SERVE_PID" "\$REPO" <<\'PY\'\n(.*?)\nPY',
            source, re.S,
        ).group(1)
        if payload is None:
            payload = json.dumps({'data': [{'id': slug}]}).encode()
        with patch('pathlib.Path', return_value=self.proc), \
                patch('sys.argv', ['-', '123', slug]), \
                patch('urllib.request.build_opener') as build:
            opener = build.return_value
            opener.open.side_effect = error
            opener.open.return_value = io.BytesIO(payload)
            with self.assertRaises(SystemExit) as exited:
                exec(compile(code, str(ROOT / 'scripts' / slug / 'remote.sh'), 'exec'), {})
            return exited.exception.code, opener.open

    def test_own_listener_and_expected_model_are_ready(self):
        for slug in SLUGS:
            with self.subTest(runner=slug):
                status, request = self.probe(slug)
                self.assertEqual(status, 0)
                request.assert_called_once_with('http://127.0.0.1:8000/v1/models', timeout=3)

    def test_stale_same_model_server_is_rejected_before_http(self):
        self.table(inode='999')
        for slug in SLUGS:
            with self.subTest(runner=slug):
                status, request = self.probe(slug)
                self.assertEqual(status, 1)
                request.assert_not_called()

    def test_nonlistener_or_wrong_port_is_not_ready(self):
        for port, state in [('1F40', '01'), ('1F41', '0A')]:
            self.table(port=port, state=state)
            for slug in SLUGS:
                with self.subTest(runner=slug, port=port, state=state):
                    status, request = self.probe(slug)
                    self.assertEqual(status, 1)
                    request.assert_not_called()

    def test_ipv6_listener_is_supported(self):
        self.table(inode='999')
        self.table(protocol='tcp6')
        for slug in SLUGS:
            with self.subTest(runner=slug):
                self.assertEqual(self.probe(slug)[0], 0)

    def test_exited_process_is_not_ready(self):
        (self.proc / '123' / 'fd' / '7').unlink()
        (self.proc / '123' / 'fd').rmdir()
        for slug in SLUGS:
            with self.subTest(runner=slug):
                status, request = self.probe(slug)
                self.assertEqual(status, 1)
                request.assert_not_called()

    def test_wrong_model_or_bad_response_is_not_ready(self):
        payloads = [b'{"data":[{"id":"old-model"}]}', b'{"data":[]}',
                    b'not json', b'[]', b'{"data":null}', b'{"data":[null]}']
        for slug in SLUGS:
            for payload in payloads:
                with self.subTest(runner=slug, payload=payload):
                    self.assertEqual(self.probe(slug, payload=payload)[0], 1)

    def test_http_timeout_is_not_ready(self):
        for slug in SLUGS:
            with self.subTest(runner=slug):
                self.assertEqual(self.probe(slug, error=TimeoutError('not ready'))[0], 1)

    def test_descriptor_race_is_not_ready(self):
        for slug in SLUGS:
            with self.subTest(runner=slug), patch('os.readlink', side_effect=FileNotFoundError):
                status, request = self.probe(slug)
                self.assertEqual(status, 1)
                request.assert_not_called()

    def shell_gate(self, slug, alive_checks, probe_status):
        source = (ROOT / 'scripts' / slug / 'remote.sh').read_text()
        wait_function = re.search(r'^wait_serve\(\) \{\n.*?^\}', source, re.M | re.S).group()
        gate = source.split('trap cleanup EXIT\n', 1)[1].split('log "ready"', 1)[0]
        # Run the real wait function and its caller, replacing external commands
        # with shell functions. No setup/install/start/bench section is executed.
        harness = r'''
set -euo pipefail
SERVE_PID=123 REPO=expected OUTDIR="$1"
checks=0 probes=0
kill() { checks=$((checks + 1)); [[ "$checks" -le ALIVE_CHECKS ]]; }
python() { probes=$((probes + 1)); return PROBE_STATUS; }
seq() { printf '1\n2\n'; }
sleep() { :; }
start_serve() { :; }
log() { :; }
tail() { :; }
MAX_LEN=8192
'''.replace('ALIVE_CHECKS', str(alive_checks)).replace('PROBE_STATUS', str(probe_status))
        result = subprocess.run(
            ['bash', '-c', harness + wait_function + '\n' + gate +
             '\nprintf "%s %s\\n" "$checks" "$probes" > "$OUTDIR/passed"',
             'readiness-test', self.temp.name], capture_output=True, text=True, timeout=5,
        )
        marker = self.proc / 'passed'
        counts = marker.read_text() if marker.exists() else None
        marker.unlink(missing_ok=True)
        return result, counts

    def test_live_owned_ready_server_passes_caller(self):
        for slug in SLUGS:
            with self.subTest(runner=slug):
                result, counts = self.shell_gate(slug, alive_checks=2, probe_status=0)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(counts, '2 1\n')

    def test_dead_process_cannot_reach_bench(self):
        for slug in SLUGS:
            with self.subTest(runner=slug):
                result, counts = self.shell_gate(slug, alive_checks=0, probe_status=0)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIsNone(counts)

    def test_process_exit_during_http_cannot_reach_bench(self):
        for slug in SLUGS:
            with self.subTest(runner=slug):
                result, counts = self.shell_gate(slug, alive_checks=1, probe_status=0)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIsNone(counts)

    def test_sku_match_is_casefolded_and_fallback_forces_triton(self):
        for slug in SLUGS:
            text = (ROOT / 'scripts' / slug / 'remote.sh').read_text()
            with self.subTest(runner=slug):
                self.assertIn("SKU_LOWER=$(printf '%s' \"$SKU\" | tr '[:upper:]' '[:lower:]')", text)
                self.assertNotIn('case "$SKU"', text)
                self.assertNotIn('[[ "$SKU" ==', text)
                self.assertIn('*a100*|*a6000*)', text)
                self.assertIn('*h100*|*h200*)', text)
                self.assertIn('*l40*|*6000_ada*|*pro_6000_blackwell*)', text)
                self.assertEqual(text.count('ATTN_BACKEND="${ATTN_BACKEND:-TRITON_ATTN}"'), 3)
                self.assertEqual(text.count('ATTN_BACKEND="${ATTN_BACKEND:-FLASH_ATTN}"'), 1)

    def test_readiness_timeout_cannot_reach_bench(self):
        for slug in SLUGS:
            with self.subTest(runner=slug):
                result, counts = self.shell_gate(slug, alive_checks=10, probe_status=1)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIsNone(counts)


if __name__ == '__main__':
    unittest.main()
