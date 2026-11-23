# Спрайты палубы

## Пробоины и кислород

`breach.png`, `life_support.png`, `air_leak.png` и `room_damage.png` вырезаны из прозрачного атласа встроенного ImageGen.

> Use case: stylized-concept. Transparent 2 by 2 sprite atlas of four equal quadrants for a top-down pixel art spaceship deck. Top left small torn hull breach with black inner opening and jagged indigo-metal edges, subtle frost. Top right compact life-support machine with two blue oxygen cylinders and a dark teal display. Bottom left tiny air leak wisps visible from above, cold pale blue. Bottom right short dark-orange damaged module spark and scorched floor mark. One complete isolated object centered in each quadrant, no text, no background, no floor or cast shadow, genuine transparent alpha, original industrial sci-fi, readable at 24 pixels.

## Наводчик и отсек вооружения

Ива использует `gunner.png`, `gunner_squeeze.png`, `gunner_seated.png` и атлас рабочих поз `work/gunner_work.png`. Отсек оформлен с помощью `weapons_console.png` и `weapons_floor.png`. Материалы сгенерированы встроенным ImageGen.

### Наводчик и пульт

> Use case: stylized-concept. Transparent raster 2x2 sprite atlas for a fixed-camera top-down 2D pixel-art space ship interior. Exactly one sprite at each equal quadrant center, separated by wide transparent gutters. Upper left a compact plum-purple and silver helmeted human gunner in view from slightly above, idle standing south facing, dark visor, boots visible. Upper right the same plum gunner leaning and turning sideways to squeeze past another person, elbows tucked, wide recognizable helmet. Lower left the same plum gunner seated in a slate cockpit chair facing NORTH toward top of canvas, viewed overhead with arms reaching up, dark chair back at bottom, no console included. Lower right a compact metallic fixed weapon-control console (science fiction, two handgrips, one amber reticle display on a dark blue casing), front controls on south edge, without any chair or character. Original industrial pixel art, sharp clean shapes, legible at 30 pixels. No logos, text, ground, shadow, or backdrop. Truly transparent alpha, each complete figure inside its own quadrant.

### Напольная плитка

> Use case: stylized-concept. A single opaque square top-down 2D tile for a restrained industrial space ship deck. Dark charcoal navy matte plain surface covering over 90%, faint 1px cell seams and two tiny desaturated plum and muted gold identification marks along one edge. Minimalist and darker than crew sprites. No bolts, highlights, damage, texture grain, vents, light pools or text. Square covers the entire image with no surrounding canvas.

### Рабочие позы

> Use case: stylized-concept. Transparent 4 by 2 raster sprite atlas, exactly one compact plum-purple helmeted spaceship crew character in each of 8 equal cells, industrial top-down pixel art, original, uniform plum-purple armor and dark visor, no text or ground, transparent backdrop. Fixed camera and independently drawn poses, not rotated images. Top row left to right: crouched using wrench toward NORTH/up, then SOUTH/down, then WEST/left, then EAST/right. Bottom row: standing viewed from back or rear three-quarter, one gloved hand reaching toward an off-image rescue control panel toward NORTH/up, then SOUTH/down, then WEST/left, then EAST/right. Keep anatomy readable with direction of hand clearly distinct. No consoles, no props except wrench, no shared backdrop or frame, generous gutters inside every equal cell.

### Уточнение ракурсов у шлюза

> Use case: identity-preserve. Game sprite sheet on transparency. The input sheet is a character identity and artwork reference for the plum-purple gunner. Draw exactly three isolated sprites of that same gunner in a single wide row of equal thirds, compact industrial pixel art in the original proportions, fixed high orthographic overhead camera. They work at an off-sprite console with a slightly forward lean and an arm reaching toward it. Left third: reaching toward the BOTTOM of the canvas, leaning deeply enough that the overhead camera sees the crown of the helmet and the dark square life-support backpack; boots trail behind toward the top, hands reach DOWN. Middle third: reaching horizontally LEFT, rear three-quarter view with visible backpack. Right third: reaching horizontally RIGHT, rear three-quarter view with visible backpack. The back plates and harness are the recognizable side, no chest insignia, no front portrait, no face or full visor. Do not rotate any drawing to fake a direction. Three same-scale sprites, entirely in their own columns. No equipment, floor, text, backdrop, shadows or checkerboard. Genuine transparency.

Атласы сгенерированы встроенным ImageGen. У экипажа и модулей сохранён альфа-канал. Открытая дверь в сцене собирается из верхней и нижней частей спрайта двери.

## Рабочие спрайты по направлениям

В папке `work/` восемь атласов встроенного ImageGen. Для ремонта двигателя и работы со спасательным пультом есть отдельный атлас на каждую сторону. В каждом атласе три кадра по 128 × 128 пикселей в порядке Мира, Лев, Ника. Игра выбирает готовый кадр по стороне подхода. У мостика одно кресло к югу от консоли, поэтому там используются сидячие кадры `*_helm.png`.

Промпт каждого атласа составлен из общей части, описания действия и строки направления после слов `All three face`.

### Общая часть

> Use case: identity-preserve. Asset type: transparent 2D game sprite atlas. Input images 1–3 are character identity and pixel-art style references. Draw exactly three original game sprites, one per equal third in a wide horizontal row: ice-blue pilot, amber engineer, sea-green rescuer. Keep recognizable top helmet stripes, suit palette and trim. Strictly direct overhead from above, independent hand-drawn pose for this cardinal direction. Keep each subject separate with its complete silhouette centered in its third. Equal scale and flat lighting, minimal bold detail legible at 31 px tall. No machines, floor, body shadows, background, labels or checkerboard. Truly transparent around each silhouette. Make the arm that uses the off-image device visually indicate the direction.

### Действие

> All three kneel to repair a machine just outside their sprite. Bold silver wrench with open jaw at the tip of the extended hand; bent knees, widened working silhouette. Wrench extends toward the machine, no sparks.

> All three stand to operate a rescue console just outside their sprite. Clearly show the BACK of the suit, including dark rear backpack plate and rear helmet, and avoid a front-facing portrait, visible face or full visor. One arm clearly extends toward the console; the other holds a small restrained cyan wrist display. Hands are up in a working posture toward the panel, not waving. No large tablet or wrench.

### Направление

- NORTH / UP, towards the top edge. Show the rear of the helmets and backplates, with arms and hands reaching upward on the flat canvas, clearly no face, visor, chest badge or front torso. Boots and body trail below the working hands.
- SOUTH / DOWN, towards the bottom edge. In a directly overhead pose the arms and hands reach DOWN on the flat canvas, with the body and boot placement clearly behind toward the top. Draw this posture separately with appropriate gravity and body anatomy, do not turn an up-facing portrait upside down.
- WEST / LEFT, towards the left edge. A separately drawn west-facing profile from overhead with a small amount of the crew member's back visible. Arms and hands extend horizontally to the left, boots trail right behind the body.
- EAST / RIGHT, towards the right edge. A separately drawn east-facing profile from overhead with a small amount of the crew member's back visible. Arms and hands extend horizontally to the right, boots trail left behind the body.

### Уточнение спрайта у пульта справа

> Use case: precise-object-edit. Asset type: transparent top-down game atlas with three characters. Image 1 is the edit target and fixes the exactly three characters and rightward reach. Image 2 is a rear-view reference for the dark rectangular life-support packs and helmet backs. Redraw the torsos and helmets in Image 1 so each figure reads unambiguously from behind in a rear three-quarter overhead view, reaching to the RIGHT with a gloved hand. Show the raised rectangular back-mounted life-support box with hose and shoulder harness as in Image 2. Hide the chest insignia, breastplate, full visor and front of the torso. Preserve three identities, accents, eastward direction, neutral shadows, high-quality pixel art, independent positioning within each horizontal third, equal scale and genuine transparency. No floor, no text or frame.

## Цветной пол и работа экипажа

Четыре файла `*_floor_v2.png` содержат отдельные цвета и маркировку для каждого покрытия. Прозрачные позы `*_helm.png`, `*_repair.png` и `*_airlock.png` сделаны для каждого члена экипажа. Рабочие позы ориентированы к устройству, а кресло входит в спрайт сидящего оператора. `bridge_console_v2.png` содержит отдельно отрисованную консоль.

### Цветные тайлы

> Use case: stylized-concept. Asset type: square 2x2 orthographic video game floor tile atlas. Four contiguous equal quadrants of square tiles exactly aligned to the canvas, no margins, no gutters. Original understated industrial spaceship floor, flat dark navy steel with subtle cell seams; at least 85% of each tile is quietly colored plain matte dark surface with no texture. Each tile has only two short small painted identification dashes along a single edge, restrained two-color accents, clear at 44 pixels. Top left midnight-blue bridge steel with small muted ice blue and slate marks; top right blue-black engineering tile with small rust and muted amber marks; bottom left deep charcoal-teal rescue tile with desaturated teal and warm-gray marks; bottom right cool dark slate corridor tile with short muted blue and copper dashes. Avoid glowing lines, vents, hazard stripes, checkerboard, grunge, bolts, repeated geometric patterns, text or large motifs. Four distinct muted palettes. Crisp hand-painted 2D pixel art and dark enough for colorful characters to read on top.

### Экипаж в кресле

> Use case: identity-preserve. Asset type: 2D game sprite atlas on genuine transparency. Input images 1–3 are character identity and style references. Exactly three isolated matching original pixel-art characters in one wide row of equal thirds, blue-and-white pilot at left, amber engineer in middle, sea-green rescue specialist at right. Preserve their distinct helmet and colored uniform. Every sprite is centered entirely within its own third with generous clear gutters. Same scale and placement in every third, strict orthographic directly overhead, face north (toward the top of the canvas), bold readable silhouette. No text, no floor, no drop shadow, no checkerboard, no backdrop, no extraneous objects. The pose must read at 34 pixels tall. All three are distinctly seated low in the same compact slate-colored industrial cockpit chair, viewed over the back of the chair, helmet seen from above, forearms reaching forward to operate controls near the top of the sprite, bent knees beside the seat if visible. The chair outlines and cushions read clearly as a seat. Compact composite of person and chair only; no desk, no console.

### Ремонт двигателя

> Use case: identity-preserve. Asset type: 2D game sprite atlas on genuine transparency. Input images 1–3 are character identity and style references. Exactly three isolated matching original pixel-art characters in one wide row of equal thirds, blue-and-white pilot at left, amber engineer in middle, sea-green rescue specialist at right. Preserve their distinct helmet and colored uniform. Every sprite is centered entirely within its own third with generous clear gutters. Same scale and placement in every third, strict orthographic directly overhead, face north (toward the top of the canvas), bold readable silhouette. No text, no floor, no drop shadow, no checkerboard, no backdrop, no extraneous objects. The pose must read at 34 pixels tall. All three crouch forward to repair a machine near the top edge of their tile, helmet lowered, one hand in front holding a short bright wrench with a clear open jaw, other hand extended forward bracing. The figure and wrench form a compact single silhouette. No machine or sparks; the machine is a separate sprite.

### Работа со шлюзом

> Use case: identity-preserve. Asset type: 2D game sprite atlas on genuine transparency. Input images 1–3 are character identity and style references. Exactly three isolated matching original pixel-art characters in one wide row of equal thirds, blue-and-white pilot at left, amber engineer in middle, sea-green rescue specialist at right. Preserve their distinct helmet and colored uniform. Every sprite is centered entirely within its own third with generous clear gutters. Same scale and placement in every third, strict orthographic directly overhead, face north (toward the top of the canvas), bold readable silhouette. No text, no floor, no drop shadow, no checkerboard, no backdrop, no extraneous objects. The pose must read at 34 pixels tall. All three stand leaning forward to operate a wall-mounted airlock panel which is off-sprite to the north. One arm extends forward to push the controls, the other holds a compact cyan status tablet close to the chest. Make the squared shoulders and outstretched hand read clearly from above. No wall, no panel. Avoid wrench or power tools.

### Консоль мостика

> Use case: precise-object-edit. Asset type: single transparent sprite for a 2D game. Input image is the edit target. Keep this exact dark industrial top-down pixel-art cockpit control console with its cyan central monitor, two smaller side displays and low steel control deck. Remove the entire orange-backed seat and its attachment from the bottom center, with truly transparent pixels below the console. Complete the lower edge of the console in matching steel if needed. Keep palette, design, framing and transparency around the console; no text or other objects.

## Минималистичный пол

Встроенный ImageGen сгенерировал атлас, из которого вырезаны `floor_tile.png`, `floor_wall_trim.png` и `floor_threshold.png`. Основная клетка получает оттенок своего покрытия в сцене. Кромка прижимается к внешней границе пола, а порог центрируется на стыке двух покрытий.

Промпт для атласа

> Use case: stylized-concept. Asset type: production 2D Godot spaceship deck tileset, transparent sprite atlas. One horizontal strip of three separate isolated rectangular samples, with ample empty transparent gutters. Left sample: an exactly square, opaque, solid flat cool charcoal navy floor tile, near #223347, with at most a very subtle one-pixel dark seam on the south and east edges. Absolutely no grain, no bolts, scratches, vents, plates, stripes, gradient, borders or motifs on its inside. Middle sample: a perfectly straight thick dark steel horizontal wall toe-kick trim, with a slim blue gray beveled edge, flat top-down 2D pixel art, very restrained, continuous from end to end, no end caps, no screws, no markings, transparent everywhere outside the narrow strip. Right sample: a perfectly straight very thin horizontal dark desaturated steel seam for the threshold between two walkable room floor types, one dark line and a subtle slate-blue lip, continuous from end to end, no end caps, transparent outside the narrow strip. All three are original industrial hard sci-fi artwork, strict orthographic overhead, no perspective, no drop shadows, no text, no extra objects. Each sample centered in its own equal horizontal third, no overlap. All graphics align to horizontal and vertical axes. Very quiet contrast for tiny readable characters on top.

## Экипаж

Use case: stylized-concept. Asset type: 2D raster sprite atlas for a Godot game. Aesthetic: original retro industrial science fiction, crisp hand-painted pixel-art, legible at small scales, deep navy palette with restrained accents. A single game-ready transparent sprite atlas exactly 2 columns by 2 rows, equal quadrants. One isolated small full-body top-down game character in each of the first three quadrant centers: upper left a pilot in ice-blue armored flight suit, upper right an engineer in warm amber armored suit with small toolpack, lower left a rescue specialist in mint-teal armored suit with a white medical shoulder stripe. Leave lower right completely transparent. All wearing space helmets, facing south, clear iconic shape, strict orthographic almost directly overhead, head and torso and boots visible. All three same scale. Each sprite entirely inside central 65% of its own quadrant. No floor, no shadows beyond silhouette, no text, no frames.

### Поза при расхождении

Кадры `pilot_squeeze.png`, `engineer_squeeze.png` и `rescuer_squeeze.png` сгенерированы встроенным ImageGen на основе трёх спрайтов экипажа. Игра сочетает смену кадра с плавным смещением и наклоном персонажа. Анимация двери использует верхнюю и нижнюю половины `bulkhead_door.png` как створки.

> Use case: identity-preserve. Asset type: transparent 2D game sprite atlas with three alternate poses in one wide horizontal row with equal thirds. The three input images are character identity and style references, left to right blue-white pilot, amber engineer, green medic. Draw exactly one alternate sidestep pose of each, centered in its own third, left to right in the same order. Keep the existing overhead/front orthographic view, identical suit colors, helmets, compact pixel art scale and silhouettes. Show a squeeze past another person by hunching slightly, drawing elbows tight and turning shoulders sideways to the right, one leg slightly ahead; full body with boots. Same foot line and height across all three. Isolated sprites on genuinely transparent background, no floors, no cast shadows, no text, no props or additional figures, no frames or boxes. Keep each figure fully inside its own third with generous space.

## Корабельные модули и дверь

Use case: stylized-concept. Asset type: 2D raster sprite atlas for a Godot game. Aesthetic: original retro industrial science fiction, crisp hand-painted pixel-art, legible at small scales, deep navy palette with restrained accents. Single transparent game sprite atlas, exactly 2 x 2 equal quadrants. One isolated strict top-down orthographic sci-fi prop per quadrant, centered within central 70% of quadrant: top left compact ship pilot console with ice-blue monitor, top right main reactor assembly with two thick pipes and an amber status lamp, bottom left compact rescue airlock controls with teal oxygen tanks, bottom right left-right traversable heavy bulkhead door, depicted as a vertical narrow metal bar on the canvas with bright orange center. Transparent gaps, naked silhouettes, no shared background, no floor, no text, no framing.

## Первый набор покрытий палубы

Use case: stylized-concept. Asset type: 2D raster sprite atlas for a Godot game. Aesthetic: original retro industrial science fiction, crisp hand-painted pixel-art, legible at small scales, deep navy palette with restrained accents. Single square opaque 2 x 2 atlas for a strict orthographic top-down spaceship tactics game, four contiguous square tiles occupying the exact four equal quadrants, all tile graphics aligned to quadrant boundaries with no gaps, no margins and no cross-quadrant details. Top left: cool blue dark metal bridge floor; top right: charcoal blue engineering floor with interior copper details; bottom left: slate blue muted rescue bay flooring with subtle teal details; bottom right: navy utilitarian corridor flooring. Each quarter shows one complete restrained square metal plate, clear four square boundaries, muted values, fine mechanical details kept subtle for character legibility, flat lighting, clean metal texture. No text, no numbers, no external border.
