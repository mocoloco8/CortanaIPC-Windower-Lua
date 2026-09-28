# Cortana Windower Addon

Cortana is a **Windower addon for Final Fantasy XI** designed to provide direct communication between Windower and the Cortana desktop application.

The project removes the need for additional middleware such as EliteAPI / EliteMMO and instead communicates directly with the running Windower client.

```text
Previous Architecture

Cortana
   ↓
EliteAPI / EliteMMO
   ↓
Windower
   ↓
Final Fantasy XI


Current Architecture

Cortana
   ↓
Windower
   ↓
Final Fantasy XI
```

The goal is to reduce unnecessary dependencies, simplify communication, and make Cortana easier to maintain when Final Fantasy XI receives updates.

---

## Requirements

- Final Fantasy XI
- Windower 4
- Cortana desktop application

---

## Installation

1. Download the latest `cortana.zip` release.

2. Extract the `cortana` folder into your Windower addons directory:

```text
Windower/
└── addons/
    └── cortana/
        ├── cortana.lua
        ├── buffs.lua
        ├── combat.lua
        ├── comm.lua
        ├── control.lua
        ├── hud.lua
        ├── inventory.lua
        ├── jobchange.lua
        ├── keys.lua
        ├── npc.lua
        ├── state.lua
        ├── targeting.lua
        ├── treasure.lua
        ├── widescan.lua
        └── dialog.png
```

3. Start Final Fantasy XI through Windower.

4. Load the addon from the Windower console:

```text
lua load cortana
```

5. Launch the Cortana desktop application normally.

Once both applications are running, Cortana will automatically look for the local Windower addon and establish communication.

---

## Local Communication

The addon communicates with the Cortana application using local UDP communication on:

```text
127.0.0.1:59332-59341
```

`127.0.0.1` is the local loopback interface, so communication is intended to remain on the same computer.

You can check the connection from Windower with:

```text
//cortana status
```

When connected, the addon will display the linked application and local communication port.

---

## Features

The addon provides the communication layer needed by Cortana to interact directly with Windower.

Current functionality includes:

- Player state monitoring
- Party information
- Target and entity tracking
- Combat and action monitoring
- Spell and ability information
- Buff and debuff tracking
- Inventory information
- Equipment information
- Pet information
- Recast information
- Follow controls
- Target selection
- Melee and auto-attack controls
- Weapon skill commands
- Magic commands
- Disengage controls
- Job changing
- Keyboard input
- NPC interaction
- NPC selling support
- Treasure pool lot/pass commands
- Widescan information
- HUD messages and notifications
- Team/profile commands
- Quick Commands

---

## Commands

### Connection Status

```text
//cortana status
```

Displays whether the addon is currently connected to the Cortana application.

---

### Inventory

```text
//cortana inv
```

or

```text
//cortana inventory
```

Displays/sends current inventory information.

---

### HUD

```text
//cortana hud
```

Controls the Cortana Windower HUD.

---

### Debug Mode

```text
//cortana debug
```

Toggles debug output.

---

### Job Change

```text
//cortana job <MAIN>[/<SUB>] [character]
```

Example:

```text
//cortana job WHM/RDM
```

Change only the subjob:

```text
//cortana job /RDM
```

When supported by the connected Cortana application, a character name may also be supplied.

---

### Follow

```text
//cortana follow
```

Follow functionality can be controlled through Cortana.

---

### Weapon Skills

Toggle weapon skill automation:

```text
//cortana ws on
//cortana ws off
```

Request a specific weapon skill:

```text
//cortana ws "Savage Blade"
```

---

### Magic

```text
//cortana magic on
//cortana magic off
```

---

### Auto Attack

```text
//cortana autoattack on
//cortana autoattack off
```

Alias:

```text
//cortana aa on
//cortana aa off
```

---

### Melee

```text
//cortana melee on
//cortana melee off
```

---

### Disengage

```text
//cortana disengage
```

---

### Quick Commands

```text
//cortana qc "<name>"
```

Example:

```text
//cortana qc "Farm"
```

---

### Team Profiles

```text
//cortana profile "<team setup name>"
```

Example:

```text
//cortana profile "Dynamis"
```

---

### HUD Message

```text
//cortana verbose "<message>"
```

Use `~` to insert a line break in supported messages.

---

## Loading Automatically

To automatically load Cortana whenever Windower starts, add the following to your Windower startup configuration:

```text
lua load cortana
```

Otherwise, load it manually after entering the game.

---

## Updating

When installing a newer release:

1. Unload the existing addon:

```text
lua unload cortana
```

2. Replace the existing `cortana` addon folder with the version from the new release.

3. Reload it:

```text
lua load cortana
```

4. Restart the Cortana desktop application if necessary.

---

## Project Goals

Cortana's Windower integration is intended to keep the communication path as simple as possible:

```text
Cortana → Windower → Final Fantasy XI
```

Reducing intermediary libraries provides a smaller dependency chain and keeps the integration centered around Windower's addon environment.

---

## Disclaimer

This is an independent community project and is not affiliated with, endorsed by, or associated with Square Enix.

FINAL FANTASY XI and related trademarks are property of Square Enix Holdings Co., Ltd.

Use third-party tools and addons at your own discretion and in accordance with the applicable game terms and policies.

---

## Version

Current Windower addon version:

```text
1.0.0
```
