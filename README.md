# FS22_TrailerLock

A Farming Simulator 22 mod that **locks the joints of double trailers** so they stay straight. You can finally reverse with a dolly, a turntable drawbar trailer or a trailer train.

## Features

- One key (**ALT + L**) locks or unlocks the whole trailer chain behind your vehicle
- Only the side-to-side turning is locked, so trailers still follow bumps and slopes
- The hitch on your tractor always stays free, so you steer the train from there
- A "Trailer lock: ON" text shows on screen while it's locked
- A trailer you unhook unlocks automatically
- Works in multiplayer (the server applies the lock)

## What gets locked

| Setup | Locked | Stays free |
|---|---|---|
| Tractor + turntable drawbar trailer | Turntable (front axle) | Drawbar on the tractor hitch |
| Tractor + dolly + semi-trailer | Dolly → semi-trailer | Tractor → dolly |
| Tractor + trailer + trailer | Trailer → trailer, plus any turntables | Tractor → first trailer |

## Installation

1. Download `FS22_TrailerLock.zip` from the [Releases](../../releases) page.
2. Put the zip in `Documents\My Games\FarmingSimulator2022\mods`. Don't unzip it.
3. Turn on **Trailer Lock** when you load your savegame.

## Usage

| Input | Action |
|---|---|
| ALT + L (in a vehicle) | Lock / unlock trailer joints |
| `tlToggle` (developer console) | Same as ALT + L |

You can change the key in the game's controls menu.

## Reporting problems

If something doesn't work, open `Documents\My Games\FarmingSimulator2022\log.txt`, search for `[TrailerLock]`, and open an issue with those lines and the trailers you were using.

## Files

- `modDesc.xml`: mod description and key binding
- `scripts/TrailerLock.lua`: lock / unlock logic, hotkey and on-screen text
- `scripts/TrailerLockEvent.lua`: multiplayer event

## Credits

Made by Timo. The turntable detection uses the same approach as [AutoDrive for FS22](https://github.com/Stephan-S/FS22_AutoDrive).
