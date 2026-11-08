const { test } = require('node:test');
const assert = require('node:assert/strict');
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');

const exec = promisify(execFile);
const root = path.resolve(__dirname, '../..');

const trayCode = [
  'function Fz(){return process.platform!=="win32"?!1:Pe.isSystemDarkMode()}',
  'show(){this.electronTray.on("click",()=>{}),ot&&this.themeCallback&&js.nativeTheme.addListener("updated",this.themeCallback)}',
  'hide(){this.electronTray?.destroy(),this.electronTray=void 0,ot&&this.themeCallback&&js.nativeTheme.removeListener("updated",this.themeCallback)}',
].join('');

async function patch(code) {
  const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'figma tray icon '));
  try {
    const mainJs = path.join(temp, 'main.js');
    await fs.writeFile(mainJs, code);
    const result = await exec('bash', ['-e', '-c', 'source "$1/build.sh"; patch_tray_icon_theme "$2"', 'test', root, mainJs]);
    return { ...result, code: await fs.readFile(mainJs, 'utf8') };
  } finally {
    await fs.rm(temp, { recursive: true, force: true });
  }
}

test('tray icon follows dark mode on Linux', async () => {
  const { code } = await patch(trayCode);
  assert.match(code, /function Fz\(\)\{return process\.platform!=="win32"&&process\.platform!=="linux"\?!1:Pe\.isSystemDarkMode\(\)\}/);
});

test('tray icon updates on theme change on Linux', async () => {
  const { code } = await patch(trayCode);
  for (const method of ['addListener', 'removeListener']) {
    assert.ok(code.includes(`(ot||process.platform==="linux")&&this.themeCallback&&js.nativeTheme.${method}("updated",this.themeCallback)`), method);
  }
});

test('tray icon theme patch is idempotent', async () => {
  const once = await patch(trayCode);
  const twice = await patch(once.code);
  assert.equal(twice.code, once.code);
});

test('tray icon theme patch warns when Figma changes the tray code', async () => {
  const code = 'function Fz(){return!1}';
  const patched = await patch(code);
  assert.equal(patched.code, code);
  assert.match(patched.stderr, /Tray icon dark mode pattern not found/);
  assert.match(patched.stderr, /Tray icon theme listener pattern not found/);
});
