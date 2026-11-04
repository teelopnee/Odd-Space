# ODD-SPACE

> **Sci-Fi HD-2D Action-RPG** · Retro-Futurism ยุค 80s/90s · Dark Satire เสียดสีทุนนิยมอวกาศ
> Godot **4.7** (Mobile renderer / Vulkan) · ออกแบบให้พัฒนาและเล่นบน **Samsung Galaxy Tab S12 Ultra** · รองรับ **จอย / จอสัมผัส / คีย์บอร์ด**

![Station](docs/screenshots/station.jpg)

ศตวรรษที่ 32 · กลุ่มทุนบิ๊ก 5 **The Consortium** เก็บเงินกับทุกอย่าง แม้แต่อากาศหายใจ
คุณตื่นจากตู้แช่แข็งบนสถานีร้าง *Cold Storage Lot 47* พร้อมยานมือสอง **The Odd Duck**
และ AI ประจำยานปากแจ๋ว **Q.U.A.C.K.**

| | |
|---|---|
| ![Intro](docs/screenshots/intro.jpg) | ![Combat](docs/screenshots/combat.jpg) |
| ![Swamp](docs/screenshots/planet_swamp.jpg) | ![Landing](docs/screenshots/planet_landing.jpg) |

---

## ▶ เล่นได้ทันที (Android / Galaxy Tab)

1. เอาไฟล์ `odd-space.apk` มาไว้บนแท็บเล็ต — จากไฟล์ที่ Claude ส่งให้ในแชท, หรือจาก **[หน้า Releases](https://github.com/teelopnee/Odd-Space/releases)** (เมื่อมีการอัปโหลด / เมื่อเปิด auto-build แล้ว)
2. แตะไฟล์เพื่อติดตั้ง (ครั้งแรกให้อนุญาต *ติดตั้งแอปที่ไม่รู้จัก* ให้แอปที่ใช้เปิดไฟล์)
3. เปิดเกม **ODD-SPACE** — ต่อจอย Bluetooth (Xbox / PlayStation / 8BitDo ฯลฯ) ได้เลย ปุ่มสัมผัสจะซ่อนเองเมื่อใช้จอย และกลับมาเมื่อแตะจอ

> ต้องการให้ GitHub สร้าง APK ใหม่อัตโนมัติทุกครั้งที่ push? ดูหัวข้อ *Auto-build APK* ใน [docs/TABLET_WORKFLOW.md](docs/TABLET_WORKFLOW.md)

## 🎮 การควบคุม

| แอ็กชัน | จอย (Xbox / PS) | แท็บเล็ต | คีย์บอร์ด |
|---|---|---|---|
| เดิน / วิ่ง (กดแรง = วิ่ง) | L-Stick | จอยซ้าย | WASD |
| **ฟัน 3 จังหวะ (คอมโบ)** | X / □ | MELEE | J |
| ยิง (แตะ) / **ยิงชาร์จ** (กดค้าง แล้วปล่อย ทะลุศัตรู) | RT / R2 | FIRE | K |
| กลิ้งหลบ (i-frame) — หลบนาทีสุดท้าย = **PERFECT DODGE** สโลว์โม | A / ✕ | ROLL | Space |
| ปัดป้อง — ศัตรูเซ, กระสุนสะท้อนกลับ x2 | RB / R1 | PARRY | L |
| **OVERCLOCK** (ใช้เกจ 3 ช่องที่สะสมจากการตี/ปัด/หลบ) | B / ○ | BOOST | R |
| เปลี่ยนเป้า / เปลี่ยนชิ้นส่วนที่เล็ง | LB / R-Stick ซ้ายขวา · LT / R-Stick ขึ้นลง | TGT / PART / **แตะที่ศัตรู** | Tab / Q |
| คุย / ขโมย / ใช้ | Y / △ | ปุ่มกลางจอ | F |
| เมนู · Causality Log | Start · Back | MENU | Esc · C |

## ✨ มีอะไรในเวอร์ชันนี้ (v0.2.0)

**ภาพแบบ HD-2D (สไตล์เดียวกับ Octopath แต่เป็นงานออริจินัลทั้งหมด)**
- ตัวละคร pixel art **8 ทิศทาง** + แอนิเมชันลื่น (เดิน/วิ่ง/กลิ้ง/คอมโบ 3 ท่า/ยิง/ชาร์จ/ปัด/บาดเจ็บ/ล้ม/คุย) สร้างด้วย *Sprite Forge* (โมเดล 3D → ลงสีแบบ pixel art อัตโนมัติ)
- ฉาก 3D พร้อม **normal map** แสงนีออน/โคมไฟสะท้อนพื้นผิว, หน้าต่างมองเห็นเนบิวลา, ลำแสงฝุ่น, ฝุ่นลอย, พื้นสะท้อนแสง, หญ้า/พืชต่างดาวพลิ้วตามลม, ฝน/หิมะ/สปอร์/ประกายไฟ
- เลนส์แบบ HD-2D: **tilt-shift**, bloom ฟุ้ง, vignette, chromatic aberration, grain, color grading
- **คัตซีน**: แถบ letterbox, การ์ดชื่อฉาก (Chapter card), ยานลงจอดทุกครั้งที่ถึงดาวใหม่ — ฉากต่อฉาก

**การต่อสู้มันส์ ๆ**
- คอมโบฟัน + พุ่งเข้าใส่, hitstop, กล้องสั่น/ซูมกระแทก, จอยสั่น, ตัวเลขดาเมจเด้ง
- **BREAK**: ศัตรูมีโล่ + จุดอ่อน (เช่น MEL / BLS / LEG / JET) — ตีจุดอ่อนจนโล่แตก = มึน + ดาเมจ x2
- **Subsystem Targeting**: ยิงขาให้ล้ม, ยิงเจ็ตแพ็กให้ระเบิดใส่พวกเดียวกัน, ยิงอาวุธให้หลุด
- ศัตรูวิ่งวน (strafe) ยิงจากระยะ, ศัตรูประชิดมีวงเตือนบนพื้นก่อนพุ่ง, ตายแล้วเหรียญเด้งเข้าหาตัว

**โลกมีชีวิต**: NPC พูดลอย ๆ (speech bubble), คุยกันเอง, หันมามองเรา, วิ่งหนีเวลามีการต่อสู้, หุ่นยนต์ทำความสะอาด, โดรนโฆษณาบินพร้อมไฟส่อง, ยานบินผ่านนอกหน้าต่าง, เสียงบรรยากาศ

**ระบบหลักเดิม**: Tag Engine · Causality Graph (พยานวิทยุแจ้ง, ฆ่า/ติดสินบน/ขู่ก่อนแจ้งเสร็จ = ข่าวไม่แพร่) · ดาวสุ่ม 4 ชั้น · เหตุการณ์อวกาศ · ชื่อเสียง 5 บริษัท · ลูกเรือทรยศได้ · Flaw & Perk · ค่าอากาศหายใจ

## เปิดโปรเจกต์ (พัฒนาต่อ)
- แท็บเล็ต: Godot Engine 4.7+ (Android) → Import โฟลเดอร์ repo — ขั้นตอนเต็ม: **[docs/TABLET_WORKFLOW.md](docs/TABLET_WORKFLOW.md)**
- PC: `git clone https://github.com/teelopnee/Odd-Space.git` แล้วเปิดด้วย Godot 4.7+

## โครงสร้าง
```
data/            ออกแบบเกมด้วย JSON (ศัตรู, แท็ก, ดาว, เหตุการณ์, ลูกเรือ, บทพูด NPC ...)
src/autoload/    ระบบหลัก: Game, Causality, Factions, Origin, Crew, FlawPerk, Encounters, ShipAI, Audio, Router
src/actors/      Player, Enemy (BREAK/subsystems), NPC, Projectile, Pickup, BillboardSprite (8 ทิศ)
src/world/       LevelBuilder (ASCII → ฉาก 3D), Level, Station (คัตซีนเปิดเกม), Planet (ลงจอด), CameraRig, Critter
src/ui/          HUD, ปุ่มสัมผัส, เมนู, สร้างตัวละคร, แผนที่ดาว
tools/           sprite_forge.py · gen_textures.py · gen_fx.py · gen_audio.py · ตรวจโปรเจกต์/ถ่ายภาพอัตโนมัติ
```
แก้ด่านสถานีได้ที่ตัวอักษรใน `LAYOUT` ของ `src/world/station_prologue.gd` (สัญลักษณ์อธิบายใน `src/world/level_builder.gd`)

เอกสาร: [GDD](docs/GDD.md) · [Architecture](docs/ARCHITECTURE.md) · [Tablet workflow](docs/TABLET_WORKFLOW.md)
