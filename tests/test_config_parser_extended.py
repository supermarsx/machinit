import os
import subprocess
import tempfile
import unittest

# Adjust path to find the parser script relative to project root.
PROJECT_ROOT = os.path.abspath(
    os.path.join(
        os.path.dirname(__file__),
        "..",
    )
)
PARSER_SCRIPT = os.path.join(PROJECT_ROOT, "scripts", "lib", "config_parser.py")


class TestConfigParserExtended(unittest.TestCase):
    def setUp(self):
        self.test_toml = tempfile.NamedTemporaryFile(mode="w+", delete=False)
        self.test_toml.write("""
[section]
key = "value"
nested.key = "nested_value"

[types]
bool_true = true
bool_false = false
int_val = 42
float_val = 3.14
list_val = ["a", "b", "c"]
empty_list = []

[deep]
[deep.level2]
[deep.level2.level3]
val = "deep_value"
""")
        self.test_toml.close()

    def tearDown(self):
        os.unlink(self.test_toml.name)

    def run_parser(self, key):
        result = subprocess.run(
            ["python3", PARSER_SCRIPT, self.test_toml.name, key],
            capture_output=True,
            text=True,
        )
        return result.stdout.strip()

    def test_nested_keys(self):
        # Parser splits by dots, so deep structures should succeed
        # even without quoted keys.
        self.assertEqual(
            self.run_parser("deep.level2.level3.val"),
            "deep_value",
        )

    def test_list_output(self):
        # The parser outputs lists as space-separated quoted strings:
        # "a" "b" "c"
        self.assertEqual(
            self.run_parser("types.list_val"),
            '"a" "b" "c"',
        )
        self.assertEqual(self.run_parser("types.empty_list"), "")

    def test_bool_output(self):
        # The parser outputs booleans as lowercase string
        self.assertEqual(self.run_parser("types.bool_true"), "true")
        self.assertEqual(self.run_parser("types.bool_false"), "false")

    def test_numeric_output(self):
        self.assertEqual(self.run_parser("types.int_val"), "42")
        self.assertEqual(self.run_parser("types.float_val"), "3.14")

    def test_missing_file(self):
        result = subprocess.run(
            ["python3", PARSER_SCRIPT, "nonexistent.toml", "key"],
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(result.returncode, 0)

    def test_invalid_toml(self):
        bad_toml = tempfile.NamedTemporaryFile(mode="w+", delete=False)
        bad_toml.write("this is not toml")
        bad_toml.close()

        # Parser catches exceptions, prints errors to stderr, and returns "".
        result = subprocess.run(
            ["python3", PARSER_SCRIPT, bad_toml.name, "key"],
            capture_output=True,
            text=True,
        )
        os.unlink(bad_toml.name)

        self.assertEqual(result.stdout.strip(), "")
        self.assertIn("Error reading config", result.stderr)


if __name__ == "__main__":
    unittest.main()
