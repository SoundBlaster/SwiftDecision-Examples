import hashlib
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "pack-oracle-safety-lexicon.py"


class PackLexiconTests(unittest.TestCase):
    def run_pack(self, source, output):
        return subprocess.run(["python3", str(SCRIPT), "--input", str(source), "--output", str(output)],
                              capture_output=True, text=True)

    def test_binary_format_hides_plain_text_and_round_trips(self):
        with tempfile.TemporaryDirectory() as directory:
            source, output = Path(directory) / "input.json", Path(directory) / "output.bin"
            source.write_text(json.dumps({"version": 1, "entries": [
                {"category": "dangerToLife", "examples": ["zebra silver cloud"]}]}))
            result = self.run_pack(source, output)
            self.assertEqual(result.returncode, 0, result.stderr)
            packed = output.read_bytes()
            self.assertEqual(packed[:4], b"OSL1")
            self.assertNotIn(b"zebra silver cloud", packed)
            decoded = bytes(value ^ ((index * 53 + 167) & 255) for index, value in enumerate(packed[40:]))
            self.assertEqual(struct.unpack(">I", packed[4:8])[0], len(decoded))
            self.assertEqual(packed[8:40], hashlib.sha256(decoded).digest())
            self.assertEqual(json.loads(decoded), json.loads(source.read_text()))

    def test_invalid_input_does_not_replace_previous_output(self):
        with tempfile.TemporaryDirectory() as directory:
            source, output = Path(directory) / "input.json", Path(directory) / "output.bin"
            output.write_bytes(b"existing")
            for text in ['{"version":true,"entries":[]}', '{"version":1,"version":2,"entries":[]}',
                         '{"version":1,"entries":[{"category":"invalid","examples":["x"]}]}']:
                source.write_text(text)
                self.assertNotEqual(self.run_pack(source, output).returncode, 0)
                self.assertEqual(output.read_bytes(), b"existing")


if __name__ == "__main__":
    unittest.main()
