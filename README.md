# leslie

![leslie running on norns](https://raw.githubusercontent.com/moapacha/leslie/main/docs/screen.gif)

A norns rotating-speaker effect modeled on the dual-rotor Leslie cabinet. Stereo input is split at a Linkwitz–Riley crossover into a horn band (high) and a bass-drum band (low). Each band is run through a doppler delay, an AM tremolo, and a stereo pan, all driven by counter-rotating LFOs. Slow / fast / brake modes follow the classic Leslie 122 — speed transitions are smoothed so rotors visibly and audibly spin up or coast to a stop.

## Requirements

- norns or norns shield
- a stereo (or mono) source patched into the audio inputs

## Controls

| Input | Function |
| --- | --- |
| E1 | input drive (0.25–4.00, soft saturate above 1.0) |
| E2 | throb — AM depth (0.00–1.00, both rotors linked, bass at 0.8×) |
| E3 | stereo width (0.00–1.00) |
| K2 | toggle slow / fast (chorale ↔ tremolo) |
| K3 | brake — smooth spin-down to 0; press again to release |
| K1 (hold) | edit mode for fine-tuning the deeper params |

While K1 is held the right column lights up and the encoders re-route:

| Input | Function |
| --- | --- |
| K1 + E1 | doppler depth, both rotors (0–5 ms; bass scales 2× automatically) |
| K1 + E2 | rotation rate of the currently selected mode (0.01 Hz steps) |
| K1 + E3 | crossover frequency (200–2000 Hz, 1 Hz steps) |

Every value on screen is also exposed in the `PARAMS` menu under `leslie`, where horn and bass parameters can be set independently and the accel times tweaked.

## OLED layout

| Region | Content |
| --- | --- |
| Left (x 4–40) | cabinet — vent slats, horn rotor (bowtie of two flared bells), bass drum, legs |
| Title row | `~leslie~`, with a `*` badge at the top-right corner while K1 is held |
| Mode row | `slow` / `fast` / `brake` — current mode at level 15, others dim |
| Param rows | left column = normal-mode params (`drive`, `throb`, `width`); right column = edit-mode params (`dop`, `spd`, `xov`). The active set is bright, the other dim, so all six values are visible at once. |
| Tach | `h` and `b` show the *target* rate of the current mode so the display reflects mode changes instantly. The on-screen rotors lerp toward that target with a per-rotor accel time, mirroring the engine's `Lag.kr`. |

The horn flare width modulates with `abs(cos(angle))` so the bowtie thins to a line when end-on and opens back up when broadside, suggesting a vertical-axis rotation.

## Signal chain

A single `\leslie` SynthDef in `lib/Engine_Leslie.sc`:

| Stage | What it does |
| --- | --- |
| input | sum stereo to mono, multiply by `drive`, soft `tanh` saturate |
| crossover | LR4 (cascaded LPF / HPF) at `xfreq` — sums flat, no magnitude dip at the split |
| rate smoothing | `Lag.kr(hornRate, hornAccel)` and the bass equivalent. `brake` is multiplied in after the lag, so engaging brake decelerates smoothly from whatever the current rate is and releasing it accelerates back. |
| LFOs | `SinOsc.kr(hornCur)` for the horn, `SinOsc.kr(-bassCur)` for the bass — counter-rotating |
| doppler | each band fed through `DelayC.ar` with delay time `(lfo × dopp) + offset`. The varying delay produces the swirling pitch shift. |
| AM | each band amplitude-modulated by its own LFO at `1 − depth/2 ± depth/2`, so depth=1 swings between near-zero and full amplitude |
| pan | each band panned by its own LFO scaled by `width`. Because the bass LFO counter-rotates, the two bands sweep in opposite directions at independent rates. |
| mix | wet / dry crossfade |

Defaults track the Leslie 122: chorale 0.8 Hz horn / 0.7 Hz bass, tremolo 6.8 Hz horn / 5.6 Hz bass, crossover 800 Hz, horn accel 0.5 s, bass accel 1.2 s.

## Install

From maiden:

```
;install https://github.com/moapacha/leslie
```

Or clone into `~/dust/code/leslie/` directly. The first load will compile the SuperCollider engine; if the engine does not appear, run `;restart` in maiden to rebuild the class library.

## Credits

The signal chain follows the architecture of mda Leslie (Paul Kellett, GPL), translated to SuperCollider for norns Crone. Defaults reference the Leslie 122 cabinet.

---

Hope you enjoy this script. Suggestions and contributions are welcome.
