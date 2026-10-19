#!/usr/bin/env python3
"""Optional stdlib-only shape check; stdin is never persisted or echoed."""
import argparse
from decimal import Decimal, DecimalException
import json
import math
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
REPORT_CAP = 40
PATH_CAP = 240
VOCABULARY = {"$schema", "title", "description", "type", "properties", "items",
              "required", "additionalProperties", "enum", "minimum", "maximum"}
TYPES = {"object", "array", "string", "number", "integer", "boolean", "null"}


class CannotVerify(Exception):
    pass


class NoSchema(CannotVerify):
    pass


def number(value):
    if type(value) is Decimal:
        return value.is_finite()
    return type(value) in (int, float) and (type(value) is int or math.isfinite(value))


def integer(value):
    if not number(value):
        return False
    if type(value) is Decimal:
        return value == value.to_integral_value()
    return type(value) is int or value.is_integer()


def json_equal(a, b):
    if number(a) and number(b):
        return a == b
    if type(a) is not type(b):
        return False
    if isinstance(a, list):
        return len(a) == len(b) and all(json_equal(x, y) for x, y in zip(a, b))
    if isinstance(a, dict):
        return a.keys() == b.keys() and all(json_equal(a[k], b[k]) for k in a)
    return a == b


def strict_json(text):
    def pairs(entries):
        result = {}
        for key, value in entries:
            if key in result:
                raise ValueError("duplicate key")
            result[key] = value
        return result

    def constant(_):
        raise ValueError("non-JSON constant")

    def whole(token):
        # Python's host integer digit limit must not turn valid JSON into invalid shape.
        try:
            return int(token)
        except ValueError:
            return Decimal(token)

    return json.loads(text, object_pairs_hook=pairs, parse_constant=constant,
                      parse_float=Decimal, parse_int=whole)


def parse_return(text):
    text = text.strip()
    if text.startswith("```"):
        match = re.fullmatch(r"```json[ \t]*\r?\n(.*?)\r?\n```", text, re.DOTALL)
        if not match:
            raise ValueError("expected one JSON fence")
        text = match[1]
    return strict_json(text)


def inspect_schema(node):
    """Reject unknown keywords and malformed supported constructs before checking data."""
    if not isinstance(node, dict) or set(node) - VOCABULARY:
        raise CannotVerify("unsupported_schema_construct")
    for key in ("$schema", "title", "description"):
        if key in node and not isinstance(node[key], str):
            raise CannotVerify("malformed_schema_metadata")
    if "$schema" in node and node["$schema"] != "https://json-schema.org/draft/2020-12/schema":
        raise CannotVerify("unsupported_schema_dialect")
    if "type" in node and (not isinstance(node["type"], str) or node["type"] not in TYPES):
        raise CannotVerify("unsupported_schema_type")
    if "properties" in node:
        if not isinstance(node["properties"], dict):
            raise CannotVerify("malformed_schema_properties")
        for child in node["properties"].values():
            inspect_schema(child)
    if "items" in node:
        inspect_schema(node["items"])
    if "required" in node:
        values = node["required"]
        if not isinstance(values, list) or not all(isinstance(v, str) for v in values) or len(set(values)) != len(values):
            raise CannotVerify("malformed_schema_required")
    if "additionalProperties" in node:
        value = node["additionalProperties"]
        if isinstance(value, dict):
            inspect_schema(value)
        elif type(value) is not bool:
            raise CannotVerify("malformed_schema_additional_properties")
    if "enum" in node:
        values = node["enum"]
        if not isinstance(values, list) or not values or any(json_equal(v, w) for i, v in enumerate(values) for w in values[:i]):
            raise CannotVerify("malformed_schema_enum")
    for key in ("minimum", "maximum"):
        if key in node and not number(node[key]):
            raise CannotVerify("malformed_schema_bound")


def validate(value, schema):
    inspect_schema(schema)
    findings = []
    total = 0

    def add(path, code):
        nonlocal total
        total += 1
        if len(findings) < REPORT_CAP:
            findings.append({"path": path[:PATH_CAP], "code": code})

    def walk(data, node, path):
        checks = {"object": isinstance(data, dict), "array": isinstance(data, list),
                  "string": isinstance(data, str), "number": number(data),
                  "integer": integer(data),
                  "boolean": type(data) is bool, "null": data is None}
        if "type" in node and not checks[node["type"]]:
            add(path, "type")
            return
        if "enum" in node and not any(json_equal(data, v) for v in node["enum"]):
            add(path, "enum")
        if number(data):
            for key, failed in (("minimum", data < node.get("minimum", data)),
                                ("maximum", data > node.get("maximum", data))):
                if failed:
                    add(path, key)
        if isinstance(data, dict):
            # Report unknown/missing names at their containing object, never echo child keys.
            for key in node.get("required", []):
                if key not in data:
                    add(path, "required:" + key[:80])
            props = node.get("properties", {})
            for key, item in data.items():
                if key in props:
                    escaped = key.replace("~", "~0").replace("/", "~1")
                    walk(item, props[key], path + "/" + escaped)
                elif node.get("additionalProperties") is False:
                    add(path, "additionalProperties")
                elif isinstance(node.get("additionalProperties"), dict):
                    walk(item, node["additionalProperties"], path)
        if isinstance(data, list) and "items" in node:
            for index, item in enumerate(data):
                walk(item, node["items"], path + "/" + str(index))

    walk(value, schema, "")
    return findings, total


def load_contract(agent, root=ROOT):
    if not re.fullmatch(r"[a-z][a-z0-9-]*", agent):
        raise CannotVerify("invalid_agent_id")
    directory = (root / "agents").resolve()
    if directory.parent != root.resolve() or directory.name != "agents":
        raise CannotVerify("agents_directory_outside_root")
    md = directory / (agent + ".md")
    if md.resolve().parent != directory:
        raise CannotVerify("agent_path_outside_agents")
    text = md.read_text(encoding="utf-8-sig")
    fm = re.match(r"\A---\r?\n(.*?)\r?\n---(?:\r?\n|$)", text, re.DOTALL)
    if not fm:
        raise CannotVerify("missing_frontmatter")
    declarations = re.findall(r"^output_schema:(.*)$", fm[1], re.MULTILINE)
    if not declarations:
        raise NoSchema("no_schema")
    if len(declarations) != 1:
        raise CannotVerify("ambiguous_schema_declaration")
    declared = declarations[0].strip()
    if declared != "./" + agent + ".schema.json":
        raise CannotVerify("schema_not_exact_sibling")
    path = directory / (agent + ".schema.json")
    if path.resolve().parent != directory:
        raise CannotVerify("schema_path_outside_agents")
    schema = strict_json(path.read_text(encoding="utf-8"))
    inspect_schema(schema)
    return schema, "agents/" + path.name, text


def check(agent, text, root=ROOT):
    try:
        schema, path, _ = load_contract(agent, root)
        try:
            data = parse_return(text)
        except (ValueError, RecursionError):
            return 1, {"status": "invalid", "schema": path, "diagnostics": [{"path": "", "code": "malformed_json_or_fence"}]}
        findings, total = validate(data, schema)
        return (1 if total else 0), {"status": "invalid" if total else "valid", "schema": path,
                                    "diagnostics": findings, "errors_total": total,
                                    "truncated": total > REPORT_CAP}
    except NoSchema:
        return 2, {"status": "no_schema", "diagnostics": []}
    except CannotVerify as exc:
        return 2, {"status": "cannot_verify", "diagnostics": [{"path": "", "code": str(exc)}]}
    except (OSError, ValueError, UnicodeError, RecursionError, OverflowError, DecimalException):
        return 2, {"status": "cannot_verify", "diagnostics": [{"path": "", "code": "contract_unreadable_or_malformed"}]}


def check_examples(root=ROOT):
    results = []
    exit_code = 0
    for md in sorted((root / "agents").glob("*.md")):
        try:
            _, path, text = load_contract(md.stem, root)
            section = re.search(r"^#{2,3} Structured Return[^\n]*\n(.*?)(?=^#{1,3} |\Z)", text, re.MULTILINE | re.DOTALL)
            examples = re.findall(r"```json[ \t]*\r?\n.*?\r?\n```", section[1], re.DOTALL) if section else []
            if not examples:
                raise CannotVerify("missing_structured_return_example")
            for index, example in enumerate(examples):
                code, report = check(md.stem, example, root)
                results.append({"agent": md.stem, "example": index + 1, **report})
                exit_code = max(exit_code, code)
        except NoSchema:
            continue
        except (CannotVerify, OSError, ValueError, RecursionError, DecimalException):
            exit_code = 2
            results.append({"agent": md.stem, "status": "cannot_verify"})
    if not results:
        exit_code = 2
    return exit_code, {"status": ("valid", "invalid", "cannot_verify")[exit_code], "examples": results[:REPORT_CAP],
                       "examples_total": len(results), "truncated": len(results) > REPORT_CAP}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--agent")
    group.add_argument("--check-examples", action="store_true")
    args = parser.parse_args()
    try:
        code, report = check_examples() if args.check_examples else check(args.agent, sys.stdin.read())
    except (OSError, UnicodeError, RecursionError):
        code, report = 2, {"status": "cannot_verify", "diagnostics": [{"path": "", "code": "input_unreadable"}]}
    print(json.dumps(report, ensure_ascii=True))
    return code


if __name__ == "__main__":
    sys.exit(main())
