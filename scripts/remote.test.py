#!/usr/bin/env python3
"""Offline fixtures: never connects to a machine, installs Nix or starts a service."""
import importlib.machinery
import importlib.util
import io
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parent.parent
loader = importlib.machinery.SourceFileLoader("remote_cli", str(ROOT / "bin/remote"))
spec = importlib.util.spec_from_loader(loader.name, loader)
cli = importlib.util.module_from_spec(spec)
loader.exec_module(cli)


class CommandTests(unittest.TestCase):
    def setUp(self):
        # Command-dispatch tests may never start real SSH/browser processes.
        guard = patch.object(cli.subprocess, "Popen", side_effect=AssertionError("No network allowed"))
        guard.start()
        self.addCleanup(guard.stop)

    def test_oauth_callback_forwarding_is_scoped_and_cleaned_up(self):
        url = "https://oauth.example.invalid/authorize?redirect_uri=http%3A%2F%2F127.0.0.1%3A54321%2Fcallback"
        proc = Mock(stdout=io.BytesIO((url + "\n").encode()))
        proc.wait.return_value = 0
        proc.poll.return_value = 0
        with patch.object(cli.subprocess, "Popen", return_value=proc) as spawn, \
             patch.object(cli.subprocess, "run", return_value=Mock(returncode=0)) as run, \
             patch.object(cli.webbrowser, "open") as browser, patch("sys.stdout"):
            cli.login("fixture-never-connect", "codex", "executor")
        browser.assert_called_once_with(url)
        self.assertIn("--no-browser", spawn.call_args[0][0][-1])
        self.assertIn("127.0.0.1:54321:127.0.0.1:54321", run.call_args_list[0][0][0])
        self.assertIn("exit", run.call_args_list[-1][0][0])
        self.assertTrue(proc.stdout.closed)

    def test_requires_explicit_host(self):
        with self.assertRaises(SystemExit), patch("sys.stderr", io.StringIO()):
            cli.main(["deploy"])

    def test_rejects_ssh_option_or_shell_injection(self):
        for host in ("-oProxyCommand=bad", "host;bad", "user@host bad"):
            with self.assertRaises(SystemExit), patch("sys.stderr", io.StringIO()):
                cli.main(["status", host])

    def test_transports_script_and_quotes_ref(self):
        with patch.object(cli, "ssh") as ssh:
            cli.main(["deploy", "user@box", "--ref", "feature/t3", "--force"])
        args, kwargs = ssh.call_args
        self.assertEqual(args[0], "user@box")
        self.assertIn("deploy feature/t3 1 0", args[1])
        self.assertEqual(kwargs["input"], (ROOT / "scripts/remote.sh").read_bytes())

    def test_mcp_auth_uses_independent_login(self):
        with patch.object(cli, "login") as login:
            cli.main(["auth", "devbox", "mcp", "executor", "--client", "codex"])
        login.assert_called_once_with("devbox", "codex", "executor")

    def test_mcp_server_rejects_option_injection(self):
        with self.assertRaises(ValueError), patch.object(cli.subprocess, "Popen", side_effect=AssertionError("No network allowed")):
            cli.login("fixture-never-connect", "pi", "--bad")

    def test_github_auth_is_not_a_credential_copy(self):
        with patch.object(cli, "login") as login:
            cli.main(["auth", "devbox", "gh"])
        login.assert_called_once_with("devbox", "gh", None)


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="remote-fixture-")
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.checkout = self.home / "Developer/dotfiles"
        self.upstream = self.root / "upstream"
        self.bin = self.home / ".local/bin"
        self.bin.mkdir(parents=True)
        self.git = shutil.which("git")
        self.log = self.root / "commands"
        self.log.touch()
        self.env = dict(os.environ, HOME=str(self.home), TEST_GIT=self.git,
                        TEST_UPSTREAM=str(self.upstream), TEST_LOG=str(self.log))
        self.run_git("init", "-b", "main", str(self.upstream))
        self.run_git("-C", str(self.upstream), "config", "user.name", "Fixture")
        self.run_git("-C", str(self.upstream), "config", "user.email", "fixture@example.invalid")
        (self.upstream / "settings.json").write_text("original\n")
        self.run_git("-C", str(self.upstream), "add", ".")
        self.run_git("-C", str(self.upstream), "commit", "-m", "initial")
        self.run_git("clone", str(self.upstream), str(self.checkout))
        self.state = self.home / ".config/dotfiles"
        self.state.mkdir(parents=True)
        (self.state / "remote.env").write_text(
            f"mode=home-manager\ntarget={self.state}/flake#remote\nREMOTE_REF=main\nDEPLOYED_T3_VERSION=0.1.0\n")
        self.mock("uname", 'if [[ ${1:-} == -m ]]; then echo x86_64; else echo Linux; fi\n')
        self.mock("id", 'if [[ $1 == -u ]]; then echo 1000; else echo fixture; fi\n')
        self.mock("git", '''if [[ $* == *"remote get-url origin"* ]]; then
  echo https://github.com/psteinroe/dotfiles.git
elif [[ $* == *"fetch origin"* ]]; then
  printf 'fetch\\n' >>"$TEST_LOG"
  exec "$TEST_GIT" -C "$2" fetch "$TEST_UPSTREAM" "${@: -1}"
else exec "$TEST_GIT" "$@"; fi
''')
        self.mock("nix", '''printf 'nix %s\\n' "$*" >>"$TEST_LOG"
if [[ $1 == eval ]]; then printf '0.1.0'; fi
''')
        self.mock("tailscale", 'printf \'%s\\n\' \'{"BackendState":"Running"}\'\n')
        for command in ("systemctl", "sudo"):
            self.mock(command, f'printf "{command} %s\\n" "$*" >>"$TEST_LOG"\n')

    def tearDown(self):
        self.temp.cleanup()

    def mock(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\nset -eu\n" + body)
        path.chmod(0o755)

    def run_git(self, *args):
        return subprocess.run([self.git, *args], check=True, env=self.env,
                              capture_output=True, text=True).stdout.strip()

    def deploy(self, force=False, allow_update=False):
        return subprocess.run(["bash", str(ROOT / "scripts/remote.sh"), "deploy", "", str(int(force)), "0", "", str(int(allow_update))],
                              env=self.env, capture_output=True, text=True)

    def advance_upstream(self):
        (self.upstream / "new-file").write_text("new\n")
        self.run_git("-C", str(self.upstream), "add", ".")
        self.run_git("-C", str(self.upstream), "commit", "-m", "advance")

    def test_dirty_settings_stop_before_fetch_or_switch(self):
        (self.checkout / "settings.json").write_text("UI settings\n")
        result = self.deploy()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Dirty dotfiles checkout", result.stderr)
        self.assertEqual(self.log.read_text(), "")
        self.assertEqual((self.checkout / "settings.json").read_text(), "UI settings\n")

    def test_untracked_file_stops_without_force(self):
        (self.checkout / "notes").write_text("keep\n")
        self.assertNotEqual(self.deploy().returncode, 0)
        self.assertTrue((self.checkout / "notes").exists())
        self.assertEqual(self.log.read_text(), "")

    def test_clean_checkout_fast_forwards_and_applies_home_manager(self):
        self.advance_upstream()
        result = self.deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.checkout / "new-file").exists())
        commands = self.log.read_text()
        self.assertIn("home-manager -- switch", commands)
        self.assertIn("sudo -n loginctl enable-linger fixture", commands)
        self.assertNotIn("nixos-rebuild", commands)

    def test_prepared_home_manager_target_needs_no_sudo(self):
        self.mock("loginctl", 'echo yes\n')
        self.mock("sudo", 'echo "Unexpected sudo" >&2; exit 99\n')
        result = self.deploy()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_nixos_target_uses_system_switch_not_home_manager(self):
        path = self.state / "remote.env"
        path.write_text(path.read_text().replace("mode=home-manager", "mode=nixos"))
        self.mock("nix", '''printf 'nix %s\\n' "$*" >>"$TEST_LOG"
if [[ $1 == eval ]]; then
  if [[ $* == *config.dotfiles.remote.user* ]]; then printf fixture; else printf 0.1.0; fi
fi
''')
        result = self.deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("sudo -n nixos-rebuild switch --impure --flake", self.log.read_text())
        self.assertNotIn("home-manager -- switch", self.log.read_text())

    def test_unenrolled_tailscale_reports_setup_without_starting_t3(self):
        self.mock("tailscale", 'echo \'{"BackendState":"NeedsLogin"}\'\n')
        result = self.deploy()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("sudo tailscale up", result.stderr)
        self.assertNotIn("restart t3code", self.log.read_text())

    def test_force_is_the_only_destructive_path(self):
        (self.checkout / "settings.json").write_text("discard\n")
        (self.checkout / "notes").write_text("discard\n")
        self.advance_upstream()
        result = self.deploy(force=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.checkout / "settings.json").read_text(), "original\n")
        self.assertFalse((self.checkout / "notes").exists())

    def test_divergence_stops_before_switch(self):
        self.run_git("-C", str(self.checkout), "config", "user.name", "Fixture")
        self.run_git("-C", str(self.checkout), "config", "user.email", "fixture@example.invalid")
        (self.checkout / "local").write_text("keep\n")
        self.run_git("-C", str(self.checkout), "add", ".")
        self.run_git("-C", str(self.checkout), "commit", "-m", "local")
        self.advance_upstream()
        self.assertNotEqual(self.deploy().returncode, 0)
        self.assertNotIn("nix run", self.log.read_text())
        self.assertTrue((self.checkout / "local").exists())

    def test_t3_version_change_requires_explicit_permission(self):
        path = self.state / "remote.env"
        path.write_text(path.read_text().replace("DEPLOYED_T3_VERSION=0.1.0", "DEPLOYED_T3_VERSION=0.0.9"))
        result = self.deploy()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--allow-t3-update", result.stderr)
        self.assertNotIn("nix run", self.log.read_text())

    def test_t3_version_change_backs_up_state_before_switch(self):
        path = self.state / "remote.env"
        path.write_text(path.read_text().replace("DEPLOYED_T3_VERSION=0.1.0", "DEPLOYED_T3_VERSION=0.0.9"))
        (self.home / ".t3").mkdir()
        (self.home / ".t3/state").write_text("preserve\n")
        result = self.deploy(allow_update=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        backups = list((self.home / ".local/state/dotfiles/backups").glob("t3-0.0.9-*/state"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), "preserve\n")
        commands = self.log.read_text()
        self.assertLess(commands.index("stop t3code"), commands.index("nix run"))


if __name__ == "__main__":
    unittest.main()
