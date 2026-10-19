#!/usr/bin/env python3
"""Checker regression tests; fixtures and child returns stay in memory."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("return_checker", Path(__file__).with_name("check-subagent-return.py"))
checker = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checker)


def sample(schema):
    if "enum" in schema:
        return copy.deepcopy(schema["enum"][0])
    kind = schema.get("type")
    if kind == "object":
        return {k: sample(v) for k, v in schema.get("properties", {}).items()}
    if kind == "array":
        return [sample(schema["items"])]
    return {"string": "test", "number": 0.5, "integer": 1,
            "boolean": True, "null": None}[kind]


def nodes(value, schema, path=()):
    yield value, schema, path
    if schema.get("type") == "object":
        for key, child in schema.get("properties", {}).items():
            yield from nodes(value[key], child, path + (key,))
    if schema.get("type") == "array":
        yield from nodes(value[0], schema["items"], path + (0,))


def replace(value, path, replacement):
    if not path:
        return replacement
    result = copy.deepcopy(value)
    current = result
    for key in path[:-1]:
        current = current[key]
    current[path[-1]] = replacement
    return result


class CurrentSchemas(unittest.TestCase):
    def test_all_schemas_positive_and_recursive_negative(self):
        files = sorted((checker.ROOT / "agents").glob("*.schema.json"))
        self.assertEqual(len(files), 8)
        for file in files:
            agent = file.name.removesuffix(".schema.json")
            schema, _, _ = checker.load_contract(agent)
            value = sample(schema)
            with self.subTest(agent=agent, case="positive"):
                self.assertEqual(checker.check(agent, json.dumps(value))[0], 0)
            for data, node, path in nodes(value, schema):
                wrong = {"object": [], "array": {}, "string": 7,
                         "number": True, "integer": True, "boolean": 1}[node["type"]]
                with self.subTest(agent=agent, path=path, case="type"):
                    self.assertEqual(checker.check(agent, json.dumps(replace(value, path, wrong)))[0], 1)
                for key in node.get("required", []):
                    bad = copy.deepcopy(data)
                    del bad[key]
                    with self.subTest(agent=agent, path=path, missing=key):
                        self.assertEqual(checker.check(agent, json.dumps(replace(value, path, bad)))[0], 1)
                if node.get("additionalProperties") is False:
                    bad = {**data, "unexpected": "sensitive"}
                    with self.subTest(agent=agent, path=path, case="additional"):
                        self.assertEqual(checker.check(agent, json.dumps(replace(value, path, bad)))[0], 1)
                if "enum" in node:
                    with self.subTest(agent=agent, path=path, case="enum"):
                        self.assertEqual(checker.check(agent, json.dumps(replace(value, path, "not-an-enum")))[0], 1)
                for bound in ("minimum", "maximum"):
                    if bound in node:
                        for delta, expected in ((0, 0), (-1 if bound == "minimum" else 1, 1)):
                            with self.subTest(agent=agent, path=path, bound=bound, delta=delta):
                                bad = replace(value, path, node[bound] + delta)
                                self.assertEqual(checker.check(agent, json.dumps(bad))[0], expected)

    def test_examples(self):
        code, report = checker.check_examples()
        self.assertEqual(code, 0, report)
        self.assertGreaterEqual(report["examples_total"], 8)


class ParserAndVocabulary(unittest.TestCase):
    def test_single_json_or_json_fence(self):
        for text in ('{"a": 1}', ' \n```json\n{"a": 1}\n```\n ', '```json\r\n{}\r\n```'):
            checker.parse_return(text)
        for text in ('{} {}', 'before {}', '{} after', '```\n{}\n```',
                     '```JSON\n{}\n```', '```json\n{}\n```\nprose',
                     '```json\n{}\n```\n```json\n{}\n```', '{', '',
                     '{"a":1,"a":2}', '{"n":NaN}', '{"n":Infinity}'):
            with self.subTest(text=text):
                with self.assertRaises(ValueError):
                    checker.parse_return(text)
                self.assertEqual(checker.check("coder", text)[0], 1)

    def test_numbers_not_bools_and_integer_semantics(self):
        for kind in ("number", "integer"):
            self.assertTrue(checker.validate(True, {"type": kind})[1])
            self.assertFalse(checker.validate(1.0, {"type": kind})[1])
        self.assertTrue(checker.validate(1.5, {"type": "integer"})[1])
        self.assertTrue(checker.validate(1, {"type": "boolean"})[1])
        self.assertTrue(checker.validate(True, {"enum": [1]})[1])
        self.assertTrue(checker.validate(float("inf"), {"type": "number"})[1])
        self.assertFalse(checker.validate(None, {"type": "null"})[1])
        self.assertFalse(checker.validate(1, {"enum": [1.0]})[1])
        self.assertFalse(checker.validate(checker.parse_return("1.0"), {"type": "integer"})[1])
        self.assertFalse(checker.validate(checker.parse_return("1e400"), {"type": "number"})[1])
        self.assertFalse(checker.validate(checker.parse_return("1e400"), {"type": "integer"})[1])
        self.assertFalse(checker.validate(checker.parse_return("9" * 5000), {"type": "integer"})[1])
        self.assertFalse(checker.validate(checker.parse_return('{"a":[1.0]}'), {"enum": [{"a": [1]}]})[1])
        self.assertTrue(checker.validate({"a": [True]}, {"enum": [{"a": [1]}]})[1])
        self.assertEqual(checker.check("coder", '{"files_changed":[],"tests_run":true,"tests_passed":true,"summary":"ok","confidence":1e400}')[0], 1)

    def test_unsupported_or_malformed_schema_fails_loud(self):
        cases = [{"$ref": "x"}, {"allOf": []}, {"minItems": 1}, {"pattern": "x"},
                 {"type": ["string", "null"]}, {"type": "bogus"}, True,
                 {"properties": []}, {"required": "x"}, {"required": ["x", "x"]},
                 {"enum": []}, {"enum": [1, 1.0]}, {"items": []},
                 {"additionalProperties": "false"}, {"minimum": True},
                 {"maximum": "1"}, {"title": 1}, {"description": False},
                 {"$schema": "http://json-schema.org/draft-07/schema#"},
                 {"properties": {"unused": {"$ref": "hidden"}}}]
        for schema in cases:
            with self.subTest(schema=schema):
                with self.assertRaises(checker.CannotVerify):
                    checker.validate({}, schema)

    def test_supported_vocabulary_without_explicit_types(self):
        self.assertTrue(checker.validate({}, {"required": ["x"]})[1])
        self.assertTrue(checker.validate(["x"], {"items": {"type": "number"}})[1])
        self.assertFalse(checker.validate({"x": 1}, {"additionalProperties": {"type": "number"}})[1])
        self.assertTrue(checker.validate({"x": "secret"}, {"additionalProperties": {"type": "number"}})[1])

    def test_report_cap_paths_and_no_child_data(self):
        schema = {"type": "array", "items": {"type": "object", "properties": {
            "known": {"type": "string"}}, "required": ["known"], "additionalProperties": False}}
        findings, total = checker.validate([{"known": False, "SECRET-KEY": "SECRET-VALUE"}] * 100, schema)
        self.assertEqual(total, 200)
        self.assertEqual(len(findings), checker.REPORT_CAP)
        self.assertEqual(findings[0]["path"], "/0/known")
        self.assertNotIn("SECRET", json.dumps(findings))
        findings, _ = checker.validate({"x" * 500: 1}, {"properties": {"x" * 500: {"type": "string"}}})
        self.assertLessEqual(len(findings[0]["path"]), checker.PATH_CAP)
        code, report = checker.check("coder", json.dumps({"files_changed": [False] * 100}))
        self.assertEqual(code, 1)
        self.assertTrue(report["truncated"])


class ContractAndCLI(unittest.TestCase):
    def test_prose_only_and_invalid_ids(self):
        for agent in ("delivery", "orchestrator", "external-scout"):
            code, report = checker.check(agent, "prose")
            self.assertEqual(code, 2)
            self.assertEqual(report["status"], "no_schema")
        for agent in ("../coder", "coder/../reviewer", "C:\\coder", "coder.md", "missing"):
            self.assertEqual(checker.check(agent, "{}")[0], 2)

    def test_frontmatter_and_sibling_fail_closed(self):
        for text in ("no frontmatter", "---\noutput_schema: ./coder.schema.json\n",
                     "---\noutput_schema: ../coder.schema.json\n---\n",
                     "---\noutput_schema: /outside.json\n---\n",
                     "---\noutput_schema: ./reviewer.schema.json\n---\n",
                     "---\noutput_schema: ./coder.schema.json\noutput_schema: ./coder.schema.json\n---\n"):
            with self.subTest(text=text), patch.object(Path, "read_text", return_value=text):
                self.assertEqual(checker.check("coder", "{}")[0], 2)

    def test_schema_containment(self):
        original = Path.resolve

        def resolve(path, *args, **kwargs):
            if path.name == "coder.schema.json":
                return checker.ROOT.parent / "outside.json"
            return original(path, *args, **kwargs)

        with patch.object(Path, "resolve", resolve):
            code, report = checker.check("coder", "{}")
            self.assertEqual(code, 2)
            self.assertEqual(report["diagnostics"][0]["code"], "schema_path_outside_agents")

    def test_agents_directory_containment(self):
        original = Path.resolve

        def resolve(path, *args, **kwargs):
            if path.name == "agents":
                return checker.ROOT.parent / "external-agents"
            return original(path, *args, **kwargs)

        with patch.object(Path, "resolve", resolve):
            self.assertEqual(checker.check("coder", "{}")[0], 2)

    def test_unsupported_contract_status(self):
        original = Path.read_text

        def read(path, *args, **kwargs):
            if path.name == "coder.schema.json":
                return '{"$ref":"external.json"}'
            return original(path, *args, **kwargs)

        with patch.object(Path, "read_text", read):
            self.assertEqual(checker.check("coder", "{}")[0], 2)
            self.assertEqual(checker.check_examples()[0], 2)

    def test_cli_exit_codes_and_stdout_json(self):
        schema, _, _ = checker.load_contract("coder")
        for agent, text, code in (("coder", json.dumps(sample(schema)), 0),
                                  ("coder", "raw-sensitive-child", 1),
                                  ("delivery", "prose", 2)):
            result = subprocess.run([sys.executable, str(Path(__file__).with_name("check-subagent-return.py")),
                                     "--agent", agent], input=text, text=True, capture_output=True)
            self.assertEqual(result.returncode, code, result.stderr)
            json.loads(result.stdout)
            self.assertNotIn("raw-sensitive-child", result.stdout)


if __name__ == "__main__":
    unittest.main()
