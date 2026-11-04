# ทำงานข้ามเครื่องด้วย GitHub (Galaxy Tab ⇄ PC ⇄ Claude Code)

Repo: https://github.com/teelopnee/Odd-Space · branch หลัก: `main`

กฎทองข้อเดียว: **`pull` ก่อนเริ่มงานทุกครั้ง, `push` ทุกครั้งที่เลิกงาน**
(Claude Code ก็ push ขึ้น repo เดียวกัน ถ้าไม่ pull ก่อนจะชนกัน)

---

## 1) ตั้งค่าครั้งแรกบนแท็บเล็ต (Termux)

1. ติดตั้ง **Termux** จาก F-Droid (เวอร์ชัน Play Store เก่าแล้ว) และ **Godot Engine 4.7+** จาก Play Store
2. เปิด Termux แล้วพิมพ์:

```bash
pkg update && pkg install -y git gh
```

```bash
termux-setup-storage
```

```bash
gh auth login
```
(เลือก GitHub.com → HTTPS → Login with a web browser)

```bash
cd ~/storage/shared/Documents && git clone https://github.com/teelopnee/Odd-Space.git
```

```bash
cd Odd-Space && git config user.name "teelopnee" && git config user.email "you@example.com" && git config core.fileMode false
```
(`core.fileMode false` กัน Android shared storage ทำให้ git เห็นทุกไฟล์ "ถูกแก้")

3. เปิด Godot (Android) → อนุญาต *All files access* → **Import** → เลือก
   `/storage/emulated/0/Documents/Odd-Space/project.godot`

## 2) ทุกวัน

ก่อนเปิด Godot:
```bash
cd ~/storage/shared/Documents/Odd-Space && bash tools/sync.sh pull
```

หลังทำงานเสร็จ (ปิด Godot ก่อนจะดีที่สุด):
```bash
cd ~/storage/shared/Documents/Odd-Space && bash tools/sync.sh "อธิบายสั้นๆ ว่าแก้อะไร"
```

`tools/sync.sh` จะ `pull --rebase` → `add` → `commit` → `push` ให้อัตโนมัติ

## 3) ไฟล์ไหนขึ้น Git / ไม่ขึ้น

| ขึ้น Git ✅ | ไม่ขึ้น ❌ (อยู่ใน `.gitignore`) |
|---|---|
| `*.gd`, `*.tscn`, `*.tres`, `data/*.json` | `.godot/` (แคช, สร้างใหม่เองทุกเครื่อง) |
| `*.import`, `*.uid` (Godot สร้าง — **ต้อง commit**) | ไฟล์ export `.apk/.aab` |
| asset: `.png`, `.wav`, `.gdshader` | |

## 4) ถ้าเจอ conflict

```bash
git status
```
- ไฟล์ `.tscn`/`.gd`: เปิดไฟล์ หา `<<<<<<<` เลือกเวอร์ชันที่ต้องการ แล้ว `git add` + `git rebase --continue`
- ยอมแพ้แล้วเอาของบน GitHub ทับของในเครื่อง (ระวัง งานในเครื่องที่ยังไม่ push จะหาย):
```bash
git fetch origin && git reset --hard origin/main
```

## 5) ทำงานกับ Claude Code

- สั่งงานใน Claude Code ได้เลย ("เพิ่มศัตรูใหม่", "แก้บั๊กกลิ้งหลบ") — Claude จะ commit + push ขึ้น `main`
- กลับมาที่แท็บเล็ต: `bash tools/sync.sh pull` แล้วเปิด Godot
- Claude อ่าน `CLAUDE.md` ใน repo เพื่อรู้ธรรมเนียมของโปรเจกต์ทุกครั้ง
