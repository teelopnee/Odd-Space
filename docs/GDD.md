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

## 4. Next milestones (proposal)
- [x] HD-2D art pass v1 (sprite forge, normal-mapped kits, lens post, weather, foliage, cutscenes).
- [ ] Hand-painted hero portraits for dialogue; more building/prop kits per biome.
- [ ] Ship interior hub (walkable Odd Duck) instead of the nav-console screen.
- [ ] Boss fights (Paragon mech, Halcyon repo-walker) with multi-part BREAK shields.
- [ ] Quests generated from the Causality Graph (e.g. a reported murder spawns a vengeful sibling).
- [ ] Bounty hunters as on-planet enemies; Paragon raids when heat is high.
- [ ] Crew in the field (follow + assist + react live), crew personal quests.
- [ ] Sleeper-agent trigger event, sibling search storyline, motivation endings.
- [ ] Localization (Thai/English) with a Thai-capable font.
- [x] Android export preset + signed APK release; [ ] performance profiling on the Tab S12 Ultra.
