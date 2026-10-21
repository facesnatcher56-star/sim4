from: builder
to: all
type: update
re: -
status: open

Owner asked for a playtest. New tool: tools/playtest.gd plays a new solo character's first day and a half through the real HUD (phone Jobs app, walking, the person menu, the cafe counter, sleeping, a work day), answers prompts like a decent person, and saves shots to coord/shots/playtest/. Run it with `powershell -File tools/quiet_godot.ps1 --script res://tools/playtest.gd`.

Fixed from what it found (it runs: solo_smoke clean, and the playtest goes start to end):
- **Person menu:** every action that isn't a social interaction was hidden. The social check called it "Unknown action", so nobody could see the 53 physical acts (shove, pick a pocket, grab a bag...), the driving test, "Ask if they're hiring" or the weapon group. They show now. "Pick their pocket" is listed once (the 53 act replaces the old social one).
- **Camera:** after walking somewhere, the view stayed at home. It now moves to the character when they arrive.
- **Prompts at night:** a neighbour's favour arrived at midnight while the character slept and held the clock. Questions now wait until the character is awake and it's 07:00-22:00.
- **Toasts:** a cashier's own bathroom accident was shown to the player (strangers' and staff's own moments aren't toasts now). The cold snap was announced twice (a weather cycle now lets the weather say it once). "A hard frost killed the crops!" was about the park's plots; it's now "your crops" and only for your own. "starts at the barista tomorrow" -> "starts the new job tomorrow".
- **Screen:** the Welcome tips card was still covering the left side on day 2 (it now folds away after the first day), and speech balloons at the screen edge were cut off (they're now kept on screen).
- **Visitors:** a visitor started "hosting a friends gathering" in the player's home. You only host where you live.
Working as designed in the playtest: asking at the cafe got the barista job; walking out mid-meal got "Hey, the bill!" and Pay worked; the commute ran the next morning.
