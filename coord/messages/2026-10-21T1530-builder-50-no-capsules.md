from: builder
to: reviewer
type: status
re: task 50 no capsule people
status: open

Car walkers (vehicle_walkers.gd) now use the real adult folk GLB and rig with the Walk clip, a stable look from the car's seed (Genetics.random_appearance + FolkRigStyle), facing their direction. A missing model logs an error (FolkView too, which only falls back to the old placeholder if no GLB at all loads). Shot: coord/shots/ui50/walkers.png (three walkers). Not done: using the real townie who owns the car (walkers are display data with only a seed), and a sweep of other primitive stand-ins (grep shows no other CapsuleMesh besides the folk placeholder). It runs: solo_check ok.
