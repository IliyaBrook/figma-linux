const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const { createHash } = require('node:crypto');
const exec = promisify(execFile);
const root = path.resolve(__dirname, '../..');
const payload = Buffer.from('verified fixture');
const digest = createHash('sha256').update(payload).digest('hex');
let temp, server, base;
const shell = (code, args = []) => exec('bash', ['-e', '-c', code, 'test', root, ...args]);
const download = (url, output) => shell('source "$1/scripts/appimage-toolchain.sh"; download_verified "$2" "$3" "$4"', [url, output, digest]);
before(async () => {
  temp = await fs.mkdtemp(path.join(os.tmpdir(), 'figma runtime '));
  server = http.createServer((req, res) => {
    if (req.url === '/missing') { res.writeHead(404); return res.end('missing'); }
    if (req.url === '/corrupt') return res.end('corrupt download');
    if (req.url === '/partial') {
      res.writeHead(200, { 'Content-Length': payload.length, Connection: 'close' });
      return res.end(payload.subarray(0, 4));
    }
    res.end(payload);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(async () => {
  if (server) await new Promise(resolve => server.close(resolve));
  if (temp) await fs.rm(temp, { recursive: true, force: true });
});
test('verified download accepts correct bytes and recovers corrupt cache', async () => {
  const output = path.join(temp, 'artifact');
  await fs.writeFile(output, 'bad cache');
  await download(base + '/ok', output);
  assert.deepEqual(await fs.readFile(output), payload);
});
test('verified cache works offline without invoking downloader', async () => {
  const output = path.join(temp, 'cached');
  await fs.writeFile(output, payload);
  await shell('source "$1/scripts/appimage-toolchain.sh"; wget() { return 99; }; download_verified invalid "$2" "$3"', [output, digest]);
});
test('HTTP, truncated and wrong-digest downloads stop before packaging and remove bad artifact', async () => {
  for (const route of ['/missing', '/partial', '/corrupt']) {
    const output = path.join(temp, route.slice(1));
    const marker = output + '.packaged';
    await assert.rejects(shell('source "$1/scripts/appimage-toolchain.sh"; download_verified "$2" "$3" "$4"; touch "$5"', [base + route, output, digest, marker]));
    await assert.rejects(fs.access(output));
    await assert.rejects(fs.access(marker));
  }
});
test('architecture mapping rejects unsupported machines before any download', async () => {
  for (const [arch, expected] of [['amd64', 'x86_64'], ['arm64', 'aarch64']]) {
    const { stdout } = await shell('source "$1/scripts/appimage-toolchain.sh"; select_appimage_architecture "$2"; echo "$tool_arch"', [arch]);
    assert.equal(stdout.trim(), expected);
  }
  await assert.rejects(shell('source "$1/scripts/appimage-toolchain.sh"; prepare_appimage_tools riscv64 "$2"', [temp]));
});
test('Node minimum accepts 22.12 and newer, bootstraps older versions', async () => {
  for (const [version, accepted] of [['20.19.0', false], ['22.11.0', false], ['22.12.0', true], ['24.14.0', true]]) {
    const code = 'source "$1/build.sh"; node_version_fixture=$2; node() { echo "v$node_version_fixture"; }; work_dir=$3; project_root=$3; wget() { return 99; }; setup_nodejs';
    if (accepted) {
      const { stdout } = await shell(code, [version, temp]);
      assert.match(stdout, /version is adequate/);
    } else {
      await assert.rejects(shell(code, [version, temp]), error => {
        assert.match(error.stdout, /Installing Node.js v22/);
        return true;
      });
    }
  }
});
