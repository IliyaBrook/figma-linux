const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');

const exec = promisify(execFile);
const root = path.resolve(__dirname, '../..');
let temp, server, base, installer;
const shell = (code, args = []) => exec('bash', ['-e', '-c', code, 'test', root, ...args]);

before(async () => {
  temp = await fs.mkdtemp(path.join(os.tmpdir(), 'figma update '));
  await fs.writeFile(path.join(temp, 'payload.txt'), 'fixture');
  await exec('7z', ['a', '-tzip', 'Figma-126.10.10-full.nupkg', 'payload.txt'], { cwd: temp });
  installer = path.join(temp, 'setup.exe');
  await exec('7z', ['a', '-tzip', installer, 'Figma-126.10.10-full.nupkg'], { cwd: temp });
  const payload = await fs.readFile(installer);
  server = http.createServer((req, res) => {
    if (req.url === '/installer') return res.end(payload);
    if (req.url === '/missing') { res.writeHead(404); return res.end('not found'); }
    if (req.url === '/partial') {
      res.writeHead(200, { 'Content-Length': payload.length, Connection: 'close' });
      return res.end(payload.subarray(0, 10));
    }
    if (req.url === '/invalid') return res.end('<html>service unavailable</html>');
    if (req.url === '/ambiguous') return res.end('abc Figma-126.1.0-full.nupkg 5\nabc Figma-126.2.0-full.nupkg 5\n');
    res.end('abc Figma-126.9.13-delta.nupkg 5\r\nabc Figma-126.9.13-full.nupkg 5\r\n');
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(async () => {
  if (server) await new Promise(resolve => server.close(resolve));
  if (temp) await fs.rm(temp, { recursive: true, force: true });
});

test('manifest accepts full package with CRLF and ignores delta packages', async () => {
  const { stdout } = await shell('source "$1/scripts/figma-version-common.sh"; figma_fetch_manifest_version "$2"', [base]);
  assert.equal(stdout.trim(), '126.9.13');
});

test('manifest rejects HTTP errors, HTML, and ambiguous full versions', async () => {
  for (const route of ['/missing', '/invalid', '/ambiguous']) {
    await assert.rejects(shell('source "$1/scripts/figma-version-common.sh"; figma_fetch_manifest_version "$2"', [base + route]));
  }
});

test('download inspects actual installer rather than lagging manifest', async () => {
  const destination = path.join(temp, 'downloaded.exe');
  const { stdout } = await shell(`source "$1/scripts/figma-version-common.sh"
    figma_download_installer "$2/installer" "$3"
    figma_version_from_nupkg "$(figma_installer_nupkg "$3")"`, [base, destination]);
  assert.equal(stdout.trim(), '126.10.10');
  assert.deepEqual(await fs.readFile(destination), await fs.readFile(installer));
  await assert.rejects(fs.access(destination + '.part'));
});

test('failed download preserves existing installer and removes partial file', async () => {
  const destination = path.join(temp, 'preserved.exe');
  await fs.writeFile(destination, 'previous installer');
  for (const route of ['/missing', '/partial']) {
    await assert.rejects(shell('source "$1/scripts/figma-version-common.sh"; figma_download_installer "$2" "$3"', [base + route, destination]));
    assert.equal(await fs.readFile(destination, 'utf8'), 'previous installer');
    await assert.rejects(fs.access(destination + '.part'));
  }
});

test('version tool inspects local installer offline and emits valid JSON', async () => {
  const { stdout } = await exec(path.join(root, 'figma-version-tool.sh'), ['--json', '--exe', installer]);
  assert.deepEqual(JSON.parse(stdout), {
    manifest_version: '', installer_version: '126.10.10', selected_version: '126.10.10',
  });
});

test('version tool fails on missing, corrupt, or ambiguous installer', async () => {
  const corrupt = path.join(temp, 'corrupt.exe');
  await fs.writeFile(corrupt, 'not an archive');
  const ambiguous = path.join(temp, 'ambiguous.exe');
  await fs.writeFile(path.join(temp, 'Figma-126.9.13-full.nupkg'), 'another fixture');
  await exec('7z', ['a', '-tzip', ambiguous, 'Figma-126.10.10-full.nupkg', 'Figma-126.9.13-full.nupkg'], { cwd: temp });
  for (const filename of [path.join(temp, 'missing.exe'), corrupt, ambiguous]) {
    await assert.rejects(exec(path.join(root, 'figma-version-tool.sh'), ['--json', '--exe', filename]));
  }
});

test('builder preserves relative --exe inside build before cleaning, without network access', async () => {
  const project = path.join(temp, 'local project');
  await fs.mkdir(path.join(project, 'build'), { recursive: true });
  await fs.copyFile(installer, path.join(project, 'build/local setup.exe'));
  await fs.writeFile(path.join(project, 'build/stale-marker'), 'old build');
  const { stdout } = await shell(`source "$1/build.sh"
    cd "$2"
    project_root=$PWD
    work_dir="$PWD/build"
    app_staging_dir="$work_dir/electron-app"
    local_exe_path='build/local setup.exe'
    curl() { echo 'Unexpected network request' >&2; return 99; }
    setup_work_directory
    resolve_figma_version
    download_figma_installer
    [[ $version == '126.10.10' ]]
    [[ -f $app_staging_dir/../FigmaSetup.exe ]]`, [project]);
  assert.match(stdout, /selected_version: 126\.10\.10/);
  assert.deepEqual(await fs.readFile(path.join(project, 'build/FigmaSetup.exe')), await fs.readFile(installer));
  await assert.rejects(fs.access(path.join(project, 'build/stale-marker')));
  assert.equal((await fs.readdir(project)).filter(name => name.startsWith('.figma-installer.')).length, 0);
});

test('missing local installer is rejected before previous build is removed', async () => {
  const project = path.join(temp, 'missing project');
  await fs.mkdir(path.join(project, 'build'), { recursive: true });
  const marker = path.join(project, 'build/keep');
  await fs.writeFile(marker, 'keep');
  await assert.rejects(shell(`source "$1/build.sh"
    project_root=$2
    work_dir="$2/build"
    app_staging_dir="$work_dir/electron-app"
    local_exe_path="$2/missing.exe"
    setup_work_directory`, [project]));
  assert.equal(await fs.readFile(marker, 'utf8'), 'keep');
});

test('builder continues with a valid installer when manifest lookup fails', async () => {
  const project = path.join(temp, 'manifest unavailable project');
  await fs.mkdir(project);
  const { stdout, stderr } = await shell(`source "$1/build.sh"
    project_root=$2
    work_dir="$2/build"
    app_staging_dir="$work_dir/electron-app"
    fixture_installer=$3
    figma_fetch_manifest_version() { return 1; }
    figma_download_installer() { cp -- "$fixture_installer" "$2"; }
    setup_work_directory
    resolve_figma_version
    download_figma_installer
    [[ $version == '126.10.10' ]]`, [project, installer]);
  assert.match(stdout, /selected_version: 126\.10\.10/);
  assert.match(stderr, /Warning: RELEASES unavailable or invalid/);
});
