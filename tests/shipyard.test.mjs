import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {edgeKey,fresh,inspectLayout,prune,validWeapon,weaponDefault} from '../web/model.mjs';

const layout = (name) => JSON.parse(readFileSync(new URL('../deck/layouts/'+name+'.json',import.meta.url),'utf8'));

test('the editor accepts the three layouts shipped with Godot',()=>{
  for (const name of ['rescue','drill','fighter']) assert.deepEqual(inspectLayout(layout(name)).errors,[]);
});

test('an exterior hatch is valid and disappears when its floor is erased',()=>{
  const data=layout('rescue');
  data.edges.push({kind:'hatch',a:[1,1],b:[0,1]});
  assert.deepEqual(inspectLayout(data).errors,[]);
  data.plan[1]=data.plan[1].slice(0,1)+'.'+data.plan[1].slice(2);
  prune(data);
  assert.ok(!data.edges.some(edge=>edge.kind==='hatch'));
  assert.deepEqual(inspectLayout(data).errors,[]);
});

test('disconnected compartments, duplicate edges and empty decks cannot export as playable layouts',()=>{
  const data=layout('rescue');
  data.edges.shift();
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
