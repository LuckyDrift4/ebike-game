// node run_pose_test.mjs  (needs: npm install @luau-rs/luau)
// Prepends the CFrame/Vector3 stand-ins and RideKit's Config/Rig/Pose modules
// to pose_test.luau and runs it.
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
  wrap('Pose', path.join(kit, 'Pose.lua')) +
  fs.readFileSync(path.join(here, 'pose_test.luau'), 'utf8');
const lua = await Lua.create({ sandbox: false });
const lines = [];
lua.globals.set('print', lua.createFunction((...a) => { lines.push(a.map(String).join('\t')); }));
try { lua.execute(src); } catch (e) { console.log('LUA ERROR:', e.message || e); process.exit(1); }
const out = process.argv[2];
if (out) fs.writeFileSync(out, lines.filter(l => l.startsWith('CASE ')).map(l => l.slice(5)).join('\n') + '\n');
// solved joint transforms -> used by build_ridekit.py for the Animation Editor pose
fs.writeFileSync(path.join(here, 'ride_pose_transforms.json'),
  '[\n' + lines.filter(l => l.startsWith('XFORM ')).map(l => l.slice(6)).join(',\n') + '\n]\n');
for (const l of lines) if (!l.startsWith('CASE ') && !l.startsWith('XFORM ')) console.log(l);
