const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync, spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '../..');
for (const format of ['deb', 'rpm']) {
  const commands = format === 'deb' ? ['dpkg-deb', 'tar', 'convert'] : ['rpmbuild', 'rpm', 'convert'];
  const available = commands.every(command => spawnSync('which', [command]).status === 0);
  test(`${format} packages normalize ownership and permissive builder modes`, { skip: !available, timeout: 120000 }, () => {
    const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'figma-package-metadata-'));
    try {
      const staging = path.join(temp, 'app');
      const electron = path.join(staging, 'node_modules/electron/dist');
      fs.mkdirSync(path.join(electron, 'resources'), { recursive: true });
      fs.mkdirSync(path.join(temp, 'work'));
      execFileSync('convert', ['-size', '16x16', 'xc:blue', path.join(temp, 'work/figma_fixture.png')]);
      fs.writeFileSync(path.join(electron, 'electron'), '#!/bin/sh\nexit 0\n', { mode: 0o777 });
      fs.chmodSync(path.join(electron, 'electron'), 0o777);
      fs.writeFileSync(path.join(staging, 'app.asar'), 'fixture');
      fs.chmodSync(path.join(staging, 'app.asar'), 0o666);
      for (const dir of ['app', 'app/node_modules', 'app/node_modules/electron', 'app/node_modules/electron/dist']) {
        fs.chmodSync(path.join(temp, dir), 0o777);
      }
      execFileSync('bash', ['-c', 'umask 0002; exec "$@"', '--', 'bash',
        path.join(root, `scripts/build-${format}-package.sh`), '126.0.0', 'amd64',
        path.join(temp, 'work'), staging, 'figma-desktop', 'Test Maintainer', 'Test package'],
        { cwd: temp, stdio: 'pipe', timeout: 110000 });
      if (format === 'deb') {
        const archive = execFileSync('dpkg-deb', ['--fsys-tarfile', path.join(temp, 'work/figma-desktop_126.0.0_amd64.deb')]);
        const listing = execFileSync('tar', ['--numeric-owner', '-tvf', '-'], { input: archive, encoding: 'utf8' });
        const entries = listing.trim().split('\n');
        assert.ok(entries.length > 10);
        for (const entry of entries) {
          const [mode, owner] = entry.trim().split(/\s+/);
          assert.equal(owner, '0/0', entry);
          if (mode.startsWith('d')) assert.equal(mode, 'drwxr-xr-x', entry);
          if (mode.startsWith('-')) assert.ok(['-rw-r--r--', '-rwxr-xr-x'].includes(mode), entry);
        }
        assert.match(listing, /-rwxr-xr-x.*\/electron\n/);
        assert.match(listing, /-rw-r--r--.*\/app\.asar\n/);
      } else {
        const listing = execFileSync('rpm', ['-qp', '--qf', '[%{FILENAMES}\t%{FILEUSERNAME}\t%{FILEGROUPNAME}\t%{FILEMODES:octal}\n]',
          path.join(temp, 'work/figma-desktop-126.0.0-1.x86_64.rpm')], { encoding: 'utf8' });
        const entries = listing.trim().split('\n');
        assert.ok(entries.length > 5);
        for (const entry of entries) {
          const [name, user, group, mode] = entry.split('\t');
          assert.equal(user, 'root', name);
          assert.equal(group, 'root', name);
          const bits = parseInt(mode, 8);
          if ((bits & 0o170000) === 0o040000) assert.equal(bits & 0o7777, 0o755, name);
          if ((bits & 0o170000) === 0o100000) assert.ok([0o644, 0o755].includes(bits & 0o7777), name);
          if (name.endsWith('/electron')) assert.equal(bits & 0o7777, 0o755);
          if (name.endsWith('/app.asar')) assert.equal(bits & 0o7777, 0o644);
        }
      }
    } finally {
      fs.rmSync(temp, { recursive: true, force: true });
    }
  });
}
