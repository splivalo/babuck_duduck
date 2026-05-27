```text
You are helping build a mobile preschool interactive character app in Flutter (NOT Flame).

The app is inspired by simple interactive character toys like Talking Tom, but MUCH simpler and focused on:
- expressive animated characters
- tap reactions
- room atmosphere
- lightweight state system
- prerendered sprite animations (PNG sequences)

IMPORTANT:
This is NOT a physics game.
This is NOT a platformer.
This is NOT a Flame engine game.
This is a standard Flutter app with layered animated UI and touch interaction.

====================================================
PROJECT OVERVIEW
====================================================

The app contains:

- 2 selectable characters:
  - Babak
  - Dudak

Only ONE character is visible at a time.

The character is displayed centered in the scene.

The app contains 4 room backgrounds:

1. bedroom_day
2. bedroom_night
3. wardrobe_room
4. table_room
5. rocket_room

IMPORTANT:
bedroom_day and bedroom_night are actually the SAME room.
The difference is only:
- lighting
- atmosphere
- background image swap

The bedroom contains a lamp baked directly into the background image.
The lamp is NOT a separate PNG.

Touching the lamp area should:
- toggle between bedroom_day and bedroom_night backgrounds
- keep the same character and current app state

====================================================
TECH STACK
====================================================

Use:
- Flutter
- Dart
- VSCode compatible architecture

Do NOT use:
- Flame
- Unity
- Spine runtime
- Rive
- physics engine

Character animations are prerendered PNG frame sequences exported from DaVinci Resolve with transparent backgrounds.

====================================================
ANIMATION SYSTEM
====================================================

Animations are frame-by-frame PNG sequences.

Examples:
- idle_blink
- idle_sway
- laugh
- talk
- reaction_head
- reaction_belly
- reaction_legs

Animation playback should:
- support looping
- support one-shot playback
- support interrupting idle animations
- support returning to idle automatically

The app should have an Animation Manager / Character State system.

====================================================
IDLE SYSTEM
====================================================

The character should feel alive.

Idle behavior logic:

- randomly play idle_blink 2-3 times
- sometimes switch to idle_sway
- repeat forever

Avoid robotic looping.

Use randomized idle timing.

Pseudo logic:

idle loop:
70% chance:
    idle_blink
30% chance:
    idle_sway

Wait random durations between idle animations.

====================================================
REACTION SYSTEM
====================================================

The character has 3 invisible touch zones:

1. HEAD
2. BELLY
3. LEGS

Touching a body zone:
- interrupts current idle animation
- plays corresponding reaction animation
- plays sound effect
- returns to idle loop

Example:
BELLY tap:
- laugh animation
- goofy sound

HEAD tap:
- surprised / angry reaction

LEGS tap:
- silly reaction

IMPORTANT:
Only one reaction should play at a time.

Ignore additional taps during active reaction playback OR queue minimally.

The app must feel responsive and instant.

====================================================
ROOM SYSTEM
====================================================

Bottom navigation buttons switch rooms instantly.

Bottom bar contains:

- Bedroom
- Wardrobe
- Table
- Rocket

Switching rooms:
- swaps background image
- keeps selected character
- keeps animation system alive

Bedroom room has special behavior:
touching the lamp hotspot toggles:
- bedroom_day
- bedroom_night

No other room has day/night behavior.

====================================================
SCREEN STRUCTURE
====================================================

App flow:

SplashScreen
    ↓
CharacterSelectScreen
    ↓
MainRoomScreen

====================================================
SPLASH SCREEN
====================================================

Simple loading splash only:
- Babak & Dudak logo/title
- lightweight loading feel

No heavy logic required.

====================================================
CHARACTER SELECT SCREEN
====================================================

Simple selection:
- choose Babak
- choose Dudak

Selected character persists across room switches.

====================================================
MAIN ROOM SCREEN
====================================================

Main room screen layers:

Stack(
    background,
    character animation,
    invisible touch zones,
    room navigation buttons,
)

Character should remain visually centered.

====================================================
ASSET ORGANIZATION
====================================================

Use VERY CLEAN asset structure.

Example:

assets/
│
├── backgrounds/
│   ├── bedroom_day.jpg
│   ├── bedroom_night.jpg
│   ├── wardrobe_room.jpg
│   ├── table_room.jpg
│   └── rocket_room.jpg
│
├── characters/
│   ├── babak/
│   │   ├── idle_blink/
│   │   │   ├── 0001.png
│   │   │   ├── 0002.png
│   │   │   └── ...
│   │   │
│   │   ├── idle_sway/
│   │   ├── laugh/
│   │   ├── talk/
│   │   ├── reaction_head/
│   │   ├── reaction_belly/
│   │   └── reaction_legs/
│   │
│   └── dudak/
│       ├── idle_blink/
│       ├── idle_sway/
│       ├── laugh/
│       ├── talk/
│       ├── reaction_head/
│       ├── reaction_belly/
│       └── reaction_legs/
│
├── sounds/
│   ├── laugh/
│   ├── belly/
│   ├── head/
│   ├── legs/
│   └── ui/
│
└── ui/

====================================================
IMPORTANT PNG EXPORT RULES
====================================================

All PNG frame exports should:
- use transparent background
- maintain EXACT SAME canvas size
- maintain EXACT SAME character position
- use sequential numbering:
    0001.png
    0002.png
    0003.png

VERY IMPORTANT:
Every animation sequence MUST:
- use identical dimensions
- use identical alignment
- use identical pivot positioning

Otherwise playback will visually jump.

====================================================
SPRITE PLAYBACK REQUIREMENTS
====================================================

Build reusable sprite sequence player.

Requirements:
- preload frames
- support FPS control
- support loop mode
- support play once mode
- callback on animation complete
- smooth transitions

Should work similarly to:
SpriteSequencePlayer(
    frames: [],
    fps: 12,
    loop: true,
)

====================================================
PERFORMANCE REQUIREMENTS
====================================================

IMPORTANT:
Do NOT preload every animation in the entire app at startup.

Instead:
- preload only active room assets
- preload current character animations
- lazy load others

Avoid memory spikes.

Use image caching carefully.

Target:
- smooth mobile performance
- low RAM usage
- instant tap reactions

====================================================
CODE ARCHITECTURE
====================================================

Create clean architecture with:

- RoomManager
- CharacterManager
- AnimationController system
- AssetLoader
- SoundManager
- TouchZoneManager

Avoid giant monolithic widgets.

====================================================
UI STYLE
====================================================

The app should feel:
- playful
- expressive
- responsive
- preschool friendly

Avoid:
- cluttered UI
- tiny buttons
- complex menus

====================================================
DEVELOPMENT PRIORITY
====================================================

FIRST milestone ONLY:

1. Splash screen
2. Character select
3. One working room
4. One character
5. idle_blink
6. idle_sway
7. belly tap reaction
8. room switching
9. bedroom day/night lamp toggle

Do NOT overbuild early.

Focus on:
- animation feel
- responsiveness
- smooth playback
- believable character behavior

====================================================
OUTPUT REQUEST
====================================================

Generate:
- Flutter project structure
- recommended packages
- clean architecture
- reusable sprite animation player
- room system
- touch zone system
- preload strategy
- animation state flow
- scalable code organization

Use production-quality Flutter architecture and clean readable Dart code.
```
