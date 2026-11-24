# Спрайты полёта и сектора

## Вражеский бур

`drill_enemy.png` создан встроенным ImageGen и используется сценой `flight/drill_enemy.tscn`.

> Use case: stylized-concept. Single transparent top-down orthographic sprite for a fictional 2D pixel art spaceship game. Small hostile industrial tunneling spaceship with a giant blunt conical mechanical drill nose pointing exactly UP, squat graphite gray armored shell, copper and dark rust metal accents, tiny amber engine ports at bottom. A silhouette distinct from a normal rescue ship, legible at 65 pixels. Original highly readable pixel art, no floor, shadow, text, projectiles or background. Genuine transparency.

## Эффекты тяги и стрельбы

`kinetic_bolt.png`, `maneuver_thruster.png` и `muzzle_flash.png` вырезаны из прозрачного атласа встроенного ImageGen.

> Use case: stylized-concept. Transparent sprite atlas with three isolated original pixel-art space-game visual effects in a horizontal row of equal thirds. Left a small thin straight bright pale-gold tracer bolt pointed UP, retained brighter tip and dim short trailing stroke, silhouette readable at 18 pixels. Center a tiny cyan-blue sideways reaction thruster puff pointing toward RIGHT, thin nozzle end on left, compact exhaust trail. Right a small short amber muzzle flash, pointing UP, simple energetic pointed shape. No spacecraft, no other shapes, no labels or panels, no backdrop, transparent alpha. Style dark-industrial pixel-art space rescue game.

Встроенный ImageGen сгенерировал корабль, две версии станции, факел тяги, три звезды и фон. Из атласов вырезаны отдельные PNG. Локальная карта выбирает спрайт аварийной или безопасной станции, а при повреждении двигателя корабль и выхлоп меняют оттенок.

## Корабль, станции и выхлоп

> Use case: stylized-concept. Asset type: transparent raster sprite atlas for top-down pixel-art space rescue game. Make an exact 2 by 2 layout, one isolated centered object per equal quadrant. Upper left: compact industrial search-and-rescue ship, bow exactly toward the top of frame, chunky readable silver blue hull with muted ochre search-and-rescue markings, two aft thruster nozzles and cyan cockpit, original hard sci-fi. Upper right: intact industrial orbital station, round docking hub, blue-gray steel radial arms and subtle cyan windows. Lower left: the same station silhouette but one bent radial arm, a scar and amber emergency lights, visible at 100 pixels; no smoke beyond the station. Lower right: small softly bright vertical cyan exhaust plume pointing down, widest bright part at its top, isolated, usable as a thruster sprite. Strict overhead orthographic view, near-flat top-down lighting, dark industrial space style, sharp pixel-art silhouette, simple readable silhouette, no text, no floors, no stars, no lettering, no shadow outside object. Genuine transparent alpha everywhere around objects, clean gutters with each object's entire silhouette inside the middle 75% of its own quadrant.

## Звёздный фон

> Use case: stylized-concept. Asset type: dark video game background. Wide 3:2 near-black navy deep-space star field for a top-down space flight tactical display. Low contrast and restrained, very sparse small pinpoints of desaturated blue and white, with one faint blue-violet diffuse dust band toward one corner. Vast quiet space as navigable backdrop, matte blue-black base, readable equipment sprites over all areas. No planets, ships, stations, bright foreground stars, icon marks, framing, gradients to white, or text. Fine pixel-art character but minimal, topology-independent.

## Звёзды на карте

> Use case: stylized-concept. Asset type: transparent raster sprite atlas for a tactical star-sector map in a pixel-art game. Three isolated luminous small top-down star objects arranged in equal thirds of one wide strip, with plenty of clear transparent space between them. From left to right, icy pale blue star, amber orange star, muted mint-teal star. Each star a tiny crisp pixel-art round stellar disc with a simple low-radius colored halo, legible at 24 pixels wide, same size across all variants. No text, sky, planets, drop shadows, frames or interface, genuine transparent background.

## Лазер, ракета и ЭМИ

`laser_beam.png`, `guided_missile.png`, `missile_blast.png` и `emp_spark.png` вырезаны из одного атласа встроенного ImageGen. В полёте они показывают длину луча, ракету, взрыв и фронт ЭМИ. Искры отмечают отключённые системы на палубе и сканере.

> One transparent horizontal 4-cell pixel-art sprite atlas for the fictional 2D Godot space game Eve Offline, strict overhead, crisp bold clusters. Four isolated game effects centered exactly in separate equal quarter-width columns with copious transparent gutters: first column a short violet-white laser streak pointing UP vertically with clean narrow core; second column a tiny dark orange homing missile pointing UP, with small amber exhaust; third column a circular copper-orange explosion sprite with bright center and uneven smoke fringe; fourth column a small icy-cyan electrical arc and spark cluster for an EMP. No lettering, lines between cells, backgrounds, spacecraft, or drop shadows. Genuine alpha transparency. Each sprite reads clearly at 16 to 48 pixels.

## Вращающиеся станции и остовы

`orbital_station.png` создан встроенным ImageGen. `orbital_station_distress.png` использует ту же геометрию с трещиной в броне и аварийной подсветкой. `docking_clamps.png` показывает захват и закрепление у причала. Для остовов каждого противника есть два растровых варианта. Пять кадров `impact_frames.png` показывают попадание, восемь кадров `ship_explosion_frames.png` показывают разрушение корпуса, четыре кадра `crew_blackout_frames.png` показывают отключение корабля после гибели экипажа.

> Use case: stylized-concept. One isolated top-down orthographic industrial orbital port game sprite, sharp detailed restrained pixel art, transparent background. Small central circular machined bearing and mechanical radiator plates, dense muted steel gray navy blocks of habitat and machinery, sparse tiny teal work lights, four aligned short docking piers at cardinal angles exactly centered on axes and ending at the same distance from the center, ring with sturdy panel seam lines, asymmetric minor equipment within circular symmetry. Shape: disk diameter around 70% of the 4 radial arms full span. A technical heavy infrastructure installation rather than a toy or medical facility. No cross, insignia, writing, glyph, icon, numbers, saturated candy colors, lighting effects outside the station, debris, floor or star backdrop. Keep layout centered and inspectable in a 390px game view.

## Роевик и щиты

`swarm_ship.png`, `swarm_wreck.png` и `swarm_derelict.png` показывают носитель и оба состояния его остова. Дроны используют `swarm_drone.png`. `shield_field.png` показывает активное поле, а `shield_hit.png` — короткую вспышку при попадании.

## Приключение и поражение

`salvage_container.png` используется для добычи в космосе и контрактного груза на палубе. `ion_cloud.png` отмечает области утечки энергии в Грозе. При поражении игрока анимация сменяет спрайт корабля на `rescue_wreck.png` или `rescue_derelict.png`.
