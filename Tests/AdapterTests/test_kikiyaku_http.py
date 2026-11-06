import copy
from http.server import HTTPServer
import json
from pathlib import Path
import sys
import threading
import unittest
from urllib import request, error

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'Tools'))
import kikiyaku_plamo as adapter


class HTTPTests(unittest.TestCase):
    def setUp(self):
        self.body = json.loads((Path(__file__).parent / 'fixtures/kikiyaku-en-ja.json').read_text())
        self.backend = adapter.Backend.__new__(adapter.Backend)
        self.backend.model = 'demo-plamo'
        self.reply = {'content': '子プロセスを起動する。', 'stop': True, 'stop_type': 'eos'}
        self.calls = []
        def call(path, payload=None):
            self.calls.append((path, payload))
            return self.reply
        self.backend.call = call
        self.server = HTTPServer(('127.0.0.1', 0), adapter.handler(self.backend))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = f'http://127.0.0.1:{self.server.server_port}'
        self.http = request.build_opener(request.ProxyHandler({}))

    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join(timeout=2)
        self.assertFalse(self.thread.is_alive())

    def post(self, body, headers=None):
        req = request.Request(self.url + '/v1/chat/completions', data=json.dumps(body).encode(),
                              headers={'Content-Type': 'application/json', **(headers or {})})
        try:
            with self.http.open(req, timeout=3) as response:
                return response.status, response.headers.get('Content-Type'), response.read()
        except error.HTTPError as exc:
            return exc.code, exc.headers.get('Content-Type'), exc.read()

    def test_stream_ends_with_stop_and_done(self):
        status, content_type, raw = self.post(self.body)
        self.assertEqual(status, 200)
        self.assertEqual(content_type, 'text/event-stream')
        self.assertTrue(raw.endswith(b'data: [DONE]\n\n'))
        events = [json.loads(line[6:]) for line in raw.decode().splitlines() if line.startswith('data: {')]
        self.assertEqual(events[0]['choices'][0]['delta']['content'], '子プロセスを起動する。')
        self.assertEqual(events[-1]['choices'][0]['finish_reason'], 'stop')
        payload = self.calls[0][1]
        self.assertEqual(payload['n_predict'], 512)
        self.assertFalse(payload['cache_prompt'])

    def test_nonstream_and_model_discovery(self):
        self.body['stream'] = False
        status, _, raw = self.post(self.body)
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(raw)['choices'][0]['message']['content'], '子プロセスを起動する。')
        with self.http.open(self.url + '/v1/models', timeout=3) as response:
            self.assertEqual(json.load(response)['data'][0]['id'], 'demo-plamo')

    def test_nonobject_request_returns400(self):
        for body in [[], 'text', None, 123]:
            with self.subTest(body=body):
                self.assertEqual(self.post(body)[0], 400)

    def test_truncated_translation_is_a_backend_failure(self):
        self.reply = {'content': 'partial', 'stop': True, 'stop_type': 'limit', 'truncated': True}
        status, _, _ = self.post(self.body)
        self.assertEqual(status, 502)

    def test_browser_origin_is_refused_without_model_request(self):
        self.assertEqual(self.post(self.body, {'Origin': 'https://example.com'})[0], 403)
        self.assertEqual(self.calls, [])

    def test_oversized_body_is_refused_before_translation(self):
        self.assertEqual(self.post({'data': 'x' * 65536})[0], 413)
        self.assertEqual(self.calls, [])


if __name__ == '__main__':
    unittest.main()
