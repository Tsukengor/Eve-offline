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
export const WEAPON_TYPES = {
  kinetic: 'Кинетическое орудие',
  laser: 'Лазер',
  missile: 'Самонаводящаяся ракета',
  emp: 'Излучатель ЭМИ',
};
const SPECIAL_FIELDS = {
  kinetic: {},
  laser: {
    laser_speed: ['Скорость развёртывания', 1, 20000, 1, 2800],
    laser_duration: ['Длительность луча, с', 0.05, 20, 0.05, 1.4],
    laser_range: ['Дальность луча', 1, 2000, 1, 460],
  },
  missile: {
    missile_speed: ['Скорость ракеты', 1, 2500, 1, 145],
    missile_fuse: ['Время до взрыва, с', 0.05, 20, 0.05, 4.2],
    missile_turn_rate: ['Скорость поворота, °/с', 1, 1440, 1, 135],
    missile_lock_angle: ['Полный угол захвата, °', 1, 360, 1, 112],
    missile_blast_radius: ['Радиус взрыва', 1, 500, 1, 122],
  },
  emp: {
    emp_range: ['Дальность ЭМИ', 1, 2000, 1, 385],
    emp_angle: ['Полный угол конуса, °', 1, 360, 1, 76],
    emp_speed: ['Скорость волны', 1, 5000, 1, 780],
    emp_energy_drain: ['Потеря энергии вблизи', 0, 100, 0.1, 54],
    emp_disable_duration: ['Длительность отключения, с', 0, 30, 0.1, 3.2],
    emp_systems: ['Максимум отключённых систем', 0, 6, 1, 3],
    emp_edge_strength: ['Доля эффекта на краю дальности', 0, 1, 0.01, 0.35],
  },
};
const PRESET = {
  laser: {damage:36,crew_damage:5,breach_chance:0.03,energy_cost:42,cooldown:2.2},
  missile: {damage:59,crew_damage:16,breach_chance:0.4,energy_cost:26,cooldown:2},
  emp: {damage:0,crew_damage:0,breach_chance:0,energy_cost:30,cooldown:2.6},
};
export function weaponFields(type) {
  const fields = {...WEAPON_FIELDS,...SPECIAL_FIELDS[type]};
  if (type === 'laser') {
    for(const [key,label] of Object.entries({damage:'Урон отсеку в секунду',crew_damage:'Урон экипажу в секунду',breach_chance:'Шанс пробоины за секунду'}))
      fields[key] = [label,...fields[key].slice(1)];
  }
  if (type === 'emp') for(const key of ['damage','crew_damage','breach_chance']) delete fields[key];
  return fields;
}
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

export function weaponDefault(type='kinetic') {
  return {type:'eve.weapon',version:1,name:WEAPON_TYPES[type],projectile:type,
    ...Object.fromEntries(Object.entries(weaponFields(type)).map(([k,v])=>[k,v[4]])),...PRESET[type],mounts:[]};
}

export function validWeapon(data) {
  return tagged(data,'eve.weapon') && typeof data.name === 'string' && data.name.trim().length > 0 && data.name.length <= 40 &&
    Object.hasOwn(WEAPON_TYPES,data.projectile) && Object.entries(weaponFields(data.projectile)).every(([key,[,min,max]]) =>
      Number.isFinite(data[key]) && data[key] >= min && data[key] <= max &&
      (key !== 'emp_systems' || Number.isInteger(data[key]))) &&
    Array.isArray(data.mounts) && data.mounts.length <= 12 && data.mounts.every(p =>
      Array.isArray(p) && p.length === 2 && p.every(v=>Number.isFinite(v)&&Math.abs(v)<=256));
}
