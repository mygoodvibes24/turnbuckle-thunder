# City 2 City Wrestling — Backyard Brawl

A 3D hardcore **backyard** wrestling game in the spirit of late-90s / early-2000s console brawlers, built
for **Xogot** (Godot 4 on iPad / iPhone). A homemade ring in a suburban backyard at night, string lights,
the neighbors' kids watching from lawn chairs, and two friends in street clothes beating each other with
steel chairs, trash cans and 2x4s, putting each other through folding tables and diving off the
turnbuckles. Comedic-hardcore, PG-13: no blood, just bad decisions.

**TANK MAGRUDER** (you) vs. **LIL PELIGRO** (CPU), first pin wins.

Everything (yard, ring, crowd, wrestlers, weapons, animations, HUD, sound) is generated in GDScript, so
there are no assets to import.

## Open it in Xogot
**On iPhone / iPad (Files app):**
1. Get the project folder onto the device (e.g. AirDrop the zip, then tap it in Files to unzip).
2. Move the unzipped `turnbuckle-thunder` folder (the one with `project.godot`) into
   **Files ▸ On My iPhone ▸ Xogot** (On My iPad on an iPad).
3. In Xogot, open it from the **On My iPhone** tab and press **Play**. Hold the device in landscape.

**From GitHub (if the repo is public):** use **Code ▸ Download ZIP**, unzip it in Files, and move the
folder into the Xogot folder as above.

It also runs in desktop Godot 4.4+ (mouse clicks act as touches). Tap **?** in-game for the move list.

## Controls
| Action | Touch | Keyboard |
|---|---|---|
| Move / aim moves and dives | Left-side joystick (touch anywhere on the left) | WASD / arrows |
| Strike · swing a weapon | PUNCH (red) | J or Z |
| Grab: tap = weak lock-up, hold = strong · pick up / drop items · tables | GRAB | K or X |
| Run / stop · Irish whip in a lock-up · climb a corner | RUN | L or C |
| Pin a downed opponent / Taunt · throw the held item | PIN / TAUNT | Space or V |
| Rematch | REMATCH button | R / Enter |

The buttons relabel themselves for the current situation (KNEE / SLAM in a lock-up, PICK UP next to a
chair, SWING / DROP / THROW while holding one, ON TABLE and SMASH! for table spots, CLIMB next to a corner,
DIVE! on the top turnbuckle, REVERSE! when a counter is possible), and a hint bar at the bottom shows what
each button does right now.

## Moves
**Strikes.** PUNCH stuns; three in a row is a knockdown. RUN, then STRIKE: running Clothesline.

**Lock-ups.** GRAB close to the opponent. A quick tap gives a weak lock-up; holding GRAB (about 0.3 s)
gives a strong one, which is slower to start and whiffs harder if you miss. "STICK+" means hold a
direction while pressing.

| Input | Weak (tap GRAB) | Strong (hold GRAB) |
|---|---|---|
| STRIKE | Knee Lift | Thunder Tombstone |
| STICK+STRIKE | Suplex | Storm Powerbomb |
| GRAB | Body Slam | Spinebuster |
| STICK+GRAB | DDT | Swinging Neckbreaker |
| RUN (stick aims) | Irish Whip | Irish Whip |
| STICK+GRAB with SPECIAL | **THUNDER DRIVER!!** | **THUNDER DRIVER!!** |

**Irish whip follow-ups** (press as the opponent rebounds off the ropes toward you; too early whiffs):
STRIKE: Clothesline · GRAB: Back Body Drop · STICK+GRAB: Running Powerslam. If you do nothing, you collide.

**Opponent on the mat.**
- STRIKE (close): Stomp.
- GRAB (close): pick him up. He is dazed, so your next lock-up on him can't be reversed.
- RUN, then STRIKE: Flying Elbow Drop. RUN, then GRAB: Running Knee Drop. Either way you land on the mat
  for a moment, and a miss hurts you.

**Reversals.** When the opponent commits to a lock-up move, an Irish whip, a punch or a running
clothesline, **REVERSE!** flashes: press GRAB or STRIKE right then. You'll counter with an Arm Drag, a
Hip Toss (vs. strong grapples), a Back Body Drop (vs. the running clothesline), or by whipping him
instead. Pressing during a lock-up before he commits, or mashing just before the window, locks you out of
reversing for half a second.

**Pins.** PIN next to a downed opponent to cover; a 3-count wins. Kicking out is harder when you're hurt,
harder after strong moves and much harder after a finisher. When pinned, **mash any button** to kick out.
A kick-out after two is a near fall and gives the kicker some spirit.

**Spirit / SPECIAL.** The yellow spirit meter fills when you deal damage, taunt, or survive a near fall,
and drops a little when you get hit. TAUNT (PIN when the opponent isn't down next to you) builds spirit,
more while he's down, but has a 6 s cooldown and is cut short if you get hit. A full meter lights
**SPECIAL** for 15 seconds: in any lock-up, STICK+GRAB is the **THUNDER DRIVER!!**. Unused, the meter
drains back to 80%.

**Weapons.** A steel chair, a trash can and a 2x4 lie around the ring.
- GRAB next to an item (when the opponent isn't standing in grab range): pick it up.
- Holding it: STRIKE swings it (a ground shot if he's down or on a table); RUN, then STRIKE: running swing;
  PIN throws it at him (hits if he's standing in front of you, within about 6 m; if he's down right next to
  you, PIN drops it and covers instead); GRAB drops it.
- Getting hit or grappled makes you drop it. Items wear out and break.

**Tables.** A folding table leans against a corner post.
- GRAB next to the folded table: set it up in front of you.
- GRAB next to a downed opponent near the standing table: drag him onto it.
- STRIKE next to an opponent lying on the table (or RUN, then STRIKE): leap onto him, **THROUGH THE TABLE!**
- Any slam or throw that lands next to a standing table also goes through it, and so does a dive off the
  top onto someone lying on one.

**High flying.**
- RUN toward a corner post when you're next to it: climb to the top turnbuckle.
- On top: STRIKE dives, GRAB hops down to the mat, RUN climbs back down. A strike while you're climbing or
  perched knocks you off the top (sometimes right onto the turnbuckle).
- Dives at a downed opponent (the stick picks the dive): no stick or stick toward him: **Backyard Splash**;
  stick away: **Moonsault**; stick sideways: **Flying Elbow off the top**; with SPECIAL lit:
  **GUTTER STAR PRESS!!!**
- Dives at a standing opponent: STRIKE: **Flying Crossbody**; STICK+STRIKE: **Missile Dropkick**.
  Miss (or fly too far) and it's you who crashes.
- Springboards: STRIKE right after you bounce off the ropes while running: **Springboard Forearm**, or a
  **Springboard Moonsault** onto a standing opponent a few steps away.
- Corner spots: Irish-whip him into a corner (aim the whip diagonally) and he slumps in the turnbuckle.
  Then RUN, then STRIKE: **Corner Splash**; or GRAB him up close: **SUPER DROP!!** off the top.

## Code map
- `scripts/main.gd`: backyard and ring, crowd, camera, HUD (bars, hints, context button labels, HOW TO
  PLAY panel), match flow, input
- `scripts/wrestler.gd`: wrestler body, state machine, move list (`MOVES`), reversals, pins, weapons and
  table logic, high flying (climbs, dives, springboards, corner spots), CPU AI, procedural animation
- `scripts/weapons.gd`: the item manager: chairs, trash can, 2x4, folding table (pick up, drop, throw,
  set up, break into splinters)
- `scripts/touch_controls.gd`: on-screen joystick and context-labelled buttons
- `scripts/audio.gd`: procedurally synthesized sound effects and crowd ambience (no audio assets)
- `scripts/fx.gd`: pooled hit sparks, dust puffs, table splinters and debris, screen flash

## Not done yet (ideas for next steps)
Out-of-ring brawling in the yard; more weapons (ladders, cookie sheets, trampoline spots); character
select; create-a-wrestler; tag and hardcore matches; front/back grapple variations, submissions, music.
