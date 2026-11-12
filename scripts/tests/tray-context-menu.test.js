const { test } = require('node:test');
const assert = require('node:assert/strict');
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');

const exec = promisify(execFile);
const root = path.resolve(__dirname, '../..');

const trayInit = {
  legacy: 'this.electronTray.setToolTip(N.name),this.electronTray.on("right-click",()=>{var V;(V=this.electronTray)==null||V.popUpContextMenu(bZe())}),this.electronTray.on("click",()=>{})',
  optionalChaining: 'this.electronTray.setToolTip(N.name),this.electronTray.on("right-click",()=>{this.electronTray?.popUpContextMenu(bZe())}),this.electronTray.on("click",()=>{})',
};

async function patch(code) {
  const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'figma tray '));
  try {
    const mainJs = path.join(temp, 'main.js');
    await fs.writeFile(mainJs, code);
    const result = await exec('bash', ['-e', '-c', 'source "$1/build.sh"; patch_tray_context_menu "$2"', 'test', root, mainJs]);
    return { ...result, code: await fs.readFile(mainJs, 'utf8') };
  } finally {
    await fs.rm(temp, { recursive: true, force: true });
  }
}

for (const [form, code] of Object.entries(trayInit)) {
  test(`tray context menu is attached for ${form} right-click handler`, async () => {
    const patched = await patch(code);
    assert.equal(patched.code, code.replace(
      'this.electronTray.on("right-click"',
      'this.electronTray.setContextMenu(bZe()),this.electronTray.on("right-click"',
    ));
  });
}

test('tray context menu patch is idempotent', async () => {
  const once = await patch(trayInit.optionalChaining);
  const twice = await patch(once.code);
  assert.equal(twice.code, once.code);
});

test('tray context menu patch warns when Figma changes the tray init', async () => {
  const code = 'this.electronTray.on("middle-click",()=>{})';
  const patched = await patch(code);
  assert.equal(patched.code, code);
  assert.match(patched.stderr, /Tray context menu pattern not found/);
});
