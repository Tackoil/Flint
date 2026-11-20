"""Exercise the build CLI without invoking Xcode or opening app windows."""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest


class BuildHelperTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="flint-build-helper-")
        self.addCleanup(directory.cleanup)
        self.project = Path(directory.name) / "Project with spaces"
        source = Path(__file__).resolve().parents[2]
        shutil.copytree(source / "scripts", self.project / "scripts")
        (self.project / "Config").mkdir()
        self.config = self.project / "Config/Features.xcconfig"
        self.original_config = "FLINT_FEATURES = FLINT_CALCULATOR FLINT_COLORS FLINT_QR\n"
        self.config.write_text(self.original_config)
        self.bin = self.project / "bin"
        self.bin.mkdir()
        builder = self.bin / "xcodebuild"
        builder.write_text("#!/bin/sh\nprintf '%s\\n' \"$@\"\n")
        builder.chmod(0o755)

    def run_build(self, *arguments, input_text=""):
        return subprocess.run(
            ["sh", str(self.project / "scripts/build.sh"), *arguments],
            input=input_text,
            capture_output=True,
            text=True,
            env={**os.environ, "PATH": f"{self.bin}:{os.environ['PATH']}"},
            timeout=10,
        )

    def test_default_build_opens_picker_and_preserves_configuration(self):
        result = self.run_build(input_text="\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Choose features", result.stderr)
        self.assertIn("FLINT_FEATURES=FLINT_CALCULATOR FLINT_COLORS FLINT_QR", result.stdout.splitlines())
        self.assertIn("Debug", result.stdout.splitlines())
        self.assertEqual(self.config.read_text(), self.original_config)

    def test_build_arguments_skip_picker(self):
        result = self.run_build("-configuration", "Release")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("FLINT_FEATURES=", result.stdout)
        self.assertNotIn("Choose features", result.stderr)
        self.assertIn("Release", result.stdout.splitlines())

    def test_interactive_defaults_and_build_arguments(self):
        result = self.run_build(
            "--interactive", "-configuration", "Release",
            "-derivedDataPath", "Build output with spaces", input_text="\n",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = result.stdout.splitlines()
        self.assertIn("FLINT_FEATURES=FLINT_CALCULATOR FLINT_COLORS FLINT_QR", arguments)
        self.assertEqual(arguments.count("-configuration"), 1)
        self.assertEqual(arguments.count("-derivedDataPath"), 1)
        self.assertIn("Build output with spaces", arguments)
        self.assertIn("Release", arguments)
        self.assertIn("1 [x] calculator", result.stderr)
        self.assertIn("2 [ ] timestamps", result.stderr)
        self.assertEqual(self.config.read_text(), self.original_config)

    def test_toggle_features_and_recover_from_invalid_input(self):
        result = self.run_build("-i", input_text="invalid\n1\n4\n\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("FLINT_FEATURES=FLINT_COLORS FLINT_NUMBER_BASES FLINT_QR", result.stdout.splitlines())
        self.assertIn("Choose a number", result.stderr)

    def test_empty_and_whitespace_configuration(self):
        for flags, expected in (("", ""), ("FLINT_CALCULATOR\tFLINT_QR\r", "FLINT_CALCULATOR FLINT_QR")):
            with self.subTest(flags=flags):
                self.config.write_text(f"  FLINT_FEATURES = {flags}\n")
                result = self.run_build("--interactive", input_text="\n")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(f"FLINT_FEATURES={expected}", result.stdout.splitlines())

    def test_all_none_and_individual_features(self):
        cases = [
            ("a\n\n", "FLINT_SYSTEM_ACTIONS"),
            ("n\n\n", ""),
            ("n\n9\n\n", "FLINT_SYSTEM_ACTIONS"),
            ("a\nn\n6\n\n", "FLINT_TRANSLATION"),
        ]
        for input_text, expected in cases:
            with self.subTest(input_text=input_text):
                result = self.run_build("--interactive", input_text=input_text)
                self.assertEqual(result.returncode, 0, result.stderr)
                flags = next(line for line in result.stdout.splitlines() if line.startswith("FLINT_FEATURES="))
                self.assertIn(expected, flags)
                if input_text != "a\n\n":
                    self.assertEqual(flags, f"FLINT_FEATURES={expected}")

    def test_cancel_and_end_of_input_never_build(self):
        for arguments in ((), ("--interactive",)):
            for input_text in ("q\n", "", "n\n"):
                with self.subTest(arguments=arguments, input_text=input_text):
                    result = self.run_build(*arguments, input_text=input_text)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(result.stdout, "")
                    self.assertIn("cancelled", result.stderr)

    def test_explicit_feature_selection(self):
        result = self.run_build("--features", "calculator,qr")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("FLINT_FEATURES=FLINT_CALCULATOR FLINT_QR", result.stdout.splitlines())
        for arguments in (("--features",), ("--features", "unknown")):
            with self.subTest(arguments=arguments):
                result = self.run_build(*arguments)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")

    def test_help_does_not_build(self):
        result = self.run_build("--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--interactive", result.stdout)
        self.assertNotIn("-project", result.stdout.splitlines())


if __name__ == "__main__":
    unittest.main()
