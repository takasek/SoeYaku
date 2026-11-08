"""Temporary loopback bridge for Kikiyaku's default prompt and PLaMo 3 Translate.

No audio processing, transcript storage, remote destinations, or custom system prompts.
The bridge accepts English/Japanese requests and emits PFML3 to a local llama-server.
"""

import argparse
import json
import os
from pathlib import Path
import re
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib import request, error
import uuid

DEFAULT_PROMPT = Path(__file__).with_name('kikiyaku-default-prompt.txt').read_text().strip()
GLOSSARY_HEADER = ('Use the term mappings in the <glossary> below in either translation direction, '
                   'choosing the form appropriate to the target language.')
TAG = '<|plamo:tag|>'
MSG = '<|plamo:msg|>'


def literal(value):
    return value.replace('<|', '＜|')


def language(value):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z]{2}(?:-[A-Za-z0-9]{2,8})*', value):
        raise ValueError('Expected a supported BCP-47 language code.')
    base = value.split('-')[0].lower()
    if base not in ('en', 'ja'):
        raise ValueError('This demo bridge supports English and Japanese only.')
    return base


def utterance(value):
    if not isinstance(value, str):
        raise ValueError('Utterance content must be text.')
    match = re.fullmatch(r'<u\s+([^>]*)>([\s\S]*)</u>', value.strip())
    if not match:
        raise ValueError('Expected Kikiyaku utterance envelope.')
    attrs = match[1]
    pairs = re.findall(r'([A-Za-z][A-Za-z0-9_-]*)\s*=\s*"([^"]*)"', attrs)
    remainder = re.sub(r'([A-Za-z][A-Za-z0-9_-]*)\s*=\s*"([^"]*)"', '', attrs)
    if remainder.strip() or len(pairs) != 2 or {a for a, _ in pairs} != {'source', 'target'}:
        raise ValueError('Expected one source and one target attribute.')
    values = dict(pairs)
    source, target = language(values['source']), language(values['target'])
    if source == target or not match[2].strip():
        raise ValueError('Expected nonempty speech and different source/target languages.')
    return source, target, match[2]


def glossary(system):
    if not isinstance(system, str) or not system.startswith(DEFAULT_PROMPT):
        raise ValueError('Use the default Kikiyaku system prompt for this demo bridge.')
    rest = system[len(DEFAULT_PROMPT):].strip()
    if not rest:
        return []
    match = re.fullmatch(re.escape(GLOSSARY_HEADER) + r'\s*<glossary>\s*([\s\S]*?)\s*</glossary>', rest)
    if not match:
        raise ValueError('Custom system prompts are not supported by this demo bridge.')
    terms = []
    for line in match[1].splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        fields = line.split('\t') if '\t' in line else line.split('=', 1)
        if len(fields) != 2 or not all(s.strip() for s in fields):
            raise ValueError('Glossary lines must contain source = target or a tab.')
        source, target = (s.strip() for s in fields)
        terms = [(a, b) for a, b in terms if a.lower() != source.lower()]
        terms.append((source, target))
    return terms


def prefix(kind, lang):
    return TAG + kind + '<|plamo:key|>lang<|plamo:val|>' + lang + MSG


def convert(body):
    if not isinstance(body, dict) or body.get('tools') or body.get('documents'):
        raise ValueError('Expected a text chat request without tools or documents.')
    messages = body.get('messages')
    if not isinstance(messages, list) or len(messages) < 2 or len(messages) % 2:
        raise ValueError('Expected a system prompt and alternating utterance/translation turns.')
    if not all(isinstance(m, dict) and isinstance(m.get('content'), str) for m in messages):
        raise ValueError('Expected text messages.')
    if messages[0].get('role') != 'system':
        raise ValueError('Expected one leading system prompt.')
    terms = glossary(messages[0]['content'])
    conversation = messages[1:]
    for i, message in enumerate(conversation):
        if message.get('role') != ('user' if i % 2 == 0 else 'assistant'):
            raise ValueError('Invalid conversation roles.')
    probe = len(messages) == 2 and conversation[-1]['content'] == '.' and body.get('max_completion_tokens') == 1
    current = ('en', 'ja', '.') if probe else utterance(conversation[-1]['content'])
    prompt = TAG + 'dataset' + MSG + 'translation'
    # PLaMo's translation examples use one language pair. Opposite-direction
    # examples can override the current output language in the2B model.
    history = []
    for i in range(0, len(conversation) - 1, 2):
        source, target, text = utterance(conversation[i]['content'])
        translated = conversation[i + 1]['content']
        if not translated.strip():
            raise ValueError('Empty history translation.')
        if (source, target) == current[:2]:
            history.append((source, target, text, translated))
    for source, target, text, translated in history[-3:]:
        prompt += prefix('input', source) + literal(text) + prefix('output', target) + literal(translated)
    source, target, text = current
    matching = []
    for a, b in terms:
        original, translation = (a, b) if source == 'en' else (b, a)
        matches = (re.search(r'(?<!\w)' + re.escape(original) + r'(?!\w)', text, re.IGNORECASE) is not None
                   if source == 'en' else original in text)
        if matches:
            matching.append((original, translation))
    if matching:
        prompt += TAG + 'glossary'
        for a, b in matching:
            prompt += '<|plamo:index|>' + literal(a) + '<|plamo:item|>' + literal(b)
    return prompt + prefix('input', source) + literal(text) + prefix('output', target), probe


def completed(value, probe):
    content = value.get('content')
    if not isinstance(content, str):
        raise ValueError('Backend did not return text.')
    text = content.strip()
    if probe:
        return text, 'stop' if value.get('stop_type') in ('word', 'eos') else 'length'
    if value.get('stop') is not True or value.get('truncated') or value.get('stop_type') not in ('word', 'eos') or not text:
        raise ValueError('Backend did not finish the translation.')
    return text, 'stop'


class NoRedirect(request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise error.HTTPError(req.full_url, code, 'Backend redirects are not allowed.', headers, fp)


class BackendFailure(RuntimeError):
    pass


class Backend:
    def __init__(self, port, key):
        if not 1 <= port <= 65535:
            raise ValueError('Backend port out of range.')
        self.base = f'http://127.0.0.1:{port}'
        self.key = key
        self.http = request.build_opener(request.ProxyHandler({}), NoRedirect())
        models = self.call('/v1/models')
        self.model = models['data'][0]['id']

    def call(self, path, payload=None):
        headers = {'Content-Type': 'application/json'}
        if self.key:
            headers['Authorization'] = 'Bearer ' + self.key
        req = request.Request(self.base + path, data=None if payload is None else json.dumps(payload, ensure_ascii=False).encode(), headers=headers)
        with self.http.open(req, timeout=45) as response:
            return json.load(response)

    def translate(self, body):
        if not isinstance(body, dict):
            raise ValueError('Expected a chat request object.')
        if body.get('model') != self.model:
            raise ValueError('Select the model returned by this bridge.')
        prompt, probe = convert(body)
        limit = body.get('max_completion_tokens', 512)
        if type(limit) is not int or limit < 1:
            raise ValueError('Invalid completion limit.')
        value = self.call('/completion', {'prompt': prompt, 'n_predict': min(limit, 512), 'stream': False,
            'temperature': 0, 'top_k': 1, 'min_p': 0, 'repeat_penalty': 1.0, 'repeat_last_n': 0, 'cache_prompt': False,
            'stop': ['<|plamo:tag|>', '<|plamo:bos|>', '<|plamo:eos|>']})
        try:
            return completed(value, probe)
        except (ValueError, TypeError, AttributeError) as exc:
            raise BackendFailure('PLaMo did not complete the translation.') from exc


def handler(backend):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass  # Never log caption text, headers, or prompts.

        def send_json(self, status, value):
            data = json.dumps(value, ensure_ascii=False).encode()
            self.send_response(status)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def allowed(self):
            host = self.headers.get('Host', '').split(':')[0]
            return host in ('127.0.0.1', 'localhost') and self.headers.get('Origin') is None

        def do_GET(self):
            if not self.allowed():
                self.send_json(403, {'error': 'Local native clients only.'}); return
            if self.path not in ('/v1/models', '/models'):
                self.send_json(404, {'error': 'Not found.'}); return
            self.send_json(200, {'object': 'list', 'data': [{'id': backend.model, 'object': 'model', 'owned_by': 'local'}]})

        def do_POST(self):
            if not self.allowed():
                self.send_json(403, {'error': 'Local native clients only.'}); return
            if self.path not in ('/v1/chat/completions', '/chat/completions'):
                self.send_json(404, {'error': 'Not found.'}); return
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if not 0 < length <= 65536:
                    self.send_json(413, {'error': 'Expected a text request no larger than64KiB.'}); return
                body = json.loads(self.rfile.read(length))
                text, finish = backend.translate(body)
            except (ValueError, TypeError, KeyError):
                self.send_json(400, {'error': 'Invalid Kikiyaku request or incomplete PLaMo result.'}); return
            except (BackendFailure, OSError, error.URLError):
                self.send_json(502, {'error': 'Local PLaMo backend is unavailable.'}); return
            result = {'id': 'chatcmpl-' + uuid.uuid4().hex, 'created': int(time.time()), 'model': backend.model}
            if not body.get('stream'):
                self.send_json(200, {**result, 'object': 'chat.completion', 'choices': [
                    {'index': 0, 'message': {'role': 'assistant', 'content': text}, 'finish_reason': finish}]})
                return
            self.send_response(200)
            self.send_header('Content-Type', 'text/event-stream')
            self.send_header('Cache-Control', 'no-cache')
            self.end_headers()
            # One completed translation is emitted, then stop. Token-level streaming is not provided.
            for delta, reason in [({'role': 'assistant', 'content': text}, None), ({}, finish)]:
                chunk = {**result, 'object': 'chat.completion.chunk', 'choices': [{'index': 0, 'delta': delta, 'finish_reason': reason}]}
                self.wfile.write(('data: ' + json.dumps(chunk, ensure_ascii=False) + '\n\n').encode())
            self.wfile.write(b'data: [DONE]\n\n')
            self.wfile.flush()
    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--backend-port', type=int, required=True)
    parser.add_argument('--backend-key-env', default='LLAMA_API_KEY')
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error('Port must be1..65535.')
    backend = Backend(args.backend_port, os.environ.get(args.backend_key_env))
    with HTTPServer(('127.0.0.1', args.port), handler(backend)) as server:
        print(f'Bridge http://127.0.0.1:{args.port}/v1 model={backend.model}', flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == '__main__':
    main()
