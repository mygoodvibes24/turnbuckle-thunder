# City 2 City Wrestling — Backyard Brawl

A 3D hardcore **backyard** wrestling game with a PS2-era / late-90s console look (low-res, soft
bilinear textures, gentle dither), built in Godot 4.4 for the **browser** and for **iPhone / iPad via
Xogot**. There is no ring: two friends fight on the lawn and the concrete patio of a suburban backyard
at night, under floodlights and string lights, while the neighbors watch from lawn chairs. They swing
steel chairs, trash cans and 2x4s, put each other through folding tables, bounce off the privacy fence
and dive off the picnic table, the car hood, the trampoline and the shed roof. Comedic-hardcore, PG-13:
no blood, just bad decisions.

- **TANK MAGRUDER** (you): a big Black brawler with short dreads.
- **LIL PELIGRO** (CPU): a skinny kid in a cheap Halloween mask.

First pin wins. Everything (yard, house, crowd, wrestlers, weapons, animations, HUD, sound) is generated
in GDScript, so there are no assets to import.

## Play it
**In the browser:** <https://mygoodvibes24.github.io/turnbuckle-thunder/> (rebuilt from `main` on every
push). Click / tap once to start the audio. Works on desktop and in mobile Safari (landscape).

**In Xogot (iPhone / iPad):**
1. Get the project folder onto the device: on GitHub use **Code ▸ Download ZIP** (or AirDrop the zip),
   then tap it in the Files app to unzip.
2. Move the unzipped `turnbuckle-thunder` folder (the one with `project.godot`) into
   **Files ▸ On My iPhone ▸ Xogot** (On My iPad on an iPad).
3. In Xogot, open it from the **On My iPhone** tab and press **Play**. Hold the device in landscape.

It also runs in desktop Godot 4.4+ (mouse clicks act as touches). Tap **?** in-game for the move list.

## Controls
| Action | Touch | Keyboard |
|---|---|---|
| Move / aim whips, dives and string enders | Left-side joystick (touch anywhere on the left) | WASD / arrows |
| Strike · strike strings · swing a weapon · air SPIN | PUNCH (red) | J or Z |
| Grab: tap = lock-up, hold = strong lock-up · chain links · items / tables · air FLIP | GRAB | K or X |
| Run / stop · double-tap: **dodge roll** · Irish whip in a lock-up · climb a perch | RUN | L or C |
| Pin a downed opponent / taunt · throw the held item · air POSE | PIN / TAUNT | Space or V |
| Rematch | REMATCH button | R / Enter |

The buttons relabel themselves for the situation (KNEE / SLAM in a lock-up, JAB → HOOK → UPPERCUT during
a string, KNEE / CATCH / LARIAT on a launched opponent, CHAIN! late in a slam, CLIMB next to a perch,
SPRING / SLING right after a fence rebound, SPIN / FLIP / POSE in the air, PICK UP / SWING / THROW for
weapons, ON TABLE / SMASH! for tables, REVERSE! when a counter is possible), and a hint bar at the
bottom says what each button does right now.

## Moves
**Movement.** Runs build momentum (about a second to "Full Steam"); hard turns bleed speed. Running into
the fence or the house wall rebounds you (with a speed boost). **Double-tap RUN to dodge-roll** toward
the stick (no stick: away from him); rolling through an attack is a "Close Shave!".

**Strike strings.** Press STRIKE again as each hit lands: **Jab → Hook → Uppercut → Porch Light
Haymaker!** The stick (relative to the opponent) picks the ender: toward = **Lawn Dart Spin Kick!**
(3rd hit) or **Screen Door Superkick!** (4th hit); away = **Bottle Rocket Launcher!** (2nd hit on), which
pops him into the air. On a launched opponent: STRIKE = **Air Mail Knee!** (re-pops him, twice per
launch), GRAB = **CATCH & SLAM!**, RUN = **EXPRESS LARIAT!!**. GRAB mid-string locks up the staggered
opponent. Enders are slow and can be reversed. RUN, then STRIKE: running **Clothesline**.

**Lock-ups.** GRAB close to the opponent. A tap gives a lock-up; holding GRAB (about 0.3 s) gives a
strong one, slower to start and whiffs harder. "STICK+" means hold a direction while pressing.

| Input | Tap GRAB | Hold GRAB |
|---|---|---|
| STRIKE | Knee Lift | THUNDER TOMBSTONE! |
| STICK+STRIKE | Suplex! | Storm Powerbomb! |
| GRAB | Body Slam | Spinebuster! |
| STICK+GRAB | DDT! | Swinging Neckbreaker! |
| RUN (stick aims) | Irish Whip | Irish Whip |
| STICK+GRAB with SPECIAL | **THUNDER DRIVER!!** | **THUNDER DRIVER!!** |

**Grapple chains.** Press GRAB (or STRIKE) late in a slam and you haul him straight back up into the
next move, up to three moves in all, each scoring more:
Body Slam → **Back-to-Back Slam!** → **SLAM-BAM POWERBOMB!!** · Suplex → **Double-Down Suplex!** →
**TRIPLE THREAT SUPLEX!!!** · DDT → **Double-Tap DDT!** → **Neckbreaker Encore!!** (Spinebuster,
Powerbomb, Back Body Drop, Powerslam and Catch & Slam chain too). STRIKE instead finishes with
**...and the ELBOW!** or **...and a STOMP!**. Reversals chain into offence (Arm Drag → Double-Tap DDT,
Hip Toss → Back-to-Back Slam). The victim can break each link with a timed reversal ("CHAIN BROKEN!").

**Irish whip follow-ups** (as he rebounds off the fence toward you): STRIKE: Clothesline · GRAB: Back
Body Drop · STICK+GRAB: Running Powerslam. Whip him diagonally and he slams into the fence and slumps
there: RUN, then STRIKE splashes him against it (**Corner Splash!**); GRAB up close: **SUPER DROP!!**.

**Opponent on the ground.** STRIKE (close): Stomp. GRAB (close): pick him up (your next lock-up can't be
reversed). RUN, then STRIKE: **Flying Elbow Drop!**; RUN, then GRAB: **Running Knee Drop!** (a miss
hurts you).

**Reversals.** When the opponent commits to a lock-up move, an Irish whip, a string ender or a running
clothesline, **REVERSE!** flashes: press GRAB or STRIKE right then for an **Arm Drag**, **Hip Toss** or
**Back Body Drop**. Mashing just before the window locks you out for half a second.

**Pins.** PIN next to a downed opponent; a 3-count wins. Kicking out is harder when you're hurt and
after big moves. When pinned, **mash any button** to kick out.

**Yard high-flying.** The perches: **picnic table** (0.75 m), **car hood** (0.95 m), **porch steps**
(1 m), **pallet stack** (1.2 m), **trampoline** (0.9 m, launches extra high) and the **shed roof**
(2.4 m, the biggest dive). Higher = more hang time and more points.
- RUN next to a perch: climb it. On top: STRIKE dives, GRAB hops down, RUN climbs down. A strike while
  you're climbing or perched knocks you off.
- Foe down (the stick picks the dive): toward / none: **BACKYARD SPLASH!**; away: **MOONSAULT!**;
  sideways: **Flying Elbow off the top!**; with SPECIAL: **GUTTER STAR PRESS!!!**.
- Foe standing: STRIKE: **Flying Crossbody!**; STICK+STRIKE: **Missile Dropkick!**. Miss and you crash.
- Fence launches: run into the fence / wall and press within 0.45 s of the rebound: STRIKE =
  springboard (**Springboard Forearm!**, **SPRINGBOARD MOONSAULT!**, **Springboard Splash!** on a downed
  foe), GRAB = slingshot (**Slingshot Crossbody!**, **SLINGSHOT SENTON!**).
- **Air tricks** while airborne: STRIKE = SPIN (180° each, stack them), GRAB = FLIP (360°, double,
  triple...; stick up = front flip), PIN = POSE (Spread Eagle, Porch Light, Lawn Chair, Air Guitar,
  Kiddie Pool Cannonball, by stick). Finish before you land ("NAILED IT!") or it's a botch.

**Weapons & tables.** A steel chair, a trash can and a 2x4 lie around the yard, plus a folding table.
- GRAB next to an item: pick it up. Holding it: STRIKE swings (ground shot on a downed foe), RUN then
  STRIKE: running swing, PIN throws it, GRAB drops it. Getting hit makes you drop it; items break.
- GRAB by the folded table: set it up. GRAB a downed foe near it: lay him on it. STRIKE (or RUN, then
  STRIKE): **THROUGH THE TABLE!** Slams, throws and dives next to a standing table go through it too.

**Style: combos, B-R-A-W-L, BRAWL MODE.** Every move and trick scores style points. Tricks less than
2.5 s apart chain into a combo (multiplier up to x8); a pause banks it, getting hit or whiffing breaks
it. Repeating the same move in one combo scores less. Style points fill the hype / spirit meter; each
time it fills you earn a letter of **B-R-A-W-L**. All five letters = **BRAWL MODE** for 12 s: every move
becomes its SUPER version (SKYSCRAPER SLAM!!, STRATOSPHERE SUPLEX!!, SUPERNOVA HAYMAKER!!, HARVEST
MOONSAULT!! ...), double points, harder hits, and SPECIAL is always lit. A full spirit meter otherwise
lights **SPECIAL** for 15 s: STICK+GRAB in a lock-up is the **THUNDER DRIVER!!**. TAUNT builds spirit
(6 s cooldown).

## Code map
- `scripts/main.gd`: the backyard (lawn, patio, house, fence, perches: `yard_bounds`, `perches`,
  `surface_at()`), floodlights and the low-res PS2-era view, crowd, camera, HUD (name plates, hints,
  context button labels, HOW TO PLAY panel), match flow, input
- `scripts/wrestler.gd`: wrestler body, state machine, move list (`MOVES`, `STRIKES`, `CHAINS`),
  strike strings and grapple chains, reversals, pins, weapons and tables, yard high-flying (perch
  climbs, dives, fence launches, air tricks), movement and dodge roll, CPU AI, procedural animation
- `scripts/style.gd`: style scoring per wrestler (combos, hype, B-R-A-W-L letters, BRAWL MODE)
- `scripts/style_hud.gd`: style overlay (letters, combo counter, trick popups, BRAWL MODE banner)
- `scripts/weapons.gd`: the item manager: chairs, trash can, 2x4, folding table (pick up, drop, throw,
  set up, break into splinters)
- `scripts/touch_controls.gd`: on-screen joystick and context-labelled buttons
- `scripts/audio.gd`: procedurally synthesized sound effects and crowd ambience (no audio assets)
- `scripts/fx.gd`: pooled hit sparks, dust puffs, table splinters and debris, screen flash
- `tools/preview.sh` + `tools/shoot.js`: screenshot a web build (local dir or URL) with headless
  Chromium / Playwright
- `.github/workflows`: builds the web version on every branch, checks for script errors, publishes
  `main` to GitHub Pages

## Roadmap
More weapons (ladders, cookie sheets, kiddie pool, garden hose); a front-yard / driveway / garage
arena; character select and create-a-wrestler; tag team and hardcore "anything goes" rules;
submissions and front/back grapple variations; career mode across City 2 City backyards; music.
