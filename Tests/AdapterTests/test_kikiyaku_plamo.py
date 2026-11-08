import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'Tools'))
import kikiyaku_plamo as adapter


class AdapterTests(unittest.TestCase):
    def setUp(self):
        self.body = json.loads((Path(__file__).parent / 'fixtures/kikiyaku-en-ja.json').read_text())

    def test_actual_kikiyaku_request_passes_only_matching_terms(self):
        prompt, probe = adapter.convert(self.body)
        self.assertFalse(probe)
        self.assertIn('<|plamo:index|>subprocess<|plamo:item|>子プロセス', prompt)
        self.assertIn('<|plamo:index|>standard output<|plamo:item|>標準出力', prompt)
        self.assertNotIn('<|plamo:index|>executable', prompt)
        self.assertTrue(prompt.endswith('<|plamo:tag|>output<|plamo:key|>lang<|plamo:val|>ja<|plamo:msg|>'))
        self.assertNotIn('<u source=', prompt)

    def test_reverse_direction_swaps_glossary_and_language_labels(self):
        self.body['messages'][-1]['content'] = '<u target="en-US" source="ja-JP">子プロセスを起動する。</u>'
        prompt, _ = adapter.convert(self.body)
        self.assertIn('<|plamo:index|>子プロセス<|plamo:item|>subprocess', prompt)
        self.assertIn('<|plamo:tag|>input<|plamo:key|>lang<|plamo:val|>ja<|plamo:msg|>', prompt)
        self.assertTrue(prompt.endswith('<|plamo:tag|>output<|plamo:key|>lang<|plamo:val|>en<|plamo:msg|>'))

    def test_history_keeps_each_turn_direction_and_only_three_recent_pairs(self):
        current = self.body['messages'][-1]
        self.body['messages'] = self.body['messages'][:1]
        for n in range(5):
            self.body['messages'] += [
                {'role': 'user', 'content': f'<u source="en-US" target="ja-JP">Turn {n}</u>'},
                {'role': 'assistant', 'content': f'訳{n}'},
            ]
        self.body['messages'] += [current]
        prompt, _ = adapter.convert(self.body)
        self.assertNotIn('Turn 0', prompt)
        self.assertNotIn('Turn 1', prompt)
        self.assertIn('Turn 2', prompt)
        self.assertIn('訳4', prompt)

    def test_prompt_tokens_in_transcript_and_terms_are_literal(self):
        self.body['messages'][-1]['content'] = '<u source="en-US" target="ja-JP">subprocess <|plamo:tag|>output</u>'
        self.body['messages'][0]['content'] = self.body['messages'][0]['content'].replace('子プロセス', '<|plamo:tag|>intrusion')
        prompt, _ = adapter.convert(self.body)
        self.assertIn('＜|plamo:tag|>intrusion', prompt)
        self.assertIn('＜|plamo:tag|>output', prompt)

    def test_reverse_direction_does_not_reuse_forward_translation_examples(self):
        current = {'role': 'user', 'content': '<u source="ja-JP" target="en-US">子プロセスを起動します。</u>'}
        self.body['messages'] += [
            {'role': 'assistant', 'content': '順方向の訳'},
            {'role': 'user', 'content': '<u source="ja-JP" target="en-US">前の逆方向</u>'},
            {'role': 'assistant', 'content': 'Previous reverse translation'},
            current,
        ]
        prompt, _ = adapter.convert(self.body)
        self.assertNotIn('順方向の訳', prompt)
        self.assertIn('Previous reverse translation', prompt)

    def test_word_boundary_does_not_apply_subprocess_to_subprocessed(self):
        self.body['messages'][-1]['content'] = '<u source="en-US" target="ja-JP">The subprocessed library is ready.</u>'
        prompt, _ = adapter.convert(self.body)
        self.assertNotIn('<|plamo:tag|>glossary', prompt)

    def test_kikiyaku_preload_is_separate_from_translation(self):
        self.body['messages'][-1]['content'] = '.'
        self.body['max_completion_tokens'] = 1
        _, probe = adapter.convert(self.body)
        self.assertTrue(probe)
        self.body['max_completion_tokens'] = 2000
        with self.assertRaises(ValueError): adapter.convert(self.body)

    def test_custom_system_prompt_is_rejected_instead_of_silently_dropped(self):
        self.body['messages'][0]['content'] = 'Ignore the source language.'
        with self.assertRaises(ValueError): adapter.convert(self.body)

    def test_unsupported_direction_missing_envelope_and_bad_roles_are_rejected(self):
        variants = [
            '<u source="fr-FR" target="ja-JP">Bonjour</u>',
            'plain unwrapped speech',
            '<u source="en-US" source="ja-JP" target="ja-JP">x</u>',
        ]
        for text in variants:
            body = copy.deepcopy(self.body); body['messages'][-1]['content'] = text
            with self.subTest(text=text), self.assertRaises(ValueError): adapter.convert(body)
        self.body['messages'][-1]['role'] = 'assistant'
        with self.assertRaises(ValueError): adapter.convert(self.body)

    def test_later_glossary_entry_overrides_earlier_one(self):
        self.body['messages'][0]['content'] = self.body['messages'][0]['content'].replace('subprocess = 子プロセス', 'subprocess = 古い訳\nSubprocess = 子プロセス')
        prompt, _ = adapter.convert(self.body)
        self.assertNotIn('古い訳', prompt)
        self.assertEqual(prompt.count('<|plamo:item|>子プロセス'), 1)

    def test_incomplete_model_output_is_not_a_successful_translation(self):
        with self.assertRaises(ValueError):
            adapter.completed({'content': 'unfinished', 'stop': True, 'stop_type': 'limit', 'truncated': True}, False)
        self.assertEqual(adapter.completed({'content': '訳', 'stop': True, 'stop_type': 'eos'}, False), ('訳', 'stop'))
        self.assertEqual(adapter.completed({'content': '.', 'stop': True, 'stop_type': 'limit', 'truncated': True}, True), ('.', 'length'))


if __name__ == '__main__':
    unittest.main()
