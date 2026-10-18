from: reviewer
to: builder
type: task
re: 2026-10-18T1830-reviewer-rare-events-00-plan.md
status: open

**08: Everything happens to everyone, news travels, the town grows.** From the owner. **This changes how you build tasks 01 to 07**, so read it before you start 01.

**1. Every event applies to every person and every lot, not only the player household.**
- Near or active townies run the full version of an event (the same code as the household).
- Far townies run a **statistical version** inside `Story` / `NeighborhoodService` / `Away`: the same `data/incidents.json` rates and conditions, resolved by dice with outcomes recorded. For example, "The Ashby house had a kitchen fire, no one hurt" or "Dax Holt was mugged near the cafe".
- Townie traits, skills, relationships, grudges and lot objects affect their risk just as they do for the household. A hot-headed townie with a long grudge can murder another townie; a careless cook can burn their own house down.
- Town-scope disasters hit every lot, with damage rolled per lot.

**2. News and rumours: how the player finds out.**
- **Town Chronicle:** a log of everything notable that happened anywhere (deaths, crimes, fires, births, weddings, arrests, disasters, lottery wins, new arrivals, businesses opening and closing). Store it in the save and cap the size.
- **Newspaper** (a daily paper delivered to the home lot, with a "Read the paper" interaction) and a **TV news** channel: these show the bigger stories from the Chronicle, delayed by a day.
- **Rumours through gossip:** use the existing `RelationshipKnowledge` gossip and secrets. Folk who witnessed or heard about an event carry it as a topic, and it spreads conversation by conversation, sometimes distorted (wrong name, exaggerated: "I heard it was arson"). A thought bubble shows when a Folk hears news ("Did you hear about the Finch fire?").
- **Personal impact:** if the victim is someone a Folk knows, they get the matching grief or worry mood, and close friends can go to the funeral or visit the grave. Witnessing crime or disaster raises fear for a while. A murder in town gives everyone "Uneasy at night" until the case is solved.
- **Police case board:** solved and unsolved cases in town. Player Folk with high logic or charisma can help an investigation (a lead-in for a detective career later).
- **Notification policy:** only events involving people the household knows, or big town events, pop up. Everything else goes quietly to the Chronicle and the paper. The notification count was already too high, so don't make it worse.

**3. The town grows and changes.**
- **Population:** townies date, marry, have children, age and die; families move in and out; the population stays within a band (raise `max_population` as the open map allows). New arrivals are generated with traits, looks (the unique-looks system) and jobs.
- **Housing:** new families move into empty lots, and new houses get built on free lots using the house generator. Run-down or damaged lots can be abandoned and then rebuilt.
- **Businesses:** venues can open, close or change owners over time. A new cafe opens, the gym shuts down after a recession. Townies work at them.
- **Town state and history:** keep track of the year, population, crime rate, and a "town mood". The Chronicle becomes the town's history, so a player can look back at the year a tornado hit or the unsolved murder of 3 years ago.
- **Generations:** the household's kids grow up and can move out to another lot in town and stay simulated. Townie dynasties form. The family tree covers the town.
- Keep the far-sim cheap. A long-run test should simulate 10 game years of the whole town, check the population band, the event rates and that the Chronicle size stays bounded, and report the time it took.
