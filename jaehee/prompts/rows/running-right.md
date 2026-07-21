Create one horizontal animation strip for Codex pet `jaehee`, state `running-right`.

User override for this run: strictly match `references/canonical-base.png` for identity, proportions, palette, outline weight, face, green star pouch, green strap, and small head tuft. For this state, remove the mint microphone entirely; do not carry it in any frame. Show rightward drag movement with a bigger readable animation: ears swing, body leans/travels toward screen-right, tiny feet alternate, and the tail wags across frames. No speed lines, dust, shadows, or detached effects.

Use the attached canonical base for identity. Use the attached layout guide only for slot count, spacing, centering, and padding; do not draw the guide.

Output exactly 8 full-body frames in one left-to-right row on flat pure user-selected #FF00FF. Treat the row as 8 invisible equal-width slots: one centered complete pose per slot, evenly spaced, with no overlap, clipping, empty slots, labels, or borders.

Identity: same pet in every frame: Cream white chibi puppy desk pet based on the supplied standing plush reference, with droopy ears, brown embroidered face, tiny tongue, soft pink cheek marks, mint microphone, green star crossbody pouch, and small music-note accent. Preserve silhouette, face, proportions, markings, palette, material, style, and props.
Style: Pet-safe sprite: compact full-body mascot, readable in a 192x208 cell, clear silhouette, simple face, stable palette/materials, and crisp edges for chroma-key extraction. Style `sticker`: Polished sticker mascot with bold clean shapes, crisp outline, flat colors, and minimal highlight detail. User style notes: 2D flat chibi official merchandise standee/sticker illustration, doll-like but not photo plush, clean bold outer contour, simple rounded color blocks, very light 2D shadow only, transparent-ready sprite material, no 3D rendering, no realistic fur, no clothing, no blue tag, no stars except the green star pouch from the reference..
Animation continuity: keep apparent pet scale and baseline stable within the row unless the state itself intentionally changes vertical position, such as `jumping`. Move the pose within the slot instead of redrawing the pet larger or smaller frame to frame.

State action: Dragging-right loop: show directional movement to the right through body and limb poses only.

State requirements:
- Show directional drag movement to the right through body, limb, and prop movement only.
- The row must unmistakably face and travel right.
- The movement cadence must alternate visibly across the 8 frames instead of repeating one nearly static stride.
- Do not draw speed lines, dust clouds, floor shadows, motion trails, or detached motion effects.

Clean extraction: crisp opaque edges, safe padding, no scenery, text, guide marks, checkerboard, shadows, glows, motion blur, speed lines, dust, detached effects, stray pixels, or chroma-key colors inside the pet.
