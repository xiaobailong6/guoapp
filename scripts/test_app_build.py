import argparse
import base64
import os
from pathlib import Path
import platform
import plistlib
import runpy
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

from app_build import BuildVariant, add_variant_argument, record_native_build, verify_native_build
from configure_ios_branding import configure


def dart_defines(*values):
    return ','.join(base64.b64encode(value.encode()).decode() for value in values)


class AppBuildTests(unittest.TestCase):
    def test_native_core_rejects_mixed_editions_and_stale_packaged_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            library = Path(temporary) / 'libduanju_core.so'
            library.write_bytes(b'synthetic native core')
            with self.assertRaisesRegex(ValueError, '缺少有效构建记录'):
                verify_native_build(library, BuildVariant(True))
            record_native_build(library, BuildVariant(True),
                                platform='android', architecture='arm64')
            self.assertTrue(verify_native_build(library, BuildVariant(True))['allSources'])
            with self.assertRaisesRegex(ValueError, '站源配置不一致'):
                verify_native_build(library, BuildVariant(False))
            with self.assertRaisesRegex(ValueError, '内容与构建记录不一致'):
                verify_native_build(library, BuildVariant(True), packaged=b'old packaged core')
            library.write_bytes(b'replaced core')
            with self.assertRaisesRegex(ValueError, '内容与构建记录不一致'):
                verify_native_build(library, BuildVariant(True))

    def test_omitted_or_true_flag_builds_the_full_edition(self):
        for encoded in ['', dart_defines('ALL_SOURCES=true'), dart_defines('OTHER=true')]:
            variant = BuildVariant.from_dart_defines(encoded)
            self.assertTrue(variant.all_sources)
            self.assertEqual(variant.name, '真果鉴')
            self.assertEqual(variant.slug, 'zhenguojian')

    def test_full_edition_decodes_among_other_flutter_defines(self):
        variant = BuildVariant.from_dart_defines(dart_defines(
            'OTHER=中文', 'ALL_SOURCES=true', 'VALUE=a=b'))
        self.assertTrue(variant.all_sources)
        self.assertEqual(variant.name, '真果鉴')
        self.assertEqual(variant.slug, 'zhenguojian')

    def test_false_flag_selects_the_green_edition(self):
        for encoded in [dart_defines('ALL_SOURCES=false'),
                        dart_defines('OTHER=中文', 'ALL_SOURCES=false')]:
            variant = BuildVariant.from_dart_defines(encoded)
            self.assertFalse(variant.all_sources)
            self.assertEqual(variant.name, '绿果鉴')
            self.assertEqual(variant.slug, 'lvguojian')

    def test_variant_arguments_carry_the_green_edition_to_child_builds(self):
        self.assertEqual(BuildVariant(True).arguments, [])
        self.assertEqual(BuildVariant(False).arguments, ['--green-only'])
        for enabled in [True, False]:
            arguments = BuildVariant(enabled).flutter_arguments
            self.assertEqual(arguments, ['--dart-define=ALL_SOURCES=' + str(enabled).lower()])

    def test_build_scripts_parse_the_green_flag_and_keep_the_legacy_one(self):
        parser = argparse.ArgumentParser()
        add_variant_argument(parser)
        for arguments, expected in [
            ([], True),
            (['--all-sources'], True),
            (['--green-only'], False),
            (['--green-only', '--all-sources'], True),
        ]:
            with self.subTest(arguments=arguments):
                self.assertEqual(parser.parse_args(arguments).all_sources, expected)

    def test_ios_branding_can_switch_editions_without_replacing_bundle_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'Info.plist'
            original = {'CFBundleIdentifier': 'com.duanju.duanjuApp', 'CFBundleVersion': '9'}
            path.write_bytes(plistlib.dumps(original))
            for enabled in [True, False]:
                configure(path, dart_defines('ALL_SOURCES=' + str(enabled).lower()))
                actual = plistlib.loads(path.read_bytes())
                self.assertEqual(actual['CFBundleDisplayName'], '真果鉴' if enabled else '绿果鉴')
                self.assertEqual(actual['CFBundleName'], 'zhenguojian' if enabled else 'lvguojian')
                for key, value in original.items():
                    self.assertEqual(actual[key], value)

    @unittest.skipUnless(shutil.which('cmake'), 'CMake is unavailable')
    def test_windows_reads_defines_from_flutter_tool_environment(self):
        branding = Path(__file__).resolve().parents[1] / 'windows/runner/app_branding.cmake'
        for flags, expected in [
            ([], '绿果鉴'),
            (['ALL_SOURCES=true'], '真果鉴'),
            (['OTHER=true', 'ALL_SOURCES=false'], '绿果鉴'),
            (['ALL_SOURCES=true', 'ALL_SOURCES=false'], '绿果鉴'),
        ]:
            with self.subTest(flags=flags), tempfile.TemporaryDirectory() as temporary:
                script = Path(temporary) / 'check.cmake'
                result = Path(temporary) / 'name.txt'
                script.write_text(
                    'list(APPEND FLUTTER_TOOL_ENVIRONMENT "OTHER=1" "DART_DEFINES=' + dart_defines(*flags) + '")\n'
                    'include("' + branding.as_posix() + '")\n'
                    'file(WRITE "' + result.as_posix() + '" "${APP_DISPLAY_NAME}")\n',
                    encoding='utf-8',
                )
                subprocess.run(['cmake', '-P', str(script)], check=True, capture_output=True)
                self.assertEqual(result.read_text(encoding='utf-8'), expected)

    def test_android_and_windows_propagate_one_edition_to_core_flutter_and_package(self):
        root = Path(__file__).resolve().parent
        for target in ['android', 'windows']:
            for enabled in [True, False]:
                with self.subTest(target=target, all_sources=enabled):
                    script = root / f'build_{target}.py'
                    arguments = [str(script)] + ([] if enabled else ['--green-only'])
                    with mock.patch.object(sys, 'argv', arguments), \
                            mock.patch.dict(os.environ, {'PATH': '/tools'}, clear=True), \
                            mock.patch('platform.system', return_value='Windows'), \
                            mock.patch('shutil.which', return_value='/tools/flutter'), \
                            mock.patch('subprocess.run') as run:
                        runpy.run_path(str(script), run_name='__main__')
                    calls = [call.args[0] for call in run.call_args_list]
                    native = next(call for call in calls if any(str(arg).endswith('build_native.py') for arg in call))
                    flutter = next(call for call in calls if 'build' in call)
                    package = next(call for call in calls if any(str(arg).endswith('package_release.py') for arg in call))
                    self.assertEqual('--green-only' in native, not enabled)
                    self.assertEqual('--green-only' in package, not enabled)
                    self.assertIn('--dart-define=ALL_SOURCES=' + str(enabled).lower(), flutter)
                    self.assertIn('core.buildAllSources=' + str(enabled).lower(), BuildVariant(enabled).linker_flags)


if __name__ == '__main__':
    unittest.main()
