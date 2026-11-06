# ODD-SPACE - Hostile Review Log

A living, deliberately merciless critique of the game, written as a professional reviewer would
write it for players of this genre. Every pass: score it, list what a buyer would hate, fix, re-score.
Code that runs is not a game that is fun - tests prove the first, only playtests prove the second.

## Who buys this game, and what they want (research)
Players of 2.5D diorama action-RPGs, immersive sims and systemic "the world remembers" games.

| Finding | What it means for ODD-SPACE |
|---|---|
| Watch Dogs: Legion's "play as anyone" was praised as a system but critics said the generated recruits were interchangeable and the story lost its heart ([Push Square](https://pushsquare.com/reviews/ps4/watch_dogs_legion), [PC Gamer](https://www.pcgamer.com/all-of-my-watch-dogs-legion-recruits-are-massive-disappointments), [CGM](https://www.cgmagonline.com/review/watch-dogs-legion-pc-review/)) | Our generated NPCs, crew and saga personas carry the same risk. Generated people need authored anchors. |
| Wildermyth works because each chapter has a hand-written opening and ending with procedural content in between, and scenes are templates that slot the player's own characters in ([RPG Site](https://rpgsite.net/review/12107-wildermyth-review), [COGconnected](https://cogconnected.com/review/wildermyth-review/), [SUPERJUMP](https://www.superjumpmagazine.com/wordplayer-wildermyth-lays-bare-the-false-promises-of-ai-storytelling/)) | Copy the structure: authored bookends per act, written around the player's tags; procedural middle. |
| Octopath's most common criticism: stories feel samey and disconnected, pacing is slow ([GamesRadar round-up](https://www.gamesradar.com/octopath-traveller-review-round-up), [RPGamer](https://rpgamer.com/game/octopath-traveler-ii/)) | Our acts and planets must connect to each other and to the player's motivation, and travel must be fast. |
| Refunds are driven by early crashes, bugs and poor performance in the first session ([Bugnet](https://bugnet.io/blog/why-are-players-refunding-my-game), [Game Developer](https://gamedeveloper.com/business/4-reasons-why-steam-refunds-are-a-threat-to-indie-game-devs-)) | The first 30 minutes must be flawless and run well on weak devices: graphics presets, stable saves. |
| Good onboarding teaches one mechanic at a time, at the moment it is needed, by doing - not with text walls ([GDevelop](https://gdevelop.io/blog/improve-game-tutorials), [Apple](https://developer.apple.com/app-store/onboarding-for-games/), [Wayline](https://www.wayline.io/blog/tutorials-onboarding-level-design)) | Just-in-time tips, never a manual up front. |
| Touch controls: keep the button count low, make them big, give press feedback, never cover the hero ([Game Developer](https://www.gamedeveloper.com/game-platforms/designing-better-controls-for-the-touchscreen-experience), [Flowlab](https://www.flowlab.io/lab/blog/designing-for-mobile)) | We had 11 buttons on screen at all times. |
| Immersive-sim fans want reactions with tangible effects, consistent rules, and no punishment for a playstyle ([GMTK/Reddit discussions, NO LAW dev interview](https://wccftech.com/no-law-lets-you-kill-any-character-inspired-immersive-sims/amp/)) | Our reactivity is strong; it must stay legible (show what changed) and fair (stealth and violence both viable). |

## Scorecard
| Area | v0.11 | Now | Notes |
|---|---|---|---|
| Systemic depth | 8 | 8 | The real selling point. |
| Combat | 4 | 5 | Tokens, dash strike, 10 weapons, difficulty settings. Still unplaytested by humans. |
| Onboarding | 2 | 6 | Just-in-time tips (wait for dialogues to close) + a 4-step FIRST DAY checklist that teaches by doing. |
| UI / readability | 3 | 7 | Contextual touch buttons, status panel that tucks away when calm, prompts that match the device, capped result text, UI scale. |
| Writing | 5 | 7 | Authored act bookends + authored meetings: the ally sizes you up, the fixer and the villain talk before they fight, the villain calls you about what you did. Side quests still template-heavy. |
| Visuals | 5 | 5 | Atmospheric, but generated characters look like programmer art at store-page size. |
| Audio | 3 | 3 | Synthesised music and SFX: thin. Needs real tracks. |
| Tech / platforms | ? | 7 | Graphics presets, Back button, pause on leave, Windows + Linux builds, mouse, F11. Game-logic CPU measured and cut ~2.8x (tools/perf_probe.gd). Still unmeasured on real phones (GPU side). |
| Commercial readiness | 2 | 5 | Credits/licences screen, parody names cleaned, trademarked terms out of store copy. Repo still public. |

**Overall (v0.17.2): 6/10.** Deep, reactive and now reasonably polished in the first five minutes, but nobody outside
the project has played it, the music is synthesised filler and the characters still read as programmer art at store
size. Not ready to sell until the two P0s below are closed.

## Open issues (P0 = a buyer would refund)
- P0 **Never playtested end to end by a human.** Owner + 5 outside players, watch where they quit.
- P0 Repository and CI "latest" APK are public: anyone can get the game free (owner decision).
- P1 (partly done) FIRST DAY checklist teaches talk -> shop -> fight -> change someone's mind; a scripted first street encounter would still be stronger.
- P1 (done for now) Authored bookends for acts I-III, authored meetings with the ally, the lieutenant and the antagonist, side quests with 6 offers per type, a manner per giver and a turn-in choice. Next: side quests are still three shapes (bounty / fetch / sabotage).
- P2 (done) HUD density: panel compacted, and out of combat it tucks away to name / HP / money / objective after 6 s of calm (Settings: off).
- P1 Music: replace at least the title, city and combat tracks with real compositions.
- P2 Store assets: capsule art, 5 screenshots, 30 s trailer, honest feature list.
- P2 (CPU done) Game-logic CPU per city 0.96-1.6 ms on a desktop core (was 2.1-4.5). Still to do: GPU/frame time on a real mid-range phone (owner).

## Fix log
- v0.12: just-in-time tips (data/tips.json, 14 situations, Settings: off / show again); NPC follow-up dialogues only
  for big moments or by a "sometimes" roll (Settings: often / sometimes / rare); "what changed" block capped at 3 lines;
  touch buttons appear only when useful (TGT / PART / PARRY in combat, BOOST when charged, BLADE / GUN with a choice,
  MED when hurt); Settings: difficulty (story / normal / hard: damage and how many attack at once), graphics
  (render scale, shadows, particles, crowd density), text and button size; Android Back closes menus instead of quitting,
  leaving the app pauses and autosaves; save format v2; Credits & Licenses screen (Godot + third-party texts);
  parody TV titles renamed; "HD-2D" (a Square Enix trademark) removed from store-facing text; Windows + Linux export
  presets and CI builds; mouse controls (left = melee, right = fire); F11 / Alt+Enter fullscreen.
- v0.13: hand-written act bookends (data/bookends.json): every act opens with an authored scene written around the
  player's motivation (12) and wealth (3), and closes with a reflection on their dominant moral axis and their crew;
  Act I plays after the first landing. tools/story_test.gd checks four very different lives see every bookend with no
  unfilled tokens. Windows + Linux zips now ship next to the APK on the "latest" release.
- v0.14: critique pass at phone size (1600x720, tools/ui_review.gd). Found and fixed: the first tip expired unseen behind the
  Act I popup (tips now wait for dialogues and menus); swamp water read as flat neon slabs (darker, lower glow); status panel
  ran to 10 lines (air debt + bounty merged, short weapon names). Added the FIRST DAY checklist (talk, shop, fight, change
  someone's mind; small rewards, medkit at the end).
- v0.14.1: weapon/enemy balance audit (tools/balance_audit.py: damage per second per weapon, enemy hit as % of the
  player's HP). Arc Thrower was 88 dps with a stun (best gun by far) -> 55 dps, shorter stun; Mono-Katana was the
  only blade worth using -> on par with the Repo Hammer; Repo Harpoon was a trap pick -> stronger pull hit;
  pirates fired 3-shot bursts that took 30% of your HP -> 2 shots. Vat Golem still hits for 24% but telegraphs a full second.
- v0.15: the villain used to be a name in other people's sentences until the final fight. Now: an authored FIRST CONTACT
  scene with the ally (by your personality x their trait x your wealth / family), THE FIXER speaks before the lieutenant
  fight (their trait x your wealth), the antagonist hijacks every screen nearby to CALL you about what you did to their
  fixer (7 fates x wealth / family feud x their trait), and a FACE TO FACE before the finale reflects your moral axis and
  what you did to the ally. Saga people talked to outside their beat now point you at the next goal in their own voice
  instead of "Not now. They're watching." Bugs found by the new story test: every "{faction}" in the saga printed the
  internal id ("VP at gristle"), including the very first story dialogue; ending headlines were first-match, so 6 of 6
  random lives became "THE PROPHET OF FREE AIR" (now the strongest qualifying legacy wins: Prophet / Mercenary / Martyr /
  Turncoat across the same 6 lives); "WHO CHOSE THEMSELF" read as a typo.
- v0.16: performance + identity pass. Measured the CPU cost of a city properly (tools/perf_probe.gd; the engine monitor
  is a per-second maximum and headless runs sleep 6.9 ms a frame, so the first numbers were wrong). Found: every walking
  NPC pushed itself into the floor and collided with the seams between floor chunks on every step (4x the cost of a
  clean step); 34 shop owners per city sat in physics every frame and some were wedged on a kerb "falling" at -143 m/s
  forever; off-screen people and foes ran at full rate; every sprite re-sent its shader parameters every frame. Fixed
  all four: densest city 4.5 -> 1.4 ms, 5 of 7 planets over budget -> 0. Hostile catch from the same probe: every
  corporate store in a city was run by the same person ("Zeb", 13 times, one face, one shared memory and ban list)
  because the owner's identity was keyed on the brand sign; owners are now one per door (keeper_test checks it).
  Name grammar no longer stacks titles ("Auntie Grandma Lin").
- v0.17: side quests had ONE offer and ONE thank-you line per type, so a run (7-14 side quests) repeated the same speech
  on several planets ("These billboards scream at my kids all night"). Now: 6 offers and 4 thank-yous per type (picked
  per quest), a line for how each giver talks (12 traits), varied "still waiting" lines, a different ending when you
  spared the bounty target, and a choice when you collect: take the money, waive it (a follower and some fame), or
  haggle for more (ruthless / charming always win, others 40%; a failed haggle costs reputation). story_test checks a
  run's offers are 70%+ unique, tokens are filled and every turn-in choice pays what it says.
- v0.17.1: status panel tucks away when calm (no hostile within 16 m, full HP, nothing changed for 6 s): weapons,
  air debt / bounty and overclock rows hide and the backdrop fades; anything new brings it back. Setting in the pause
  menu. Checked at 1600x720 with tools/ui_review.gd (new "_calm" shot): 8 rows -> 4.
- v0.17.2: first-five-minutes pass on the title and the creation form at 1600x720. Found: pressing Esc in the creation
  form (Esc is also "pause") STARTED a new life instead of going back; the footer always showed gamepad hints
  ("LB/RB = category") to keyboard and touch players; touch controls forced on still produced "press F" tips; the
  save line was a raw ISO timestamp printed over the striped sun; "WAKE UP IN: CARGO HOLD" contradicted "Cold Storage
  Lot 47" beside it. All fixed (START begins only from a pad; hints follow the input device; touch-on = touch prompts;
  "6 Nov, 12:35" on a dark plate; "COLD STORAGE LOT 47 - CARGO HOLD").
