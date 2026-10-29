#!/usr/bin/env python3
"""Pack a locally authored Oracle lexicon. Obfuscation is not encryption."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import tempfile

ROOT = Path(__file__).resolve().parent.parent
STOPWORDS = set("a an and are at be do for from i is it my not of on or should the to will я ли или не мне как на с со в из от это за что а".split())
CATEGORIES = {"selfHarm", "harmToPeople", "dangerToLife", "ambiguousRisk"}


def validate(payload):
    if not isinstance(payload, dict) or set(payload) != {"version", "entries"} or type(payload["version"]) is not int or payload["version"] != 1:
        raise ValueError("expected version 1 and an entries array")
    entries = payload["entries"]
    if not isinstance(entries, list) or len(entries) > 1000:
        raise ValueError("entries must be an array with at most 1000 entries")
    count = 0
    for entry in entries:
        if not isinstance(entry, dict) or set(entry) != {"category", "examples"} or not isinstance(entry["category"], str) or entry["category"] not in CATEGORIES:
            raise ValueError("each entry must contain a valid category and examples")
        examples = entry["examples"]
        if not isinstance(examples, list) or not examples:
            raise ValueError("examples must be a non-empty array")
        for example in examples:
            if not isinstance(example, str) or len(example.encode("utf-8")) > 2000:
                raise ValueError("each example must be a string of at most 2000 UTF-8 bytes")
            words = "".join(c if c.isalnum() else " " for c in example.lower().replace("ё", "е")).split()
            if not any(word not in STOPWORDS for word in words):
                raise ValueError("each example must contain at least one meaningful word")
            count += 1
    if count > 5000:
        raise ValueError("at most 5000 examples are supported")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=ROOT / "private/OracleSafetyLexicon.json")
    parser.add_argument("--output", type=Path, default=ROOT / "Sources/OracleGame/Resources/OracleSafetyLexicon.private.bin")
    args = parser.parse_args()
    if args.output.is_symlink():
        parser.error("output must not be a symlink")
    try:
        if args.input.stat().st_size > 1_048_576:
            raise ValueError("input exceeds 1 MiB")
        def unique_object(pairs):
            result = {}
            for key, value in pairs:
                if key in result:
                    raise ValueError("duplicate JSON key")
                result[key] = value
            return result

        payload = json.loads(args.input.read_text(encoding="utf-8"), object_pairs_hook=unique_object)
        validate(payload)
        encoded = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        if len(encoded) > 1_048_576:
            raise ValueError("encoded input exceeds 1 MiB")
        masked = bytes(value ^ ((index * 53 + 167) & 255) for index, value in enumerate(encoded))
        blob = b"OSL1" + struct.pack(">I", len(encoded)) + hashlib.sha256(encoded).digest() + masked
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=args.output.parent, delete=False) as stream:
            temporary = Path(stream.name)
            try:
                stream.write(blob)
                stream.flush()
                os.fsync(stream.fileno())
            except BaseException:
                temporary.unlink(missing_ok=True)
                raise
        try:
            os.replace(temporary, args.output)
        except BaseException:
            temporary.unlink(missing_ok=True)
            raise
        print(f"Packed {sum(len(e['examples']) for e in payload['entries'])} examples to {args.output}")
    except (OSError, ValueError, json.JSONDecodeError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
