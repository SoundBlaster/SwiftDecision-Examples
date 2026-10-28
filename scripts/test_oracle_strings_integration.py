import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class HookIntegrationTests(unittest.TestCase):
    def test_hook_checks_staged_inputs_and_pinned_tool(self):
        with tempfile.TemporaryDirectory(prefix="strings-integration-") as temp:
            root = Path(temp)
            def run(*args, check=True):
                return subprocess.run(args, cwd=root, capture_output=True, text=True, check=check)
            def git(*args, check=True):
                return run("git", *args, check=check)
            git("init", "-q")
            (root / "tools").mkdir()
            git("clone", "-q", "--no-hardlinks", str(ROOT / "tools/StringCatalogDoctor"),
                "tools/StringCatalogDoctor")
            rev = run("git", "-C", "tools/StringCatalogDoctor", "rev-parse", "HEAD").stdout.strip()
            (root / ".githooks").mkdir()
            shutil.copy2(ROOT / ".githooks/pre-commit", root / ".githooks/pre-commit")
            shutil.copy2(ROOT / "Makefile", root / "Makefile")
            config = {"version": 1, "catalogs": [{"path": "sample.xcstrings"}],
                      "locales": ["es"], "baseline": "baseline.json"}
            (root / ".string-catalog-doctor.json").write_text(json.dumps(config))
            (root / "baseline.json").write_text('{"version":1,"issues":[]}')
            catalog = {"sourceLanguage": "en", "strings": {"Hello": {"localizations": {
                "es": {"stringUnit": {"state": "translated", "value": "Hola"}}
            }}}}
            (root / "sample.xcstrings").write_text(json.dumps(catalog))
            git("add", "Makefile", ".githooks", ".string-catalog-doctor.json",
                "baseline.json", "sample.xcstrings")
            git("update-index", "--add", "--cacheinfo", f"160000,{rev},tools/StringCatalogDoctor")
            catalog["strings"]["Hello"]["localizations"].clear()
            (root / "sample.xcstrings").write_text(json.dumps(catalog))
            self.assertEqual(run(".githooks/pre-commit", check=False).returncode, 0)
            git("add", "sample.xcstrings")
            result = run(".githooks/pre-commit", check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("es: 'Hello': missing", result.stdout + result.stderr)
            source = root / "tools/StringCatalogDoctor/string_catalog_doctor/__main__.py"
            source.write_text(source.read_text() + "\n# local modification\n")
            result = run(".githooks/pre-commit", check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("pinned revision", result.stderr)


if __name__ == "__main__":
    unittest.main()
