# Turnbuckle Thunder (prototype)

A 3D grappling-style pro wrestling prototype in the spirit of late-90s console
wrestling games, built for **Xogot** (Godot 4 on iPad / iPhone). Everything
(ring, crowd, wrestlers, animations, HUD) is generated in GDScript, so there are
no assets to import.

## Open it in Xogot
1. On GitHub, use **Code ▸ Download ZIP** and unzip it in the Files app.
2. In Xogot, open the `turnbuckle-thunder` folder (the one with `project.godot`).
3. Press **Play**. Hold the device in landscape.

It also runs in desktop Godot 4.4+ (mouse clicks act as touches).

## Controls
| Action | Touch | Keyboard |
|---|---|---|
| Move | Left-side joystick (touch anywhere on the left) | WASD / arrows |
| Strike | STRIKE | J or Z |
| Grab | GRAB | K or X |
| Run / stop | RUN | L or C |
| Pin (opponent down) / Taunt | PIN | Space or V |
| Rematch | REMATCH button | R / Enter |

## How a match works
- **Strikes:** punches stun; 3 in a row knock the opponent down. While running, STRIKE = running clothesline.
- **Rope running:** RUN sprints and bounces off the ropes (steer with the stick).
- **Grappling:** GRAB close to the opponent to lock up, then:
  - STRIKE: Knee Lift · Direction + STRIKE: Suplex
  - GRAB: Body Slam · Direction + GRAB: DDT
- **Reversals:** when you get grabbed, tap GRAB/STRIKE for a chance to reverse with an arm drag.
- **Spirit meter** (yellow): fills when you deal damage or taunt. When it flashes you have a
  **SPECIAL** — lock up and press Direction + GRAB for the **Thunder Driver**.
- **Pins:** PIN on a downed opponent. Lower health = harder to kick out. Mash buttons to kick out yourself. 3-count wins.

## Code map
- `scripts/main.gd`: arena, crowd, camera, HUD, match flow
- `scripts/wrestler.gd`: wrestler body, state machine, move list (`MOVES`), CPU AI, procedural animation
- `scripts/touch_controls.gd`: on-screen joystick + buttons

## Not done yet (ideas for next steps)
Out-of-ring action, turnbuckle moves, front/back grapple variations, more wrestlers and
character select, tag matches, sound and music, real models and animations.
