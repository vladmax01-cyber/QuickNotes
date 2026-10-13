# Quick Notes design direction

Reading this as: a native personal quick-capture utility for a keyboard-first Mac user, in a quiet tactile macOS language, dial ENERGY 1 / RHYTHM 1 / MOTION 2.

## Identity

- The app feels immediate, calm, and physically present without resembling a full notes manager.
- A single translucent note surface is the identity motif. It exists to separate handwriting-like capture from whatever app sits underneath.
- The editor is always the focal point. Navigation and controls recede until they are needed.

## Palette

- Native semantic macOS colors form the base so contrast and appearance track the system.
- One user-selected accent appears for focus and selected states, including the active formatting control and the pinned note.
- No gradients or glow. They would compete with typed content and have no hierarchy purpose here.

## Typography

- San Francisco system type keeps text native, familiar, and legible.
- Note content uses the system body face with comfortable line spacing; labels use native control styles.

## Layout and spacing

- A compact header carries sidebar, title, and pin controls without a conventional toolbar.
- The title strip is the drag handle so the window moves naturally without making toolbar buttons harder to click.
- The collapsible recent-notes rail preserves the scratchpad-first workflow.
- Spacing follows native control density, with extra breathing room around the editor to support long capture sessions.

## Materials and elevation

- Glass is limited to one root surface per app window so Quick Note and Settings share the same identity without stacking translucent cards.
- The 0–100% transparency scale preserves text opacity and keeps a light material veil at its maximum so controls remain legible.
- Settings keeps native grouped controls and opaque text so the shared transparency level never weakens readability.
- One soft panel shadow communicates that the note is temporarily above the current task.

## Motion

- Opening uses a short fade with a four-point settling motion; closing uses a shorter fade so motion clarifies state without slowing capture.
- Sidebar and search transitions are brief state changes; nothing loops or bounces.
- Haptics acknowledge a committed action after its visual change. Inline formatting uses a lighter tap; menu formatting and folding use a firmer one.

## Icons

- SF Symbols are used only when their meaning is direct: note, sidebar, pin, search, settings, and menu bar status.
- No custom logo is created. The app icon uses the relevant system note symbol until the owner supplies icon direction.
