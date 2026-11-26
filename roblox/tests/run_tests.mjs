// node run_tests.mjs [test.luau]   (needs: npm install @luau-rs/luau)
// Runs a Luau test with the CFrame/Vector3 stand-ins and RideKit's modules prepended.
import { Lua } from '@luau-rs/luau';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
const here = path.dirname(fileURLToPath(import.meta.url));
const kit = path.join(here, '..', 'RideKit');
const wrap = (name, file) => `local ${name} = (function()\n${fs.readFileSync(file, 'utf8')}\nend)()\n`;
const src =
  wrap('rbx', path.join(here, 'rbxmath.luau')) +
  'local Vector3, CFrame = rbx.Vector3, rbx.CFrame\n' +
  wrap('Config', path.join(kit, 'Config.lua')).replace(/Enum\.KeyCode\.\w+/g, '0') +
  wrap('Rig', path.join(kit, 'Rig.lua')) +
  wrap('Physics', path.join(kit, 'Physics.lua')) +
  wrap('AnimPlayer', path.join(kit, 'AnimPlayer.lua')) +
  (fs.existsSync(path.join(kit, 'AnimData.lua')) ? wrap('AnimData', path.join(kit, 'AnimData.lua')) : '') +
  wrap('Bikes', path.join(here, 'bikes_data.luau')) +
  (fs.existsSync(path.join(here, 'bike_ref.luau')) ? wrap('BikeRef', path.join(here, 'bike_ref.luau')) : '') +
  fs.readFileSync(path.join(here, process.argv[2] || 'rig_test.luau'), 'utf8');
const lua = await Lua.create({ sandbox: false });
const lines = [];
lua.globals.set('print', lua.createFunction((...a) => { lines.push(a.map(String).join('\t')); }));
try { lua.execute(src); } catch (e) { console.log('LUA ERROR:', e.message || e); process.exit(1); }
const ref = lines.find(l => l.startsWith('REF '));
if (ref) fs.writeFileSync(path.join(here, '..', '..', 'blender', 'anim', 'bike_ref.json'), JSON.stringify(JSON.parse(ref.slice(4)), null, 1) + '\n');
for (const l of lines) if (!l.startsWith('REF ')) console.log(l);
if (lines.some(l => / FAILED$|^FAIL/.test(l))) process.exit(1);
