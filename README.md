[README.md](https://github.com/user-attachments/files/30730140/README.md)
# node7-makeup











<img width="1671" height="998" alt="makeupeditor" src="https://github.com/user-attachments/assets/b717acab-65f0-4868-ad36-5b277472f88e" />



Standalone Node7 barber-chair editor for native facial customization.

## Included

- Direct native DrawText interaction at the configured barber chairs
- K input only; no commands, fallback commands, key mappings, or map blips
- No screen blur or post-processing blur
- Eye colors and eyebrow styles
- Female-only eyeliner, eyeshadow, lipstick, and blush
- Native scars, ageing, freckles, moles, and spots for both sexes
- Reduced native face sculpt controls for brows, eyes, nose, mouth, jaw, chin, and cheeks
- Male-only native beard styles and colors; female characters never receive beard options
- Independent `node7_makeup_profiles` persistence
- Cash and bank payments with save verification and refund-on-failure
- Reload after reconnect, resource restart, server restart, respawn, and ped rebuild

## Requirements

- `node7-core`
- `oxmysql`

## Start order

```cfg
ensure oxmysql
ensure node7-core
ensure node7-barbers
ensure node7-makeup
```

The resource creates its own database table automatically. The included SQL file can also be imported manually.

## Interaction

Stand at a configured barber chair and press K when `[K] Use Makeup Chair` is displayed.

## Ownership rules

The resource only reapplies beard data after a player has actually selected a beard option in this editor. Older makeup rows therefore cannot erase a beard owned by another resource.

## Sex-specific native options

- Male: eyes/brows, 18 native multiplayer beard styles, skin details, sculpt.
- Female: eyes/brows, native makeup, skin details, sculpt.
- Node7 sex mapping is `1 = male`, `2 = female`; the live MetaPed model is authoritative in the chair.

## Functional behavior

- The resource never chooses a replacement head or skin tone.
- Cosmetics and face details are layered over the character's currently equipped native head assets.
- Male sessions expose native eyes/brows, beard, face details, and sculpt controls.
- Female sessions expose native eyes/brows, makeup, face details, and sculpt controls.
- The chair preview is a disposable clone; cancelling cannot leave unpaid changes on the live character.
