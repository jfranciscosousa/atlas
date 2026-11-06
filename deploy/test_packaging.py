#!/usr/bin/env python3
"""Dependency-free packaging tests: python3 -m unittest discover -s deploy -v.

Uses only disposable directories and a stub release; never starts Atlas or a DB.
"""
import fcntl
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PUBLISH = ROOT / "deploy/publish-assets"
ENTRYPOINT = ROOT / "deploy/entrypoint"


class PublisherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="atlas-packaging-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "packaged"
        self.store = self.root / "retained"
        self.source.mkdir()
        self.store.mkdir()
        self.asset("index-abcdefgh.js", b"current build")

    def asset(self, name, content=b"public asset"):
        path = self.source / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        return path

    def run_publish(self, success=True, source=None, store=None):
        result = subprocess.run(
            [str(PUBLISH), str(source or self.source), str(store or self.store)],
            text=True, capture_output=True, timeout=20,
        )
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual([p for p in self.store.glob(".publish.*") if p.name != ".publish.lock"],
                         [], "staging files leaked")
        return result

    def test_append_idempotently_and_retain_history(self):
        old = self.store / "old-12345678.js"
        old.write_bytes(b"previous deployment")
        self.asset("fonts/font-ABCDEFGH.woff2")
        self.run_publish()
        current = self.store / "index-abcdefgh.js"
        original_inode = current.stat().st_ino
        self.run_publish()
        self.assertEqual(current.read_bytes(), b"current build")
        self.assertEqual(current.stat().st_ino, original_inode)
        self.assertEqual(stat.S_IMODE(current.stat().st_mode), 0o444)
        self.assertEqual(old.read_bytes(), b"previous deployment")
        self.assertTrue((self.store / "fonts/font-ABCDEFGH.woff2").is_file())

    def test_maps_and_html_never_enter_the_store(self):
        for name in ["index.html", "nested/page.HTML", "index-abcdefgh.js.map", "data.MAP"]:
            self.asset(name, b"must remain private to the image")
        self.run_publish()
        files = {p.relative_to(self.store).as_posix() for p in self.store.rglob("*") if p.is_file()}
        self.assertEqual(files, {"index-abcdefgh.js", ".publish.lock"})

    def test_collision_fails_before_any_new_asset_is_published(self):
        self.asset("a-new-12345678.css")
        collision = self.store / "index-abcdefgh.js"
        collision.write_bytes(b"different existing bytes")
        result = self.run_publish(success=False)
        self.assertIn("collision", result.stderr)
        self.assertFalse((self.store / "a-new-12345678.css").exists())
        self.assertEqual(collision.read_bytes(), b"different existing bytes")

    def test_rejects_unsafe_or_unversioned_names(self):
        for name in ["bad name-12345678.js", "bad\nname-12345678.js", ".hidden-12345678.js",
                     "-option-12345678.js", "index.js", "private-12345678.exs",
                     "page-12345678.html.gz"]:
            with self.subTest(name=name):
                bad = self.asset(name)
                self.run_publish(success=False)
                bad.unlink()
        self.assertFalse((self.store / "index-abcdefgh.js").exists())

    def test_rejects_source_symlinks_including_maps_and_directories(self):
        outside = self.root / "outside"
        outside.mkdir()
        (outside / "secret").write_bytes(b"not public")
        for name, target in [("link-12345678.js", outside / "secret"),
                             ("link.map", outside / "secret"), ("linked", outside)]:
            with self.subTest(name=name):
                link = self.source / name
                link.symlink_to(target)
                self.run_publish(success=False)
                link.unlink()
        self.assertFalse((self.store / "index-abcdefgh.js").exists())

    def test_rejects_source_special_files(self):
        os.mkfifo(self.source / "pipe-12345678.js")
        self.run_publish(success=False)

    def test_rejects_destination_symlink_targets_even_when_bytes_match(self):
        outside = self.root / "outside.js"
        outside.write_bytes(b"current build")
        (self.store / "index-abcdefgh.js").symlink_to(outside)
        self.run_publish(success=False)
        self.assertEqual(outside.read_bytes(), b"current build")

    def test_rejects_destination_directory_symlinks_and_lock_symlinks(self):
        outside = self.root / "outside"
        outside.mkdir()
        self.asset("nested/font-12345678.woff2")
        link = self.store / "nested"
        link.symlink_to(outside)
        self.run_publish(success=False)
        link.unlink()
        (self.store / ".publish.lock").unlink()
        (self.store / ".publish.lock").symlink_to(outside / "lock")
        self.run_publish(success=False)
        self.assertEqual(list(outside.iterdir()), [])

    def test_rejects_destination_hardlinks(self):
        outside = self.root / "outside.js"
        outside.write_bytes(b"current build")
        os.link(outside, self.store / "index-abcdefgh.js")
        self.run_publish(success=False)

    def test_rejects_symlink_ancestors_and_dot_components(self):
        (self.root / "alias").symlink_to(self.root, target_is_directory=True)
        self.run_publish(success=False, store=self.root / "alias/retained")
        self.run_publish(success=False, source=self.root / "alias/packaged")
        self.run_publish(success=False, store=str(self.store) + "/../retained")
        self.run_publish(success=False, store=str(self.store) + "\n/unsafe")

    def test_rejects_overlapping_directories(self):
        self.run_publish(success=False, store=self.source / "retained")
        self.run_publish(success=False, store=self.root)

    def test_rejects_alternate_spellings_of_root(self):
        self.run_publish(success=False, store="////")
        self.run_publish(success=False, source="////")

    def test_rejects_group_or_world_writable_store(self):
        self.store.chmod(0o777)
        self.run_publish(success=False)

    def test_rejects_oversized_file_without_copying_it(self):
        oversized = self.asset("huge-12345678.js", b"")
        with oversized.open("wb") as handle:
            handle.truncate(64 * 1024 * 1024 + 1)
        result = self.run_publish(success=False)
        self.assertIn("64 MiB", result.stderr)
        self.assertFalse((self.store / "index-abcdefgh.js").exists())

    def test_rejects_oversized_build_without_copying_it(self):
        for i in range(5):
            with self.asset(f"large{i}-12345678.js", b"").open("wb") as handle:
                handle.truncate(64 * 1024 * 1024)
        result = self.run_publish(success=False)
        self.assertIn("256 MiB", result.stderr)
        self.assertFalse((self.store / "index-abcdefgh.js").exists())

    def test_directory_depth_is_bounded(self):
        self.asset("/".join(["nested"] * 9) + "/deep-12345678.js")
        result = self.run_publish(success=False)
        self.assertIn("nesting budget", result.stderr)

    def test_publish_waits_for_lock(self):
        with (self.store / ".publish.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            process = subprocess.Popen([str(PUBLISH), str(self.source), str(self.store)],
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                with self.assertRaises(subprocess.TimeoutExpired):
                    process.wait(timeout=0.2)
                self.assertFalse((self.store / "index-abcdefgh.js").exists())
                fcntl.flock(lock, fcntl.LOCK_UN)
                stdout, stderr = process.communicate(timeout=20)
                self.assertEqual(process.returncode, 0, stdout + stderr)
            finally:
                if process.poll() is None:
                    process.kill()
                process.communicate()

    def test_concurrent_publishers_are_idempotent(self):
        processes = [subprocess.Popen([str(PUBLISH), str(self.source), str(self.store)],
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                     for _ in range(4)]
        try:
            for process in processes:
                stdout, stderr = process.communicate(timeout=20)
                self.assertEqual(process.returncode, 0, stdout + stderr)
        finally:
            for process in processes:
                if process.poll() is None:
                    process.kill()
                process.communicate()
        self.assertEqual((self.store / "index-abcdefgh.js").read_bytes(), b"current build")
        self.assertEqual([p for p in self.store.glob(".publish.*") if p.name != ".publish.lock"], [])


class EntrypointTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="atlas-entrypoint-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "deploy").mkdir()
        (self.root / "bin").mkdir()
        shutil.copy2(ENTRYPOINT, self.root / "deploy/entrypoint")
        shutil.copy2(PUBLISH, self.root / "deploy/publish-assets")
        self.assets = self.root / "lib/atlas-0.1.0/priv/static/assets"
        self.assets.mkdir(parents=True)
        (self.assets / "index-abcdefgh.js").write_bytes(b"current build")
        (self.assets.parent / "index.html").write_bytes(b"image HTML")
        self.store = self.root / "retained"
        self.log = self.root / "calls"
        binary = self.root / "bin/atlas"
        binary.write_text("""#!/bin/sh
printf '%s\\n' "$*" >> "$ATLAS_TEST_LOG"
if [ "$1" = eval ]; then
  if [ "${ATLAS_TEST_EXPECT_ASSET:-false}" = true ]; then
    test -s "$FRONTEND_ASSET_DIR/index-abcdefgh.js" || exit 9
  fi
  exit "${ATLAS_TEST_SCHEMA_STATUS:-0}"
fi
printf '%s\\n' "$$" > "$ATLAS_TEST_PID"
""")
        binary.chmod(0o755)
        self.env = {"PATH": os.environ["PATH"], "ATLAS_TEST_LOG": str(self.log),
                    "ATLAS_TEST_PID": str(self.root / "pid")}

    def start(self, **env):
        return subprocess.run([str(self.root / "deploy/entrypoint")],
                              env=self.env | env, cwd="/", text=True,
                              capture_output=True, timeout=20)

    def calls(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def test_publishes_before_schema_then_starts_without_volume_html(self):
        process = subprocess.Popen([str(self.root / "deploy/entrypoint")],
                                   env=self.env | {"SERVE_FRONTEND": "true",
                                       "FRONTEND_ASSET_DIR": str(self.store),
                                       "ATLAS_TEST_EXPECT_ASSET": "true"},
                                   cwd="/", text=True, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE)
        stdout, stderr = process.communicate(timeout=20)
        self.assertEqual(process.returncode, 0, stdout + stderr)
        self.assertEqual(self.calls(), ["eval Atlas.Release.check_schema!()", "start"])
        self.assertEqual(int((self.root / "pid").read_text()), process.pid, "start must exec")
        self.assertFalse((self.store / "index.html").exists())
        self.assertEqual((self.assets.parent / "index.html").read_bytes(), b"image HTML")

    def test_schema_failure_never_starts(self):
        result = self.start(ATLAS_TEST_SCHEMA_STATUS="23")
        self.assertEqual(result.returncode, 23)
        self.assertEqual(self.calls(), ["eval Atlas.Release.check_schema!()"])

    def test_publication_failure_prevents_schema_and_start(self):
        (self.assets / "bad name.js").write_bytes(b"bad")
        result = self.start(SERVE_FRONTEND="true", FRONTEND_ASSET_DIR=str(self.store))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_missing_or_ambiguous_assets_prevent_start(self):
        shutil.rmtree(self.assets)
        result = self.start(SERVE_FRONTEND="true", FRONTEND_ASSET_DIR=str(self.store))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])
        self.assets.mkdir()
        (self.root / "lib/atlas-0.2.0/priv/static/assets").mkdir(parents=True)
        result = self.start(SERVE_FRONTEND="true", FRONTEND_ASSET_DIR=str(self.store))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_disabled_frontend_or_unset_store_skip_publication(self):
        for env in [{}, {"SERVE_FRONTEND": "true"},
                    {"SERVE_FRONTEND": "false", "FRONTEND_ASSET_DIR": str(self.store)}]:
            with self.subTest(env=env):
                result = self.start(**env)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(self.store.exists())
                self.assertEqual(self.calls()[-2:], ["eval Atlas.Release.check_schema!()", "start"])


class DockerContractTests(unittest.TestCase):
    def test_frontend_pin_and_nif_preseed_match_standalone_builds(self):
        docker = (ROOT / "Dockerfile").read_text()
        pin = json.loads((ROOT / "package.json").read_text())["packageManager"]
        self.assertIn("npm install --global " + pin, docker)
        self.assertIn("pnpm install --frozen-lockfile --filter @atlas/web...", docker)
        api = (ROOT / "apps/api/Dockerfile").read_text()
        for token in ["ARG BUILDER_IMAGE=", "ARG RUNTIME_IMAGE=", "RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH=",
                      "ELIXIR_MAKE_CACHE_DIR=", "file=libyex-", "file=vix-nif-",
                      '"https://github.com/satoren/y_ex/', '"https://github.com/akash-akya/vix/']:
            expected = next(line for line in api.splitlines() if token in line)
            self.assertIn(expected, docker)

    def test_release_contains_frontend_and_readable_runtime_config(self):
        docker = (ROOT / "Dockerfile").read_text()
        self.assertLess(docker.index("/app/apps/web/dist/client/ priv/static/"), docker.index("RUN mix release"))
        self.assertIn("COPY --chmod=0644 apps/api/config/runtime.exs config/", docker)
        self.assertIn("chmod -R a+rX,go-w", docker)
        self.assertIn("COPY --from=build --chown=0:0", docker)
        self.assertIn("--uid 1000", docker)
        self.assertIn("USER atlas", docker)
        self.assertIn("SERVE_FRONTEND=true PORT=4000", docker)
        self.assertIn("http://127.0.0.1:4000/health", docker)
        self.assertIn('ENTRYPOINT ["/app/deploy/entrypoint"]', docker)
        runtime = docker.split("FROM ${RUNTIME_IMAGE}", 1)[1]
        self.assertNotIn("nginx", runtime)
        self.assertNotIn("supervisor", runtime)
        self.assertNotIn("migrate()", docker)
        for binary in ["bash", "coreutils", "util-linux"]:
            self.assertIn(binary, runtime)
        for script in [ENTRYPOINT, PUBLISH]:
            self.assertTrue(os.access(script, os.X_OK), str(script))
            subprocess.run(["bash", "-n", str(script)], check=True)

    def test_specific_ignore_is_independent_of_standalone_web_context(self):
        patterns = [line for line in (ROOT / "Dockerfile.dockerignore").read_text().splitlines()
                    if line and not line.startswith("#")]
        self.assertEqual(patterns[0], "**")
        for included in ["apps/api/mix.exs", "apps/api/mix.lock", "apps/api/lib/**",
                         "apps/api/priv/**", "apps/api/config/runtime.exs", "apps/web/src/**",
                         "apps/web/public/**", "deploy/entrypoint", "deploy/publish-assets"]:
            self.assertIn("!" + included, patterns)
        for excluded in ["**/.env", "**/.env.*", "**/deps", "**/_build", "**/node_modules", "**/dist"]:
            self.assertIn(excluded, patterns)
        self.assertIn("apps/api", (ROOT / ".dockerignore").read_text().splitlines())


if __name__ == "__main__":
    unittest.main()
