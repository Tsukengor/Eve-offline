import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {edgeKey,fresh,inspectLayout,prune,validWeapon,weaponDefault,upgradeWeapon} from '../web/model.mjs';

const layout = (name) => JSON.parse(readFileSync(new URL('../deck/layouts/'+name+'.json',import.meta.url),'utf8'));

test('the editor accepts the layouts shipped with Godot',()=>{
  for (const name of ['rescue','drill','fighter','swarm']) assert.deepEqual(inspectLayout(layout(name)).errors,[]);
});

test('an exterior hatch is valid and disappears when its floor is erased',()=>{
  const data=layout('rescue');
  data.edges.push({kind:'hatch',a:[3,1],b:[3,0]});
  assert.deepEqual(inspectLayout(data).errors,[]);
  data.plan[1]=data.plan[1].slice(0,3)+'.'+data.plan[1].slice(4);
  prune(data);
  assert.ok(!data.edges.some(edge=>edge.kind==='hatch'));
  assert.deepEqual(inspectLayout(data).errors,[]);
});

test('disconnected compartments, duplicate edges and empty decks cannot export as playable layouts',()=>{
  const data=layout('rescue');
  data.edges = data.edges.filter(edge => !edge.a.includes(6) && !edge.b.includes(6));
  assert.match(inspectLayout(data).errors.at(-1),/изолированные/);
  data.edges.push({...data.edges[0],a:data.edges[0].b,b:data.edges[0].a});
  assert.match(inspectLayout(data).errors[0],/повторяющаяся/);
  assert.equal(edgeKey([2,3],[1,3]),edgeKey([1,3],[2,3]));
  assert.ok(inspectLayout(fresh()).errors.length);
});

test('weapon stat blocks accept valid mounts and reject unsupported values',()=>{
  const sample={...weaponDefault(),mounts:[[-11,-13],[11,-13]]};
  assert.ok(validWeapon(sample));
  assert.ok(!validWeapon({...sample,breach_chance:5}));
  assert.ok(!validWeapon({...sample,mounts:[[Infinity,0]]}));
});

test('the shipyard exports laser, missile and EMP parameters with the correct kind',()=>{
  for (const type of ['laser','missile','emp']) assert.ok(validWeapon(weaponDefault(type)));
  assert.ok(!validWeapon({...weaponDefault('laser'),laser_energy_per_second:0}));
  assert.ok(!validWeapon({...weaponDefault('missile'),missile_blast_radius:-1}));
  assert.ok(!validWeapon({...weaponDefault('emp'),emp_systems:1.5}));
  assert.ok(!validWeapon({...weaponDefault('emp'),emp_edge_strength:1.5}));
  assert.ok(!validWeapon({...weaponDefault('emp'),emp_recovery_suppression:1.5}));
});

test('the shipyard exports railguns and sets a laser tick rate',()=>{
  assert.ok(validWeapon(weaponDefault('rail')));
  assert.ok(!Object.hasOwn(weaponDefault('laser'),'laser_range'));
  assert.equal(weaponDefault('laser').laser_ticks_per_second,12);
  const legacy={...weaponDefault('laser'),laser_range:460,laser_speed:2800};
  delete legacy.laser_ticks_per_second;
  assert.ok(validWeapon(legacy));
  assert.deepEqual(upgradeWeapon(legacy),weaponDefault('laser'));
  assert.ok(!validWeapon({...weaponDefault('laser'),laser_ticks_per_second:16}));
  assert.ok(!validWeapon({...weaponDefault('rail'),rail_penetration:1.5}));
  for (const removed of ['flak','push']) assert.ok(!validWeapon({...weaponDefault(),projectile:removed}));
});
