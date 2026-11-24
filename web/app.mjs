import {LIMITS,ROOMS,MODULES,STEPS,WEAPON_TYPES,weaponFields,floor,at,fresh,same,edgeKey,inspectLayout,prune,weaponDefault,validWeapon,upgradeWeapon} from './model.mjs';

const $ = (id) => document.getElementById(id);
const element = (tag,text) => {
  const node = document.createElement(tag);
  if (text !== undefined) node.textContent = text;
  return node;
};
const TOOLS = [['paint','Клетка / отсек'],['erase','Удалить клетку'],['door','Внутренняя дверь'],
  ['hatch','Дверь в космос'],['wall','Стена'],['clear-edge','Удалить границу'],['module','Модуль']];
const EDGES = ['door','hatch','wall','clear-edge'];
const EDGE_COLORS = {door:'#8ef3d7',hatch:'#ffba7a',wall:'#a0b0c5'};
const STORAGE = 'eve-offline-shipyard-v1';
let layout = fresh();
let stats;
let tool = 'paint';
let room = 'C';
let moduleKey = 'bridge';
let tab = 'deck';
let cursor = [0,0];
let hint = null;
let stroke = null;
let undo = [];
let redo = [];
let toast;
const board = $('board');
const ctx = board.getContext('2d');
const weaponForm = $('weapon-form');
let weapon = weaponDefault();
let templates = 0;

function message(text, error=false) {
  clearTimeout(toast);
  $('status').textContent = text;
  $('status').classList.toggle('error',error);
  $('status').hidden = false;
  toast = setTimeout(()=>$('status').hidden=true,5000);
}
function saveDraft() {
  try {localStorage.setItem(STORAGE,JSON.stringify({layout,weapon}));} catch { /* Downloads remain available. */ }
}
function snapshot() {
  templates++;
  undo.push(structuredClone(layout));
  if (undo.length > 60) undo.shift();
  redo = [];
}
function restore(from,to) {
  if (!from.length) return;
  to.push(layout);
  layout = from.pop();
  cursor = [0,0];
  sync();
}
function sync(persist=true) {
  if (persist) saveDraft();
  $('name').value = layout.name;
  $('width').value = layout.plan[0].length;
  $('height').value = layout.plan.length;
  update();
}
function update() {
  stats = inspectLayout(layout);
  $('undo').disabled = !undo.length;
  $('redo').disabled = !redo.length;
  $('export').disabled = stats.errors.length > 0;
  const validation = $('validation');
  validation.textContent = stats.errors.length ? stats.errors.join('\n') : 'Готово к импорту в игру';
  validation.classList.toggle('error',stats.errors.length > 0);
  $('dimensions').textContent = layout.plan[0].length+' × '+layout.plan.length+' · '+(stats.cells?.length || 0)+' кл.';
  const legend = Object.entries(ROOMS).map(([key,[label,color]])=>{
    const row=element('div'), swatch=element('span');
    swatch.className='swatch';swatch.style.backgroundColor=color;
    row.append(swatch,element('span',label),element('strong',stats.counts?.[key] ?? 0));
    return row;
  });
  $('legend').replaceChildren(...legend);
  draw();
}
function selectTool(next) {
  tool = next;
  for (const button of $('tools').children) button.setAttribute('aria-pressed',String(button.dataset.tool===next));
  const isModule = next === 'module';
  $('palette-label').hidden = next !== 'paint' && !isModule;
  $('palette-label').firstChild.textContent = isModule ? 'Тип модуля' : 'Тип отсека';
  $('palette').replaceChildren(...Object.entries(isModule ? MODULES : ROOMS).map(([key,data])=>{
    const option=element('option',data[isModule ? 1 : 0]);option.value=key;return option;
  }));
  $('palette').value = isModule ? moduleKey : room;
  $('edge-controls').hidden = !EDGES.includes(next);
  hint = null;
  draw();
}

const PAD=9, CELL=34;
function draw() {
  const width=layout.plan[0].length, height=layout.plan.length;
  const w=width*CELL+2*PAD, h=height*CELL+2*PAD;
  if (board.width!==w || board.height!==h) {board.width=w;board.height=h;}
  ctx.clearRect(0,0,w,h);
  const toPixel = (p) => p.map(n=>PAD+n*CELL);
  for (let y=0;y<height;y++) for (let x=0;x<width;x++) {
    const [px,py]=toPixel([x,y]), kind=at(layout,[x,y]);
    ctx.fillStyle=ROOMS[kind]?.[1] || '#0e1d2b';
    ctx.fillRect(px,py,CELL,CELL);
    ctx.strokeStyle='#2d4357';ctx.lineWidth=1;ctx.strokeRect(px+.5,py+.5,CELL,CELL);
    if (kind === '.') continue;
    if (stats?.visited && !stats.visited.has(String([x,y])) &&
      !Object.values(layout.modules).some(p=>same(p,[x,y]))) {
      ctx.fillStyle='#fb776629';ctx.fillRect(px+1,py+1,CELL-1,CELL-1);
    }
    ctx.fillStyle='#8baeb533';ctx.fillRect(px+4,py+5,6,1);
    for (const [dx,dy] of STEPS) {
      const other=[x+dx,y+dy];
      if (at(layout,other) !== kind && !stats?.edges?.has(edgeKey([x,y],other))) line([x,y],other,'#637c94',2);
    }
  }
  for (const {a,b,kind} of layout.edges) {
    const color=EDGE_COLORS[kind];
    line(a,b,color,kind==='wall'?3:4,kind!=='wall');
    if (kind === 'hatch') {
      const inside = floor(layout,a) ? a : b, outside = same(inside,a) ? b : a;
      exteriorMarker(inside,outside,color);
    }
  }
  for (const [key,p] of Object.entries(layout.modules)) {
    const [x,y]=toPixel(p);
    ctx.fillStyle='#132331';ctx.strokeStyle='#a7c6d4';ctx.lineWidth=1;
    ctx.fillRect(x+7,y+7,CELL-14,CELL-14);ctx.strokeRect(x+7.5,y+7.5,CELL-14,CELL-14);
    ctx.font='bold 12px ui-monospace, monospace';ctx.textAlign='center';ctx.textBaseline='middle';ctx.fillStyle='#d8f6f1';
    ctx.fillText(MODULES[key][0],x+CELL/2,y+CELL/2);
  }
  const [cx,cy]=toPixel(cursor);
  ctx.strokeStyle='#82e6cf';ctx.lineWidth=1.5;ctx.strokeRect(cx+1,cy+1,CELL-2,CELL-2);
  if (hint) line(...hint,EDGE_COLORS[tool] || '#ff9c91',2);
  $('coordinates').textContent='Клетка '+(cursor[0]+1)+', '+(cursor[1]+1);
}

function line(a,b,color,width,gate=false) {
  const mx=PAD+(a[0]+b[0]+1)*CELL/2, my=PAD+(a[1]+b[1]+1)*CELL/2;
  const dx=b[1]-a[1],dy=a[0]-b[0],extent=gate?CELL*.32:CELL/2;
  ctx.beginPath();ctx.strokeStyle=color;ctx.lineWidth=width;
  ctx.moveTo(mx-dx*extent,my-dy*extent);ctx.lineTo(mx+dx*extent,my+dy*extent);ctx.stroke();
}
function exteriorMarker(inside,outside,color) {
  const [dx,dy]=outside.map((n,i)=>n-inside[i]);
  const x=PAD+(inside[0]+.5+dx*.5)*CELL,y=PAD+(inside[1]+.5+dy*.5)*CELL;
  ctx.beginPath();ctx.strokeStyle=color;ctx.lineWidth=1.5;
  ctx.moveTo(x-dy*4+dx,y+dx*4+dy);ctx.lineTo(x+dx*7,y+dy*7);ctx.lineTo(x+dy*4+dx,y-dx*4+dy);ctx.stroke();
}

function pointer(event) {
  const bounds=board.getBoundingClientRect(), x=((event.clientX-bounds.left)*board.width/bounds.width-PAD)/CELL;
  const y=((event.clientY-bounds.top)*board.height/bounds.height-PAD)/CELL;
  const point=[Math.floor(x),Math.floor(y)];
  if (point[0]<0 || point[1]<0 || point[0]>=layout.plan[0].length || point[1]>=layout.plan.length) return null;
  const distances=[y-point[1],x-point[0],1-(x-point[0]),1-(y-point[1])];
  const index=distances.indexOf(Math.min(...distances));
  return {point,other:[point[0]+STEPS[index][0],point[1]+STEPS[index][1]]};
}

function apply(point,other,record=true) {
  if (EDGES.includes(tool)) {
    if (!other) return;
    const count=+floor(layout,point)+ +floor(layout,other);
    const position=layout.edges.findIndex(({a,b})=>edgeKey(a,b)===edgeKey(point,other));
    const remove=tool==='clear-edge'||layout.edges[position]?.kind===tool;
    if (remove && position<0) return;
    if (!remove && (count!==(tool==='hatch'?1:2) || (tool!=='wall' &&
      Object.values(layout.modules).some(p=>same(p,point)||same(p,other))))) {
      message(tool==='hatch'?'Выберите границу свободной клетки и пустоты.':'Выберите границу между подходящими клетками пола.',true);
      return;
    }
    if (record) snapshot();
    if (position>=0) layout.edges.splice(position,1);
    if (!remove) layout.edges.push({kind:tool,a:point,b:other});
  } else if (tool==='module') {
    if (at(layout,point)!==MODULES[moduleKey][0]) {message('Поставьте модуль в отсеке «'+MODULES[moduleKey][1]+'».',true);return;}
    if (record) snapshot();
    if (same(layout.modules[moduleKey],point)) delete layout.modules[moduleKey];
    else layout.modules[moduleKey]=point;
  } else {
    const kind=tool==='erase'?'.':room;
    if (at(layout,point)===kind) return;
    if (record) snapshot();
    const [x,y]=point;
    const row=layout.plan[y];
    layout.plan[y]=row.slice(0,x)+kind+row.slice(x+1);
  }
  prune(layout);
  saveDraft();
  update();
  return true;
}

function download(data) {
  const url=URL.createObjectURL(new Blob([JSON.stringify(data,null,2)+'\n'],{type:'application/json'}));
  const anchor=element('a');
  anchor.href=url;
  anchor.download=(data.name.trim().replace(/[^\p{L}\p{N}_-]+/gu,'-') || 'eve-offline')+'.json';
  document.body.append(anchor);anchor.click();anchor.remove();
  setTimeout(()=>URL.revokeObjectURL(url),1000);
}
async function chooseTemplate(name) {
  let response=await fetch('./layouts/'+name+'.json');
  if (!response.ok) response=await fetch('../deck/layouts/'+name+'.json');
  if (!response.ok) throw new Error('Шаблон недоступен.');
  const data=await response.json();
  const result=inspectLayout(data);
  if (result.errors.length) throw new Error(result.errors[0]);
  return data;
}
async function loadTemplate(record=true) {
  const request=++templates;
  try {
    const data=await chooseTemplate($('template').value);
    if (request!==templates) return;
    if (record) snapshot();
    layout=data;cursor=[0,0];sync();
  } catch (error) {message(error.message,true);}
}
function openJson(id,validate,applyData) {
  $(id).addEventListener('change',async ()=>{
    const file=$(id).files[0];$(id).value='';
    if (!file) return;
    try {
      if (file.size>65536) throw new Error('Файл больше 64 КБ.');
      const data=JSON.parse(await file.text());
      validate(data);applyData(data);
    } catch (error) {message(error instanceof SyntaxError?'Не удалось прочитать JSON.':error.message,true);}
  });
}

for (const [id,label] of TOOLS) {
  const button=element('button',label);button.dataset.tool=id;
  button.onclick=()=>selectTool(id);$('tools').append(button);
}
for (const [label,direction] of [['С',STEPS[0]],['З',STEPS[1]],['В',STEPS[2]],['Ю',STEPS[3]]]) {
  const button=element('button',label);
  button.onclick=()=>apply(cursor,cursor.map((n,i)=>n+direction[i]));
  $('sides').append(button);
}
$('palette').onchange=()=>{if(tool==='module')moduleKey=$('palette').value;else room=$('palette').value;};
$('load-template').onclick=()=>loadTemplate();
$('new-deck').onclick=()=>{templates++;snapshot();layout=fresh(layout.plan[0].length,layout.plan.length);sync();};
$('name').onchange=()=>{snapshot();layout.name=$('name').value.trim() || 'Палуба';sync();};
$('resize').onclick=()=>{
  const fields=[$('width'),$('height')];
  if(fields.some(f=>!f.reportValidity()||!Number.isInteger(f.valueAsNumber))) return;
  const [w,h]=fields.map(f=>f.valueAsNumber);
  snapshot();
  layout.plan=Array.from({length:h},(_,y)=>(layout.plan[y]||'').slice(0,w).padEnd(w,'.'));
  cursor=[0,0];prune(layout);sync();
};
$('undo').onclick=()=>restore(undo,redo);$('redo').onclick=()=>restore(redo,undo);
$('open').onclick=()=>$('layout-file').click();
$('export').onclick=()=>{if (!inspectLayout(layout).errors.length) download(layout);};
openJson('layout-file',data=>{
  const result=inspectLayout(data);
  if(!result.cells) throw new Error(result.errors[0]);
},data=>{
  templates++;snapshot();
  layout={...data,name:typeof data.name==='string'?data.name.slice(0,40):'Палуба',
    modules:Object.fromEntries(Object.keys(MODULES).filter(key=>data.modules[key] &&
      Array.isArray(data.modules[key]) && data.modules[key].length===2).map(key=>[key,data.modules[key]]))};
  prune(layout);cursor=[0,0];sync();
});

board.onpointerdown=event=>{
  if(event.button!==0)return;
  const hit=pointer(event);
  if(!hit)return;
  cursor=hit.point;board.focus({preventScroll:true});
  const changed=apply(hit.point,hit.other);
  if(tool==='paint'||tool==='erase'){stroke={point:String(hit.point),changed};board.setPointerCapture(event.pointerId);}
  draw();
};
board.onpointermove=event=>{
  const hit=pointer(event);
  if(!hit)return;
  cursor=hit.point;hint=EDGES.includes(tool)?[hit.point,hit.other]:null;
  if(stroke!==null&&stroke.point!==String(hit.point)){
    const changed=apply(hit.point,hit.other,!stroke.changed);stroke={point:String(hit.point),changed:changed||stroke.changed};
  } else draw();
};
board.onpointerup=board.onpointercancel=board.onlostpointercapture=()=>{stroke=null;};
board.onpointerleave=()=>{hint=null;draw();};
board.onkeydown=event=>{
  const direction={ArrowUp:STEPS[0],ArrowLeft:STEPS[1],ArrowRight:STEPS[2],ArrowDown:STEPS[3]}[event.key];
  if(direction){
    event.preventDefault();
    cursor=cursor.map((p,i)=>Math.max(0,Math.min(p+direction[i],(i?layout.plan.length:layout.plan[0].length)-1)));
    draw();
  }else if(event.key==='Enter'&&!EDGES.includes(tool)){apply(cursor);event.preventDefault();}
};
document.addEventListener('keydown',event=>{
  if(tab!=='deck'||!(event.ctrlKey||event.metaKey)||event.key.toLowerCase()!=='z'||/^(INPUT|SELECT)$/.test(event.target.tagName))return;
  event.preventDefault();if(event.shiftKey)restore(redo,undo);else restore(undo,redo);
});

function mountRow(point=[0,0]) {
  const row=element('div');row.className='row';
  point.forEach((value,index)=>{
    const input=element('input');input.type='number';input.value=value;input.min=-256;input.max=256;input.step='any';input.required=true;
    input.setAttribute('aria-label',index?'Координата Y':'Координата X');row.append(input);
  });
  const remove=element('button','Удалить');remove.type='button';
  remove.onclick=()=>{row.remove();readWeapon();};
  row.append(remove);$('mounts-list').append(row);
}
function fillWeapon() {
  $('weapon-name').value=weapon.name;
  $('weapon-type').value=weapon.projectile;
  $('weapon-fields').replaceChildren(...Object.entries(weaponFields(weapon.projectile)).map(([key,[label,min,max]])=>{
    const field=element('label',label);field.className='control-label';
    const input=element('input');input.name=key;input.type='number';input.min=min;input.max=max;
    input.step=['emp_systems','laser_ticks_per_second','rail_penetration'].includes(key)?'1':'any';input.required=true;input.value=weapon[key];
    field.append(input);return field;
  }));
  $('mounts-list').replaceChildren();weapon.mounts.forEach(mountRow);readWeapon();
}
function readWeapon() {
  const mounts=[...$('mounts-list').children].map(row=>[...row.querySelectorAll('input')].map(input=>input.valueAsNumber));
  const draft={...weapon,name:$('weapon-name').value,projectile:weaponForm.elements.projectile.value,mounts};
  const fields=weaponFields(draft.projectile);
  for(const key of Object.keys(fields))draft[key]=weaponForm.elements[key].valueAsNumber;
  $('weapon-title').textContent=draft.name||'Без названия';
  $('weapon-stats').replaceChildren(...Object.entries(fields).map(([key,[label]])=>{
    const row=element('div'),value=draft[key];
    row.append(element('dt',label),element('dd',Number.isFinite(value)?(['breach_chance','emp_edge_strength','emp_recovery_suppression','rail_retention'].includes(key)?Math.round(value*100)+' %':String(value)):'—'));
    return row;
  }));
  $('add-mount').disabled=mounts.length>=12;
  if(validWeapon(draft)){weapon=draft;saveDraft();}
  return draft;
}
$('weapon-type').replaceChildren(...Object.entries(WEAPON_TYPES).map(([key,label])=>{
  const option=element('option',label);option.value=key;return option;
}));
$('weapon-type').onchange=event=>{weapon=weaponDefault(event.target.value);fillWeapon();};
weaponForm.oninput=event=>{if(event.target.name!=='projectile')readWeapon();};
weaponForm.onsubmit=event=>{
  event.preventDefault();
  const data=readWeapon();
  if(validWeapon(data))download(data);
  else message("Проверьте название и параметры орудия.",true);
};
$('add-mount').onclick=()=>{if($('mounts-list').children.length<12){mountRow();readWeapon();}};
$('open-weapon').onclick=()=>$('weapon-file').click();
openJson('weapon-file',data=>{if(!validWeapon(data))throw new Error('Нужен корректный статблок оружия Eve Offline версии 1.');},data=>{weapon=upgradeWeapon(data);fillWeapon();});
function switchTab(next){
  tab=next;
  for(const item of ['deck','weapon']){
    $(item+'-editor').hidden=item!==next;
    $(item+'-tab').setAttribute('aria-pressed',String(item===next));
  }
}
$('deck-tab').onclick=()=>switchTab('deck');
$('weapon-tab').onclick=()=>switchTab('weapon');
let hasDraft=false;
try {
  const saved=JSON.parse(localStorage.getItem(STORAGE));
  if(inspectLayout(saved?.layout).cells){layout=saved.layout;hasDraft=true;}
  if(validWeapon(saved?.weapon))weapon=upgradeWeapon(saved.weapon);
} catch { /* A fresh template is still available. */ }
sync(false);selectTool('paint');fillWeapon();
if(!hasDraft)loadTemplate(false);
