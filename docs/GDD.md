# ODD-SPACE — Game Design Document (living)

## 1. Mood & Tone
- **Retro-Futurism 80s/90s**, dark satire of space capitalism.
- Year 3xxx. **The Consortium** (Big 5) bills for everything — including breathing.
- Opening: thaw from a cryo pod on the derelict *Cold Storage Lot 47*, with a second-hand ship
  **The Odd Duck** and its sarcastic AI **Q.U.A.C.K.**
- Music: synthwave + ancient plucked strings → futuristic, cheeky, lonely.

### The Consortium (the 5 factions)
| Faction | Business | Motto |
|---|---|---|
| OxyGenix Atmospherics | owns the air | "Every breath, a brand experience." |
| Halcyon Debt & Trust | loans, cryo-collateral (froze you) | "Your future, collateralized." |
| Gristle Nutrition Group | Protein Paste(tm) | "Food-adjacent since 2981." |
| Paragon Compliance Services | private police, bounty hunting | "Safety is a subscription." |
| Lumen Omnimedia | news, ads, propaganda | "Truth, now with fewer opinions." |

## 2. Visuals (HD-2D)
- 2D pixel-art characters on Y-billboards in a 3D world, **lit by real lights and casting real shadows**.
- Low-poly 3D environments (budget 5k–15k tris per building/prop set), neon emissive trims.
- Post: bloom/glow, fog, ACES tonemap, saturation boost, **tilt-shift depth of field**
  (physical depth DOF optional), subtle scanline/vignette overlay.
- Diegetic UI: holographic billboards with satirical ads (shootable), floating radio-call bars
  above witnesses, damage numbers and subsystem labels in 3D, Lumen news ticker.

## 3. Core systems (implemented in v0.1)
1. **Dynamic Origin & Tag Engine** — no classes. Background × Motivation × Secret/Flaw (+ synergies).
   Decides spawn room, starting credits/items, stat mods, starting rep/bounty, NPC reactions.
2. **Causality Graph Engine** — every act is a node with causes/effects. Crimes seen by witnesses
   become *pending*; the witness radios it in over a few seconds. Finish → *reported*
   (rep loss, bounty, headline, guards turn hostile). Kill/bribe/threaten before the call ends →
   *suppressed*. Unseen → *secret*. Fleeing the level lets pending calls finish.
   NPCs elsewhere know local crimes, crimes against their controller, and galactic news (severity ≥ 4).
3. **Fast combat** — dodge roll with i-frames, parry window (melee → stagger, bolts → reflected ×2),
   auto-aim at a chosen **subsystem**: legs (cripple/knock down), jetpack (explodes, hurts allies),
   weapon (disarm), head/visor (crit), sensor (blind), thruster (crash).
4. **Procedural Planet Matrix** — environment × controller × economic crisis × local anomaly.
5. **Space Encounters** on warp — ghost ship, fake distress, Paragon checkpoint, ad drone,
   bounty hunter, Lumen interview, free sample, Halcyon collector, cryo auction.
6. **Faction Reputation** −100..+100 → prices, trade refusal, hostile guards, hunters.
7. **Crew Morality Engine** — max 4; each judges actions on mercy/order/greed. Disloyal crew
   steal the ship's money, leak coordinates (forced hunter encounter) or mutiny (fight them next planet).
8. **Flaw & Perk** — repeated mishaps (failed parries, bites, getting shot in the back, explosions,
   air debt, getting caught stealing...) offer a permanent flaw for free skill points.
9. **Air billing** — OxyGenix charges every 10 s; unpaid air becomes Halcyon debt.

## 3b. Combat feel (v0.2)
- Melee: 3-hit energy-baton combo with lunges, slash arcs, hitstop; roll-cancel after a hit lands.
- Blaster: tap to shoot the locked subsystem; hold to CHARGE a piercing shot (2 shield damage).
- Perfect dodge (roll at the last instant): slow-mo + Overclock gain. Parry: zoom punch, stagger, reflect.
- OVERCLOCK: 3-pip boost meter from hits/parries/perfects/breaks; spend for a damage/speed burst.
- BREAK: shields + weaknesses (MEL/BLS/CHG/EXP/PRY/part names), discovered on first hit, shown over enemies.
- Enemies: flinch/knockback (armoured ones don't), strafing ranged AI, telegraph rings for melee lunges,
  last-kill slow-mo, credit chips that magnetise to you.

## 3c. Every run is different (v0.3)
- **Start choice**: thaw out of cryo in Lot 47 (classic prologue) *or* be a native of any generated
  world in this universe (hometown rep +12 with its owners, +40 cr, start on the pad, no prologue).
- **Universe seed**: one number = 7 worlds + the whole saga. Shown/typed in the creator, shareable.
- **Look**: 36 chibi body/outfit/hair variants x free palette (skin, hair, eyes, outfit, neon), live
  8-way turntable. NPCs/enemies/crew/saga cast all roll their own looks (faction uniforms for corp staff).
- **Saga** (procedural main story): antagonist (absurd corporate title + scheme), ally (job, traits,
  quirk), lieutenant, MacGuffin, personal thread from *Motivation*, twist from *Secret*.
  7 beats / 3 acts across random planets: contact → clue → personal → lieutenant → MacGuffin →
  twist (forgive / cut ties / sell out) → finale (expose / seize / destroy). Side jobs per planet
  (bounty, lost item, ad sabotage). Journal tab with cast portraits revealed as the story unfolds.
- **Dense random worlds**: per-biome generators (city grid with markets and plazas, swamp canals
  with boardwalks, plastic-glacier desert with ad towers, mesa canyon, crystal pools), random map
  size, frontier towns around the pad, foreground dressing, sky traffic, per-seed palette/weather.

## 3d. Life paths (v0.4)
- Origin = 6 tags: **class** (5 Consortium heirs, old money, executive, middle manager, gig worker, working poor,
  drowning in debt, street beggar, collateral/owned, off-grid ghost), **age** (6 brackets + exact age 16-312),
  23 backgrounds, 8 personalities, 12 motivations, 12 secrets, 31 synergies: 2.2M combinations x 8 starts.
- **Interactions**: 54 verbs on NPCs gated by who you are (heirs pull rank / call the family lawyer, beggars beg and
  trade gossip, teens play innocent, elders get senior discounts, netrunners hack wristpads, preachers convert,
  organisers unionise, charmers flirt, the ruthless extort...). Odds depend on NPC traits, faction, mood, your rep.
- **Saga v2**: every beat branches; elites surrender (kill / spare / arrest / recruit / interrogate / extort /
  stream / seize / reparations / redeem...); 8 twist choices incl. defecting to the villain; 15 finales + 5 for
  defectors; 12 early endings when your Motivation comes true first; endings are composed: 3.1M distinct.
- **Planet stories**: each world's crisis becomes a local arc with 5 resolutions that change the planet (crisis
  resolved/worse, prices, air, liberation). **Street events**: 16 incidents, 69 gated choices.

## 4. Next milestones (proposal)
- [x] HD-2D art pass v1 (sprite forge, normal-mapped kits, lens post, weather, foliage, cutscenes).
- [ ] Hand-painted hero portraits for dialogue; [x] more building/prop kits per biome (v0.3).
- [ ] Ship interior hub (walkable Odd Duck) instead of the nav-console screen.
- [ ] Boss fights (Paragon mech, Halcyon repo-walker) with multi-part BREAK shields.
- [ ] Quests generated from the Causality Graph (e.g. a reported murder spawns a vengeful sibling).
- [ ] Bounty hunters as on-planet enemies; Paragon raids when heat is high.
- [ ] Crew in the field (follow + assist + react live), crew personal quests.
- [x] Sibling search / motivation threads and twists via the Saga; [ ] voiced sleeper-trigger set piece.
- [ ] Localization (Thai/English) with a Thai-capable font.
- [x] Android export preset + signed APK release; [ ] performance profiling on the Tab S12 Ultra.
