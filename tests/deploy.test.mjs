import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, rm, writeFile, access } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { deploy } from '../scripts/deploy.mjs';

test('deploy previews and updates only the addon folder, preserving other addons', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'ecf-deploy-'));
  try {
    const addonsPath = path.join(root, 'Game with spaces', 'Interface', 'AddOns');
    await mkdir(addonsPath, { recursive: true });
    const configPath = path.join(root, 'config.json');
    await writeFile(configPath, JSON.stringify({ addonsPath }));
    await writeFile(path.join(addonsPath, 'other-addon.txt'), 'keep');
    const preview = await deploy({ configPath, dryRun: true });
    await assert.rejects(access(preview.destination), { code: 'ENOENT' });
    const result = await deploy({ configPath });
    const manifest = path.join(result.destination, 'EnhancedCombatForever.toc');
    assert.match(await readFile(manifest, 'utf8'), /## Interface: 16001/);
    await access(path.join(result.destination, 'Core.lua'));
    await access(path.join(result.destination, 'Settings.lua'));
    await assert.rejects(access(path.join(result.destination, 'package.json')), { code: 'ENOENT' });
    await writeFile(path.join(result.destination, 'Core.lua'), 'old version');
    await deploy({ configPath });
    assert.notEqual(await readFile(path.join(result.destination, 'Core.lua'), 'utf8'), 'old version');
    assert.equal(await readFile(path.join(addonsPath, 'other-addon.txt'), 'utf8'), 'keep');
    await writeFile(configPath, JSON.stringify({ addonsPath: path.join(root, 'missing') }));
    await assert.rejects(deploy({ configPath }), /does not exist/);
    await writeFile(configPath, JSON.stringify({ addonsPath: '' }));
    await assert.rejects(deploy({ configPath }), /Set addonsPath/);
    await writeFile(configPath, '{invalid');
    await assert.rejects(deploy({ configPath }), /Cannot read deploy config/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
