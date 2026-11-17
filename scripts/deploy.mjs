import { cp, readFile, realpath, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const projectRoot = fileURLToPath(new URL('../', import.meta.url));
const addonName = 'EnhancedCombatForever';

export async function deploy({ configPath = path.join(projectRoot, 'deploy.config.json'), dryRun = false } = {}) {
  let config;
  try {
    config = JSON.parse(await readFile(configPath, 'utf8'));
  } catch (error) {
    if (error.code === 'ENOENT') {
      throw new Error('Create deploy.config.json from deploy.config.example.json and set addonsPath.');
    }
    throw new Error(`Cannot read deploy config: ${error.message}`);
  }
  if (typeof config.addonsPath !== 'string' || !config.addonsPath.trim()) {
    throw new Error('Set addonsPath in deploy.config.json to your existing Interface/AddOns directory.');
  }
  if (process.platform !== 'win32' && /^[a-z]:[\\/]/i.test(config.addonsPath)) {
    throw new Error('Use a Linux path in this terminal. For WSL, C:\\... becomes /mnt/c/... .');
  }
  if (!path.isAbsolute(config.addonsPath)) {
    throw new Error('addonsPath must be an absolute path.');
  }
  let addonsPath;
  try {
    addonsPath = await realpath(config.addonsPath);
    if (!(await stat(addonsPath)).isDirectory()) throw new Error('not a directory');
  } catch {
    throw new Error(`AddOns directory does not exist or is inaccessible: ${config.addonsPath}`);
  }
  const source = await realpath(path.join(projectRoot, addonName));
  const destination = path.join(addonsPath, addonName);
  const relative = path.relative(source, destination);
  if (relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative))) {
    throw new Error('Deployment destination must be outside the source addon folder.');
  }
  await stat(path.join(source, `${addonName}.toc`));
  if (!dryRun) {
    await cp(source, destination, { recursive: true, force: true });
  }
  return { source, destination, dryRun };
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try {
    const args = process.argv.slice(2);
    if (args.some(arg => arg !== '--dry-run')) throw new Error('Usage: npm run deploy -- [--dry-run]');
    const result = await deploy({ dryRun: args.includes('--dry-run') });
    console.log(`${result.dryRun ? 'Would copy' : 'Copied'} ${result.source}\nTo ${result.destination}`);
    if (!result.dryRun) console.log('First install: restart WoW. Updates: use /reload in game.');
  } catch (error) {
    console.error(`Deploy failed: ${error.message}`);
    process.exitCode = 1;
  }
}
