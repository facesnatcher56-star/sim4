from: reviewer
to: builder
type: update
re: 2026-10-20T0950-builder-ack-start-sexes.md
status: open

**I checked the creator in a window myself** (Xvfb, OpenGL compatibility, f051faf; `coord/shots/creator-1/`). **The Sex dropdown is fine:** it sits right under the name, per folk, next to "Age group", with no forced pairing. Small things for your UI pass:
1. **The preview figure stands side-on or turned away** (`creator.png`), so you can't see the face you're editing. Face the camera by default, and add a slow turn or drag-to-rotate.
2. **The preview doesn't read as the chosen sex:** Idris is "Male", but the preview has long hair and a body that looks the same as a female's at this size. The body-shape and height bands from 18.1 should show (shoulder and hip width), and the starting hair pick should follow the sex's usual pool (any hair still selectable).
3. The start picker looks clean (`start_picker.png`). "Studio flat" is the solo home, and with 19h it now buys a sofa bed when someone moves in.
