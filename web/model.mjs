export const LIMITS = {width: 24, height: 18};
export const ROOMS = {
  C: ['Коридор', '#233a52'], B: ['Мостик', '#254664'], E: ['Двигатели', '#553e3a'],
  S: ['Шлюз', '#285049'], W: ['Вооружение', '#51415d'], L: ['Кислород', '#275368'], R: ['Реактор', '#574a35'],
};
export const MODULES = {
  bridge: ['B', 'Мостик'], engine: ['E', 'Двигатели'], airlock: ['S', 'Шлюз'],
  weapons: ['W', 'Вооружение'], life_support: ['L', 'Кислород'], reactor: ['R', 'Реактор'],
};
export const STEPS = [[0,-1],[-1,0],[1,0],[0,1]];
export const WEAPON_FIELDS = {
  damage: ['Урон отсеку', 0, 1000, 0.1, 27],
  crew_damage: ['Урон экипажу', 0, 1000, 0.1, 9],
  breach_chance: ['Шанс пробоины', 0, 1, 0.01, 0.25],
  cooldown: ['Интервал, с', 0.01, 10, 0.01, 0.32],
  energy_cost: ['Энергия за выстрел', 0, 100, 0.1, 12],
  damaged_spread_degrees: ['Разброс при повреждении, °', 0, 45, 0.5, 18],
  muzzle_offset: ['Вынос ствола', -256, 256, 0.1, 35],
};
const coords = (p) => Array.isArray(p) && p.length === 2 && p.every(n => Number.isInteger(n) && n >= -1 && n <= LIMITS.width);
export const same = (a,b) => a?.[0] === b?.[0] && a?.[1] === b?.[1];
const stepsFrom = ([x,y], directions = STEPS) => directions.map(([dx,dy]) => [x+dx,y+dy]);
export const edgeKey = (a,b) => (a[1] < b[1] || (a[1] === b[1] && a[0] < b[0]) ? [a,b] : [b,a]).join(':');
export const at = (layout, [x,y]) => x >= 0 && y >= 0 ? layout.plan[y]?.[x] || '.' : '.';
export const floor = (layout,p) => at(layout,p) !== '.';
export const fresh = (width=17,height=13) => ({
  type:'eve.ship-layout',version:1,name:'Новая палуба',plan:Array.from({length:height},()=>'.'.repeat(width)),
  modules:{},edges:[],
});
const tagged = (data,type) => !!data && data.type === type && data.version === 1;

export function inspectLayout(data) {
  if (!tagged(data,'eve.ship-layout')) return {errors:['Нужен JSON палубы Eve Offline версии 1.']};
  const rows = data.plan;
  const width = rows?.[0]?.length;
  if (!Array.isArray(rows) || !rows.length || rows.length > LIMITS.height || !width || width > LIMITS.width ||
    rows.some(row => typeof row !== 'string' || row.length !== width || /[^.CBESWLR]/.test(row)) ||
    !data.modules || typeof data.modules !== 'object' || Array.isArray(data.modules) || !Array.isArray(data.edges)) {
    return {errors:['Проверьте размеры и содержимое сетки, модулей и границ.']};
  }
  const counts = {};
  const cells = [];
  rows.forEach((row,y) => [...row].forEach((kind,x) => {
    if (kind === '.') return;
    counts[kind] = (counts[kind] || 0) + 1;
    cells.push([x,y]);
  }));
  const errors = [];
  const equipment = [];
  for (const [key,[kind,label]] of Object.entries(MODULES)) {
    const point = data.modules[key];
    if (!coords(point) || at(data,point) !== kind) errors.push('Установите модуль «'+label+'».');
    else equipment.push(point);
  }
  const excludes = p => equipment.some(tile => same(tile,p));
  const edges = new Map();
  for (const item of data.edges) {
    const {kind,a,b} = item || {};
    if (!coords(a) || !coords(b) || Math.abs(a[0]-b[0])+Math.abs(a[1]-b[1]) !== 1 || edges.has(edgeKey(a,b))) {
      return {errors:['Некорректная или повторяющаяся граница.']};
    }
    const ends = Number(floor(data,a)) + Number(floor(data,b));
    if (!((kind === 'wall' && ends === 2) || (!excludes(a) && !excludes(b) &&
      ((kind === 'door' && ends === 2) || (kind === 'hatch' && ends === 1))))) {
      return {errors:['Проверьте границы дверей и стен.']};
    }
    edges.set(edgeKey(a,b),kind);
  }
  for (const [key,[kind,label]] of Object.entries(MODULES)) {
    const point = data.modules[key];
    if (!coords(point) || at(data,point) !== kind) continue;
    const directions = ['engine','airlock'].includes(key) ? STEPS : [[0,1]];
    if (!stepsFrom(point,directions).some(p => at(data,p) === kind && !excludes(p) && edges.get(edgeKey(point,p)) !== 'wall'))
      errors.push('Оставьте рабочее место у модуля «'+label+'».');
  }
  const walk = cells.filter(p => !excludes(p));
  const stack = walk.length ? [walk[0]] : [];
  const visited = new Set(stack.map(String));
  while (stack.length) {
    const a = stack.pop();
    for (const b of stepsFrom(a)) {
      const connection = edges.get(edgeKey(a,b));
      if (!floor(data,b) || excludes(b) || visited.has(String(b)) ||
        !(connection === 'door' || (connection !== 'wall' && at(data,a) === at(data,b)))) continue;
      visited.add(String(b));
      stack.push(b);
    }
  }
  if (visited.size < walk.length) errors.push('Есть изолированные клетки. Соедините отсеки проходами или дверями.');
  return {errors,counts,cells,edges,visited};
}

export function prune(layout) {
  for (const [key,point] of Object.entries(layout.modules)) {
    if (!Object.hasOwn(MODULES,key) || at(layout,point) !== MODULES[key][0]) delete layout.modules[key];
  }
  const equipment = Object.values(layout.modules);
  const inside = ([x,y]) => x >= -1 && y >= -1 && x <= layout.plan[0].length && y <= layout.plan.length;
  layout.edges = layout.edges.filter(({a,b,kind}) => {
    if (!inside(a) || !inside(b)) return false;
    const count = +floor(layout,a) + +floor(layout,b);
    return kind === 'wall' ? count === 2 : !(equipment.some(p => same(a,p) || same(b,p))) &&
      count === (kind === 'door' ? 2 : 1);
  });
}

export function weaponDefault() {
  return {type:'eve.weapon',version:1,name:'Кинетическое орудие',projectile:'kinetic',
    ...Object.fromEntries(Object.entries(WEAPON_FIELDS).map(([k,v])=>[k,v[4]])),mounts:[]};
}

export function validWeapon(data) {
  return tagged(data,'eve.weapon') && typeof data.name === 'string' && data.name.trim().length > 0 && data.name.length <= 40 &&
    data.projectile === 'kinetic' && Object.entries(WEAPON_FIELDS).every(([key,[,min,max]]) =>
      Number.isFinite(data[key]) && data[key] >= min && data[key] <= max) &&
    Array.isArray(data.mounts) && data.mounts.length <= 12 && data.mounts.every(p =>
      Array.isArray(p) && p.length === 2 && p.every(v=>Number.isFinite(v)&&Math.abs(v)<=256));
}
