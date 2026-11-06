# Turnbuckle Thunder (prototype)

A 3D grappling-style pro wrestling prototype in the spirit of late-90s console
wrestling games, built for **Xogot** (Godot 4 on iPad / iPhone). Everything
(ring, crowd, wrestlers, animations, HUD, sound) is generated in GDScript, so there
are no assets to import.

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
| Move / aim moves | Left-side joystick (touch anywhere on the left) | WASD / arrows |
| Strike | PUNCH (red) | J or Z |
| Grab: tap = weak lock-up, hold = strong lock-up | GRAB | K or X |
| Run / stop · Irish whip in a lock-up | RUN | L or C |
| Pin a downed opponent / Taunt | PIN / TAUNT | Space or V |
| Rematch | REMATCH button | R / Enter |

The buttons relabel themselves for the current situation (e.g. KNEE / SLAM in a lock-up, REVERSE! when a
counter is possible), and a hint bar at the bottom shows what each button does right now.

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

## Code map
- `scripts/main.gd`: arena, crowd, camera, HUD (bars, hints, HOW TO PLAY panel), match flow, input
- `scripts/wrestler.gd`: wrestler body, state machine, move list (`MOVES`), reversals, pins, CPU AI,
  procedural animation
- `scripts/touch_controls.gd`: on-screen joystick and context-labelled buttons
- `scripts/audio.gd`: procedurally synthesized sound effects and crowd ambience (no audio assets)
- `scripts/fx.gd`: pooled hit sparks, mat dust puffs and screen flash

## Not done yet (ideas for next steps)
Out-of-ring action, turnbuckle / top-rope moves, front/back grapple variations, submissions, more
wrestlers and character select, tag matches, music, real models and animations.
