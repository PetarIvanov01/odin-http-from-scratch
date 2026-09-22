'use strict';

// Run with: node benchmark.js
// Optional environment variables: REQUESTS, CONNECTIONS, RUNS,
// BOMBARDIER_EXE, GO_EXE, ODIN_EXE, BUN_EXE, CARGO_EXE.

const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');

const root = __dirname;
const bin = path.join(root, 'comparisons', 'empty-ok-all', 'bin');
const port = 8080;
const url = `http://127.0.0.1:${port}/pong`;
const requests = Number(process.env.REQUESTS || 10_000);
const connections = Number(process.env.CONNECTIONS || 200);
const runs = Number(process.env.RUNS || 1);

const isWindows = process.platform === 'win32';
const exe = (name) => (isWindows ? `${name}.exe` : name);

function configuredCommand(variable, fallback, candidates = []) {
  if (process.env[variable]) return process.env[variable];
  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) return candidate;
  }
  return fallback;
}

const commands = {
  bombardier: configuredCommand(
    'BOMBARDIER_EXE',
    'bombardier',
    [path.join(process.env.USERPROFILE || '', 'go', 'bin', exe('bombardier'))],
  ),
  go: configuredCommand('GO_EXE', 'go', [
    'C:\\Program Files\\Go\\bin\\go.exe',
  ]),
  odin: configuredCommand('ODIN_EXE', 'odin'),
  bun: configuredCommand('BUN_EXE', 'bun'),
  cargo: configuredCommand('CARGO_EXE', 'cargo'),
};

const artifacts = {
  odin: path.join(bin, exe('odin-server')),
  go: path.join(bin, exe('go-server')),
  rust: path.join(bin, exe('empty-ok-rust')),
  bun: path.join(bin, 'bun-server.js'),
};

const servers = [
  {
    name: 'Odin',
    build: [commands.odin, [
      'build', '.', `-out:${artifacts.odin}`,
      '-o:speed', '-disable-assert', '-no-bounds-check',
      '-define:BENCHMARK=true',
    ], root],
    start: [artifacts.odin, [], root],
    cleanupImage: path.basename(artifacts.odin),
  },
  {
    name: 'Go',
    build: [commands.go, [
      'build', '-trimpath', '-ldflags=-s -w',
      '-o', artifacts.go, 'main.go',
    ], path.join(root, 'comparisons', 'empty-ok-all', 'go')],
    start: [artifacts.go, [], root],
  },
  {
    name: 'Rust/Actix',
    build: [commands.cargo, [
      'build', '--release', '--manifest-path',
      path.join(root, 'comparisons', 'empty-ok-all', 'rust', 'Cargo.toml'),
    ], root],
    start: [artifacts.rust, [], root],
    afterBuild() {
      const cargoBinary = path.join(
        root, 'comparisons', 'empty-ok-all', 'rust', 'target',
        'release', exe('empty-ok-rust'),
      );
      fs.copyFileSync(cargoBinary, artifacts.rust);
    },
  },
  {
    name: 'Bun',
    build: [commands.bun, [
      'build', path.join(root, 'comparisons', 'empty-ok-all', 'bun', 'index.ts'),
      '--target=bun', '--outfile', artifacts.bun,
    ], root],
    start: [commands.bun, ['run', artifacts.bun], root],
  },
];

function runChecked(command, args, cwd) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
  });

  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error([
      `${command} ${args.join(' ')} failed with exit code ${result.status}`,
      result.stdout,
      result.stderr,
    ].filter(Boolean).join('\n'));
  }
}

function waitForPong(child, timeoutMs = 10_000) {
  return new Promise((resolve, reject) => {
    const deadline = Date.now() + timeoutMs;
    let settled = false;

    const finish = (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      clearInterval(poll);
      error ? reject(error) : resolve();
    };

    const probe = () => {
      const request = http.get(url, { headers: { Connection: 'close' } }, (response) => {
        let body = '';
        response.setEncoding('utf8');
        response.on('data', (chunk) => { body += chunk; });
        response.on('end', () => {
          if (response.statusCode === 200 && body === 'Pong') finish();
          else finish(new Error(`Smoke test returned ${response.statusCode}: ${body}`));
        });
      });
      request.on('error', () => {});
      request.setTimeout(500, () => request.destroy());
    };

    const poll = setInterval(() => {
      if (child.exitCode !== null) {
        finish(new Error('Server exited before becoming ready.'));
      } else if (Date.now() < deadline) {
        probe();
      }
    }, 100);
    const timer = setTimeout(() => finish(new Error('Timed out waiting for /pong.')), timeoutMs);
    probe();
  });
}

function stop(child, cleanupImage) {
  if (isWindows) {
    spawnSync('taskkill', ['/PID', String(child.pid), '/T', '/F'], {
      stdio: 'ignore',
      windowsHide: true,
    });
    // Odin can leave worker-created processes behind on Windows. The image
    // name is unique to this benchmark binary, so clean up any leftovers.
    if (cleanupImage) {
      spawnSync('taskkill', ['/IM', cleanupImage, '/T', '/F'], {
        stdio: 'ignore',
        windowsHide: true,
      });
    }
  } else {
    if (child.exitCode === null) child.kill('SIGTERM');
  }
}

function benchmark(child) {
  const result = spawnSync(commands.bombardier, [
    '-c', String(connections),
    '-n', String(requests),
    '-H', 'Connection: close',
    url,
  ], {
    cwd: root,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
  });

  const output = `${result.stdout}\n${result.stderr}`;
  const successful = output.match(/2xx\s+-\s+(\d+)/)?.[1];
  const failed = output.match(/others\s+-\s+(\d+)/)?.[1];
  const rate = output.match(/Reqs\/sec\s+([\d.]+)/)?.[1];

  if (result.error) throw result.error;
  if (result.status !== 0 || successful !== String(requests) || failed !== '0') {
    throw new Error(`Incomplete Bombardier run:\n${output}`);
  }

  return { requestsPerSecond: Number(rate), output };
}

async function main() {
  if (!Number.isInteger(requests) || requests < 1) throw new Error('REQUESTS must be positive.');
  if (!Number.isInteger(connections) || connections < 1) throw new Error('CONNECTIONS must be positive.');
  if (!Number.isInteger(runs) || runs < 1) throw new Error('RUNS must be positive.');

  fs.mkdirSync(bin, { recursive: true });
  const results = [];

  for (const server of servers) {
    console.log(`\nBuilding ${server.name}...`);
    runChecked(...server.build);
    server.afterBuild?.();

    const measurements = [];
    for (let run = 1; run <= runs; run += 1) {
      console.log(`Testing ${server.name} (${run}/${runs})...`);
      const child = spawn(server.start[0], server.start[1], {
        cwd: server.start[2],
        stdio: 'ignore',
        windowsHide: true,
      });

      try {
        await waitForPong(child);
        measurements.push(benchmark(child).requestsPerSecond);
      } finally {
        stop(child, server.cleanupImage);
      }
    }

    const median = measurements.slice().sort((a, b) => a - b)[Math.floor(measurements.length / 2)];
    results.push({ server: server.name, median });
  }

  console.log(`\nResults (${connections} connections, ${requests} requests):`);
  console.table(results);
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
