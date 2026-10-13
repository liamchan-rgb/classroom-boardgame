"""Toolchain failure-path tests; these do not substitute for an Xcode build."""
import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("select_ci_xcode", Path(__file__).resolve().parents[1] / "select_ci_xcode.py")
selector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selector)


class XcodeSelectionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.project = Path(self.temporary.name) / "App.xcodeproj"
        self.project.mkdir()
        (self.project / "project.pbxproj").write_text('"IPHONEOS_DEPLOYMENT_TARGET" = "27.0";')

    def select(self, sdks):
        def query(command, developer):
            if command[0] == "xcodebuild":
                return "Xcode test fixture"
            return sdks[developer][0 if command[2] == "iphoneos" else 1]
        with patch.object(selector.glob, "glob", return_value=list(sdks)), \
             patch.object(selector.os, "environ", {}), \
             patch.object(selector.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "/old/Xcode", "")), \
             patch.object(selector, "query", side_effect=query), \
             contextlib.redirect_stdout(io.StringIO()):
            return selector.select(self.project)

    def test_old_default_is_rejected_in_favor_of_compatible_installation(self):
        compatible = "/Applications/Xcode New.app/Contents/Developer"
        selected = self.select({"/old/Xcode": ("26.4", "26.4"), compatible: ("27.0", "27.0")})
        self.assertEqual(selected, compatible)

    def test_device_sdk_cannot_hide_incompatible_simulator_sdk(self):
        with self.assertRaisesRegex(ValueError, "no Xcode"):
            self.select({"/old/Xcode": ("28.0", "26.4")})

    def test_missing_required_sdk_fails_without_lowering_project_target(self):
        original = (self.project / "project.pbxproj").read_bytes()
        with self.assertRaisesRegex(ValueError, ">= 27.0"):
            self.select({"/old/Xcode": ("26.4", "26.4")})
        self.assertEqual((self.project / "project.pbxproj").read_bytes(), original)

    def test_inconsistent_debug_release_minimum_is_reported(self):
        with (self.project / "project.pbxproj").open("a") as out:
            out.write('"IPHONEOS_DEPLOYMENT_TARGET" = "26.0";')
        with self.assertRaisesRegex(ValueError, "consistent project iOS minimum"):
            self.select({"/old/Xcode": ("28.0", "28.0")})


if __name__ == "__main__":
    unittest.main()
