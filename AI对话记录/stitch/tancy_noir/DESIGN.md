# Design System Document: The Sonic Canvas

## 1. Overview & Creative North Star
**Creative North Star: "The Obsidian Conductor"**

This design system transcends the standard "utility" feel of mobile applications to create an immersive, editorial-grade auditory environment. It rejects the rigid, boxy constraints of traditional Android interfaces in favor of a fluid, high-contrast aesthetic that treats album art and playback controls as high-fashion artifacts.

The system is built on **Intentional Asymmetry** and **Tonal Depth**. By utilizing overlapping elements—where typography breaks the boundaries of its containers and glassmorphism blurs the lines between foreground and background—we create a "Sleek-Futurism" that feels alive. This is not just a player; it is a premium digital stage where the user's music is the sole protagonist.

---

## 2. Colors: Depth and Vibration
Our palette is anchored in the abyss (`surface: #0e0e0e`), allowing vibrant accents to punch through with electric intensity.

### The "No-Line" Rule
**Explicit Instruction:** Designers are prohibited from using 1px solid borders for sectioning. 
*   **Alternative:** Boundaries must be defined solely through background color shifts. Use `surface-container-low` for secondary sections and `surface-container-high` for elevated modules.
*   **The Transition:** Use soft, radial gradients (e.g., from `background` to `surface-container`) to define areas without creating hard visual stops.

### Surface Hierarchy & Nesting
Treat the UI as a series of physical layers of tinted glass.
*   **Base Layer:** `surface` (#0e0e0e)
*   **Contextual Layer:** `surface-container-low` (#131313) for the main scrollable feed.
*   **Active Layer:** `surface-container-highest` (#262626) for the currently playing track bar.
*   **Interactive Layer:** `primary` (#81ecff) for active states and critical touchpoints.

### The "Glass & Gradient" Rule
To achieve a "bespoke" feel, use **Glassmorphism** for all floating overlays (e.g., volume sliders, menu popovers). 
*   **Formula:** Apply `surface-variant` at 60% opacity with a 20px-30px backdrop blur.
*   **Signature Textures:** Main Play/Pause CTAs should utilize a linear gradient from `primary` (#81ecff) to `primary-container` (#00e3fd) at a 135° angle to add "soul" and dimension.

---

## 3. Typography: The Editorial Voice
We use a dual-font approach to balance high-fashion character with utility-grade legibility.

*   **Display & Headline (Space Grotesk):** This is our "signature." Used for artist names and section headers. The geometric, slightly futuristic nature of Space Grotesk provides an authoritative, modern edge. Use `display-lg` (3.5rem) for hero artist pages to create an editorial layout.
*   **Body & Labels (Inter):** Inter is the workhorse. It ensures that track durations, settings, and metadata remain hyper-readable even at `body-sm` (0.75rem).

**Hierarchy Rule:** Never center-align long lists of text. Use left-aligned `title-lg` for track names and `body-md` with `on-surface-variant` (#adaaaa) for album titles to create clear, tiered scanning.

---

## 4. Elevation & Depth: Tonal Layering
Traditional drop shadows are too "standard." We define elevation through light and transparency.

*   **The Layering Principle:** Instead of a shadow, place a `surface-container-lowest` card on a `surface-container-low` section. The subtle contrast creates a soft, natural "recessed" or "lifted" look.
*   **Ambient Shadows:** For floating action buttons (FABs), use a shadow color tinted with `primary` at 8% opacity with a blur radius of 24px. This mimics the glow of the accent color rather than a dark grey "sticker" effect.
*   **The "Ghost Border":** If a separation is legally required for accessibility, use the `outline-variant` token at 15% opacity. High-contrast, 100% opaque borders are strictly forbidden.
*   **Glassmorphism Depth:** When using glass overlays, ensure the `on-surface` text maintains a 7:1 contrast ratio against the blurred background.

---

## 5. Components: Precision & Fluidity

### Playback Controls (The Signature Suite)
*   **Play/Pause Button:** A `xl` (1.5rem) rounded container using the `primary` gradient. The icon should be `on-primary-fixed` (#003840).
*   **The Heart (Favorite):** In its active state, it uses `secondary` (#ff734a) with a subtle glow effect (4px blur of the same color).

### Buttons
*   **Primary:** `full` (pill) roundedness. No border. Gradient fill.
*   **Secondary:** `md` roundedness. Transparent fill with a "Ghost Border."
*   **Tertiary:** Text only using `primary` color, `label-md` weight.

### Cards & Lists (The "No-Divider" Rule)
*   **Track Lists:** Forbid the use of divider lines. Separate items using `spacing-4` (1rem) of vertical white space.
*   **Album Cards:** Use `lg` (1rem) corner radius. Metadata should be nested within a glassmorphic strip at the bottom of the card imagery.

### Input Fields
*   **Search Bar:** Use `surface-container-highest`. Do not use a border. Use `md` (0.75rem) corner radius. The cursor should be the `secondary` color for a "futuristic spark" during interaction.

### Custom Component: The "Fluid Progress Bar"
*   **Track Seek:** The background track is `outline-variant` at 20% opacity. The active progress is a gradient of `primary` to `tertiary`. The "scrubber" thumb only appears on touch, using a `surface-bright` fill to contrast against the dark track.

---

## 6. Do's and Don'ts

### Do:
*   **Do** use asymmetrical margins. If the left margin is `spacing-6`, try a right margin of `spacing-8` for hero headers to create movement.
*   **Do** allow album art to "bleed" into the background using a massive 150px blur of the `primary` color.
*   **Do** use `full` roundedness for all interactive "pill" elements to maintain the futuristic, aero-aesthetic.

### Don't:
*   **Don't** use pure `#000000` for containers; it kills the depth. Use `surface` (#0e0e0e) or `surface-container-lowest`.
*   **Don't** use standard Android "Material Ripple" in gray. Always tint ripples with the `primary` or `secondary` token at 10% opacity.
*   **Don't** crowd the interface. If in doubt, add `spacing-10` (2.5rem) of empty space. White space is a luxury signal.