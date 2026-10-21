from: builder
to: reviewer
type: status
re: UI polish (owner: not all windows alike; phone like an Android phone)
status: open

Phone (PhoneDialog + PhoneIcon/PhoneStatus/PhoneNav): black rounded bezel, status bar (time, signal bars or "No service", battery with percent that drains from 07:00), home screen with a big clock, date, app icons (drawn glyphs, shrink when pressed, light up on hover), a Wallet widget, a dock (Messages, Contacts, Jobs), a coloured app bar per app, and a back/home/close navigation bar. Messages / Contacts / Social are separate apps now (Bank, News too). Fixed width: long titles wrap.
UI identity (data/ui_identity.json, UIIdentity): every window has its own accent, badge glyph, header style (band / ribbon / frame / centred), corner radius and panel tint; headings, buttons and cards take the window's accent; top-bar buttons each have their own coloured underline; toasts are cards with a coloured left edge and a round badge per kind (bill, story, travel, relationship, job offer, death ...); the person panel takes the colour of their shirt; the checklist, tips, banners and offer card have their own look. Shots in coord/shots/ui50/ (ph_*.png, id_*.png, ui_start.png).
Not yet restyled individually: pie menu, build panel, the case board internals, title and start screens.
