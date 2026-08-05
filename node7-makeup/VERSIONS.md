# 1.6.0

- Removed ClonePed from the chair preview; native eye and eyebrow changes now target the real multiplayer MetaPed.
- Eye-color previews now use the exact Node7 barber component/category sequence and perform the required MetaPed variation commit.
- Eye changes rebuild owned face overlays and restore male facial hair last.
- Chair scenario starts once and the real ped is frozen only after the seated transition; no chair watchdog or repeated scenario restart is used.
- Cancel restores the exact profile that existed when the chair opened.

# 1.5.5

- Fixed eyebrow style arrows changing the saved index without visually replacing the active MetaPed texture.
- Restored the required one-time MetaPed component variation commit after each successful native texture bind.
- The chair scenario is never restarted by eyebrow previews.
- Reapplies the selected male beard after an overlay commit so eyebrow changes do not remove facial hair.

# 1.5.4

- Replaced the failing dynamic head-asset texture builder with the exact native eyebrow texture sequence already proven in node7-barbers.
- Native overlay IDs are used directly, with the working palette, tint, load, finalize, and bind order.
- Removed preview-time MetaPed rebuilding after the texture is bound so the barber-chair task is not interrupted.

# 1.5.3

- Fixed `GET_META_PED_ASSET_GUIDS` result unpacking; the previous code shifted the drawable/albedo/normal/material outputs and always produced a nil base material.
- Restored the correct native overlay-layer arguments: albedo, normal and material texture hashes.
- Uses 255 to disable unused secondary and tertiary tint channels instead of forcing them to palette color zero.
- Removed the post-build texture reset and now applies then reloads the completed native texture override.
- Failed previews roll back to the prior eyebrow selection instead of leaving a broken working profile.

# 1.5.2

- Fixed native eyebrow style preview and persistence application.
- Head-overlay layers now use their native overlay IDs instead of raw texture asset hashes.
- Corrected native texture finalization order before binding to the MetaPed heads category.
- Kept the beard JSON catalog, chair interaction, payments, and UI presentation unchanged.

# 1.5.1

- Replaced the executable shared beard catalog with a validated JSON asset loaded directly on both client and server.
- Fixed `Native beard catalog failed to load` when the shared Lua catalog failed before client startup.
- Includes 24 beard models and 407 native color variants.

## 1.5.0

- Fixed the male native beard catalog not reaching the client.
- Loads `shared/beards.lua` explicitly in both client and server contexts.
- Replaced fragile `ipairs` catalog enumeration with validated indexes 1 through 18.
- No UI, chair, camera, overlay, sculpt, or payment behavior changed.

## 1.4.1 - Native head preservation and stable chair preview

- Face-detail and cosmetic layers now use the active character's current `heads` albedo, normal, and material assets as their base.
- Removed every static male/female head texture fallback that could replace the character's head or skin tone.
- Corrected texture layers to pass native albedo, normal, and material hashes instead of overlay IDs.
- Renamed the former Skin section to Details/Face Details; it contains only scars, ageing, freckles, moles, and spots.
- Preview uses a disposable clone and starts the barber-chair scenario exactly once.
- Removed every preview-time chair clear/restart call.
- Cosmetic and sculpt previews no longer run a full MetaPed variation rebuild on the seated clone.
- Beard payload uses explicit native model and color IDs, preventing the selector from remaining on None because of Lua/JavaScript indexing.

# Versions

## 1.4.0

- Uses the character current native head albedo, normal, and material as the makeup base.
- Stops skin-detail choices from replacing the character head or skin tone.
- Corrects texture-layer arguments to use native overlay albedo/normal/material assets.
- Moves all unpaid previews to a cloned chair ped so MetaPed refreshes cannot make the player stand up.
- Locks sex from the real character/server session; clones never control male/female options.
- Rebuilds beard catalog transport with explicit model and texture IDs.
- Removes the broken one-based Lua/zero-based JavaScript beard indexing.
- Re-seats the preview only when a native refresh actually cancels the scenario; no polling watchdog.
- Renames the Skin tab to Details because it does not alter skin tone.

# 1.3.1

- Beard catalog visibility now comes from an immutable real-ped male session flag.
- Native model checks use `IsPedModel` to avoid signed hash mismatches.
- Male sessions always receive all 18 beard styles and their native colors.
- Removed the chair polling/restart watchdog and all preview-time re-seating.
- Chair behavior now matches the one-shot flow in `node7-barbers`.

# 1.3.0

- Corrected Node7 sex mapping: `1 = male`, `2 = female`.
- Real player MetaPed model is authoritative for chair sex.
- Removed ClonePed preview and now uses the same native barber-chair scenario as node7-barbers.
- Added chair-lock recovery during native face refreshes.
- Male UI is strictly Eyes, Beard, Skin, Sculpt. Female UI is strictly Eyes, Makeup, Skin, Sculpt.
- Rebuilt beard catalog from the 18 named native multiplayer beard styles in node7-appearance.
- Beard application now uses the proven node7-appearance component sequence.

# 1.2.1

- Fixed the male Beard tab being hidden when the cloned barber-chair preview ped was misreported as female.
- Locks the session gender from the real Node7 character before ClonePed.
- Uses the same locked gender for catalog filtering, beard preview, profile validation, purchase, and cleanup.
- Added model and server-character fallbacks for reliable male/female detection.

# Versions

## 1.2.0

- Fixed the blue-character purchase bug by restoring the proven native overlay-ID sequence.
- Removed unsafe full-face foundation, discoloration, acne and complexion layers.
- Limited male and female characters to their own native option sets.
- Split male and female eyebrow catalogs.
- Added stable male beard preview, purchase and restore with corrected component flags.
- Reduced sculpting to the main native facial groups.
- Removed palette switching and invalid three-channel tint writes.
- Kept direct K DrawText interaction, no commands, no fallback keybinds, no blur and no blips.

# Versions

## 1.1.0

- Corrected native head-overlay construction for eyebrows, makeup, and skin layers.
- Added complete native facial sculpt preview and reload flow.
- Added male-only native beard models and colors.
- Added beard ownership tracking so old makeup profiles do not remove externally owned beards.
- Reapplies owned beard data after face and overlay refreshes.
- Uses direct K DrawText interaction with no commands or fallback bindings.
- Removed UI blur while leaving presentation otherwise unchanged.
- Preserves independent database, cash/bank payment, verification, refund, and restart persistence logic.
