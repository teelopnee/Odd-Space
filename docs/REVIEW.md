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
| UI / readability | 3 | 6 | 5 touch buttons instead of 11 out of combat, compact status panel, capped result text, UI scale. |
| Writing | 5 | 6 | Hand-written act openings/closings now frame the procedural saga (Wildermyth model). Middle still template-heavy. |
| Visuals | 5 | 5 | Atmospheric, but generated characters look like programmer art at store-page size. |
| Audio | 3 | 3 | Synthesised music and SFX: thin. Needs real tracks. |
| Tech / platforms | ? | 6 | Graphics presets, Back button, pause on leave, Windows + Linux builds (CI, verified), mouse, F11. Unmeasured on real devices. |
| Commercial readiness | 2 | 5 | Credits/licences screen, parody names cleaned, trademarked terms out of store copy. Repo still public. |

## Open issues (P0 = a buyer would refund)
- P0 **Never playtested end to end by a human.** Owner + 5 outside players, watch where they quit.
- P0 Repository and CI "latest" APK are public: anyone can get the game free (owner decision).
- P1 (partly done) FIRST DAY checklist teaches talk -> shop -> fight -> change someone's mind; a scripted first street encounter would still be stronger.
- P1 (partly done) Authored bookends exist for acts I-III; next: authored mid-act scenes for the ally and the antagonist.
- P2 HUD density: panel compacted (debt + bounty one line, short weapon names); consider auto-hiding out of combat.
- P1 Music: replace at least the title, city and combat tracks with real compositions.
- P2 Store assets: capsule art, 5 screenshots, 30 s trailer, honest feature list.
- P2 Performance budget per device class; profile a 40-NPC city on a mid-range phone.

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
