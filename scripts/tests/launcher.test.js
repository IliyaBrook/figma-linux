const { test } = require('node:test');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const path = require('node:path');
const launcher = path.resolve(__dirname, '../launcher-common.sh');

function launchArgs(options = {}) {
  const probe = options.probe ?? 'printf "number of extensions: 1\\n    GLX (opcode: 150)\\n"';
  return execFileSync('bash', ['-c', `source "$1"
    log_message() { :; }
    xdpyinfo() { ${probe}; }
    timeout() { shift; "$@"; }
    ${options.missingTools ? 'unset -f xdpyinfo timeout; PATH=/nonexistent' : ''}
    detect_display_backend
    build_electron_args "\${PACKAGE_TYPE:-appimage}" || exit 1
    printf '%s\\n' "\${electron_args[@]}"`, 'test', launcher], {
    encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, DISPLAY: ':test', WAYLAND_DISPLAY: '', FIGMA_USE_X11: '',
      FIGMA_USE_WAYLAND: '', FIGMA_RENDERER: '', ...options.env },
  }).trim().split('\n');
}

test('X11 with GLX retains Electron graphics defaults', () => {
  const args = launchArgs();
  assert.ok(args.includes('--no-sandbox'));
  assert.ok(!args.some(arg => arg.startsWith('--use-angle')));
  assert.ok(!args.some(arg => arg.startsWith('--ozone-platform')));
});

test('X11 without GLX selects SwiftShader and keeps WebGL enabled for every package', () => {
  for (const type of ['appimage', 'deb', 'rpm']) {
    const args = launchArgs({ probe: 'printf "number of extensions: 1\\n    RENDER\\n"', env: { PACKAGE_TYPE: type } });
    assert.ok(args.includes('--use-angle=swiftshader'));
    assert.ok(args.includes('--use-gl=angle'));
    assert.ok(!args.includes('--disable-gpu'));
  }
});

test('XWayland retains X11 compatibility backend and probes that display', () => {
  const args = launchArgs({ probe: 'printf "number of extensions: 0\\n"', env: { WAYLAND_DISPLAY: 'wayland-0' } });
  assert.ok(args.includes('--ozone-platform=x11'));
  assert.ok(args.includes('--use-angle=swiftshader'));
});

test('native Wayland opt-in bypasses X11 probe', () => {
  const args = launchArgs({ probe: 'echo "unexpected probe" >&2; exit 99', env: { WAYLAND_DISPLAY: 'wayland-0', FIGMA_USE_WAYLAND: '1' } });
  assert.ok(args.includes('--ozone-platform=wayland'));
  assert.ok(!args.includes('--use-angle=swiftshader'));
});

test('Wayland session without DISPLAY uses native Wayland automatically', () => {
  const args = launchArgs({ env: { DISPLAY: '', WAYLAND_DISPLAY: 'wayland-0' } });
  assert.ok(args.includes('--ozone-platform=wayland'));
});

test('explicit X11 preference takes precedence over native Wayland opt-in', () => {
  const args = launchArgs({ env: { WAYLAND_DISPLAY: 'wayland-0', FIGMA_USE_WAYLAND: '1', FIGMA_USE_X11: '1' } });
  assert.ok(args.includes('--ozone-platform=x11'));
});

test('failed, malformed, or unavailable X11 probe preserves graphics defaults', () => {
  for (const options of [{ probe: 'return 1' }, { probe: 'echo incomplete' }, { missingTools: true }]) {
    assert.ok(!launchArgs(options).includes('--use-angle=swiftshader'));
  }
});

test('hardware override bypasses automatic software selection', () => {
  const args = launchArgs({ probe: 'echo "unexpected probe" >&2; exit 99', env: { FIGMA_RENDERER: 'hardware' } });
  assert.ok(!args.includes('--use-angle=swiftshader'));
});

test('software override works without probe tools, including native Wayland', () => {
  const args = launchArgs({ missingTools: true, env: { FIGMA_RENDERER: 'software', WAYLAND_DISPLAY: 'wayland-0', FIGMA_USE_WAYLAND: '1' } });
  assert.ok(args.includes('--ozone-platform=wayland'));
  assert.ok(args.includes('--use-angle=swiftshader'));
});

test('invalid renderer is rejected instead of silently changing rendering', () => {
  assert.throws(() => launchArgs({ env: { FIGMA_RENDERER: 'typo' } }), /Invalid FIGMA_RENDERER/);
});
