# สรุปการปรับ UI/UX + Permission (กลุ่มงาน, คลังไฟล์, ตารางงาน, คลังรหัสผ่าน)

**อัปเดต:** บทบาทปัจจุบัน — แอดมิน, ผู้จัดการ, หัวหน้าพนักงานประจำ, พนักงานประจำ, พนักงานออนไลน์  
หัวหน้าพนักงานประจำเห็นทุกแผนกเหมือนผู้จัดการ; แก้ไข user ได้เฉพาะ instructor/staff ในแผนกตัวเอง  
กลุ่มงาน: ฟอร์มเว็บ+แผนก, การ์ด+กรอง; จัดการสมาชิกมี pagination (20/50/100/200/500)

## ไฟล์ที่แก้ + เหตุผลสั้น ๆ

### 1) ลบเมนู "ลงเวลา"
| ไฟล์ | การเปลี่ยนแปลง |
|------|-----------------|
| `frontend/src/pages/History.tsx` | เปลี่ยน label ตัวกรองจาก "ลงเวลา" เป็น "เข้างาน/ออกงาน" (เมนูลงเวลาถูกลบแล้ว แต่ประวัติยังมี entity work_logs) |
| หมายเหตุ | Nav, App, Dashboard ไม่มีลิงก์/route ลงเวลาอยู่แล้ว (ทำในรอบก่อน) |

### 2) Modal มาตรฐาน (ใหญ่ขึ้น, sticky header/footer, body เลื่อนได้)
| ไฟล์ | การเปลี่ยนแปลง |
|------|-----------------|
| `frontend/src/components/ui/PageModal.tsx` | **ใหม่** — Modal ความกว้าง max-w-4xl, sticky header (ชื่อ + ปิด), sticky footer (ยกเลิก/บันทึก), body มี max-height + overflow auto ใช้ class okace-scroll |
| `frontend/src/pages/GroupLinks.tsx` | ใช้ PageModal แทน Modal, ฟอร์ม 2 คอลัมน์, section "สิทธิ์การมองเห็น" + MultiSelect แบบ searchable + สรุป chips |
| `frontend/src/pages/ScheduleCards.tsx` | ใช้ PageModal แทน Modal, ฟอร์ม 2 คอลัมน์, section สิทธิ์การมองเห็น + searchable MultiSelect |
| `frontend/src/pages/PhotoVault.tsx` | ใช้ PageModal แทน Modal สำหรับอัปโหลด, section สิทธิ์การมองเห็น + searchable MultiSelect, ปุ่มอัปโหลด disabled เมื่อไม่มีไฟล์ (ใช้ footer กำหนดเอง) |
| `frontend/src/pages/PasswordVault.tsx` | ใช้ PageModal แทน Modal, ฟอร์ม 2 คอลัมน์ |

### 3) Scrollbar Dark Gold
| ไฟล์ | การเปลี่ยนแปลง |
|------|-----------------|
| `frontend/src/index.css` | เพิ่ม class `.okace-scroll` — Webkit + Firefox scrollbar (thumb โทนทอง, track มืด) |
| `frontend/src/components/Layout.tsx` | เพิ่ม `okace-scroll` ให้ main content area |

### 4) ตารางงาน — แสดงชื่อสาขา (ไม่ใช่ UID)
| ไฟล์ | การเปลี่ยนแปลง |
|------|-----------------|
| `frontend/src/pages/ScheduleCards.tsx` | คอลัมน์สาขา: แสดง `branch?.name ?? (card.branch_id ? '(ไม่พบสาขา)' : '—')` (เดิมมี join branch อยู่แล้ว) |

### 5) คลังรหัสผ่าน — Permission + UI
| ไฟล์ | การเปลี่ยนแปลง |
|------|-----------------|
| `supabase/sql/migrations/027_password_vault_instructor_head_see_all.sql` | **ใหม่** — RLS SELECT อนุญาตให้ `instructor_head` เห็นทุกแถว (แก้ไขได้เฉพาะของตัวเองอยู่แล้วจาก 024) |
| `frontend/src/lib/vaultPermissions.ts` | **ใหม่** — ฟังก์ชันกลาง: `canSeeAllVaultEntries`, `canEditVaultEntry`, `canAddVaultEntry`, `canFilterVaultByAll` ตาม role (admin/manager เห็นและแก้ทั้งหมด, instructor_head เห็นทั้งหมดแก้เฉพาะของตัวเอง, staff/instructor เห็นและแก้เฉพาะของตัวเอง) |
| `frontend/src/lib/types.ts` | เพิ่ม `owner?: { display_name, default_branch_id }` ใน PasswordVaultItem สำหรับ join จาก profiles |
| `frontend/src/pages/PasswordVault.tsx` | ดึงข้อมูลด้วย `owner:profiles!owner_id(display_name, default_branch_id)`; Toggle "ของฉัน / ของทุกคน" (แสดงเฉพาะ role ที่เห็นทั้งหมด); คอลัมน์ "เจ้าของ" และ "แผนก" (จาก owner.display_name และ owner.default_branch_id → ชื่อสาขา); search ชื่อไซต์/ผู้ใช้/เจ้าของ; pagination; ปุ่มแก้ไข/ลบ disabled เมื่อไม่มีสิทธิ์ + ข้อความ "ดูได้อย่างเดียว"; ใช้ PageModal + header แถวเดียว (ค้นหา, filter, ปุ่มเพิ่ม) |

### 6) กลุ่มงาน / คลังไฟล์ / ตารางงาน — Header + MultiSelect แบบค้นหาได้
| ไฟล์ | การเปลี่ยนแปลง |
|------|-----------------|
| `frontend/src/components/ui/MultiSelect.tsx` | เพิ่ม prop `searchable` — ช่องค้นหาใน dropdown + filter options ตาม label, ใช้ class okace-scroll ในรายการ |
| กลุ่มงาน / คลังไฟล์ / ตารางงาน | มี header row อยู่แล้ว (ค้นหา + filters สาขา/เว็บ/ตำแหน่ง + ปุ่ม action); ใน modal ใช้ MultiSelect แบบ searchable + showChips + section สิทธิ์การมองเห็น |

---

## วิธีทดสอบ Role / Permission แบบ Step-by-Step

### สิ่งที่ต้องมี
- บัญชี 4 ระดับ: **staff**, **instructor** (หรือ instructor_head), **manager**, **admin**
- Supabase: รัน migration 027 (password_vault SELECT สำหรับ instructor_head)

### 1) เมนู "ลงเวลา"
- Login ด้วยทุก role → เปิด sidebar
- **ตรวจ**: ไม่มีเมนู "ลงเวลา" / "Timekeeping" / "clock" / "attendance"
- เปิด **ประวัติ** → ตัวกรอง entity มี "เข้างาน/ออกงาน" (ไม่ใช้คำว่า "ลงเวลา" ในเมนู)

### 2) กลุ่มงาน / คลังเก็บไฟล์ / ตารางงาน
- **ทุก role**: เปิดหน้า กลุ่มงาน, คลังเก็บไฟล์, ตารางงาน ได้
- **staff / instructor**: เห็นเฉพาะข้อมูลตามสิทธิ์เดิม (สาขา/เว็บที่กำหนด); ปุ่มเพิ่ม/แก้ไข/ลบ ตามสิทธิ์เดิม
- **instructor_head (หัวหน้าพนักงานประจำ)**: เห็นทุกลิงก์/ตารางงานทุกแผนกเหมือนผู้จัดการ; แก้ไข/ลบได้
- **admin / manager**: เห็นทั้งหมด, แก้ไขได้ทั้งหมด
- **Modal**: กดเพิ่ม/แก้ไข → เปิด modal ใหญ่ (max-w-4xl), header ติดบน, footer ปุ่มติดล่าง, เนื้อหาเลื่อนได้; ฟอร์ม 2 คอลัมน์บนจอใหญ่; ช่องสาขา/เว็บ/ตำแหน่ง มีค้นหา + chips
- **ตารางงาน**: คอลัมน์สาขาแสดงชื่อสาขา (ไม่ใช่ UUID); ถ้าสาขาถูกลบแสดง "(ไม่พบสาขา)"

### 3) คลังรหัสผ่าน — Permission
- **staff หรือ instructor**  
  - เห็นเฉพาะรายการที่ตัวเองสร้าง  
  - ไม่มี toggle "ของทุกคน"  
  - มีปุ่ม "เพิ่มรหัสผ่าน", แก้ไข/ลบได้เฉพาะของตัวเอง  

- **instructor_head (หัวหน้าพนักงานประจำ)**  
  - Toggle "ของฉัน" / "ของทุกคน" แสดง  
  - เลือก "ของทุกคน" → เห็นรายการของคนอื่น  
  - คอลัมน์ "เจ้าของ" และ "แผนก" แสดงชื่อและสาขาของเจ้าของ  
  - แก้ไข/ลบได้เฉพาะรายการที่ **ตัวเองสร้าง**; รายการของคนอื่นแสดง "ดูได้อย่างเดียว"  

- **manager / admin (ผู้จัดการ/ผู้ดูแลระบบ)**  
  - Toggle "ของฉัน" / "ของทุกคน" แสดง  
  - "ของทุกคน" → เห็นทุกรายการ  
  - แก้ไข/ลบได้ทุกรายการ  

### 4) Build และหน้าที่เกี่ยวข้อง
- Build ผ่าน (ถ้ามี environment): `npm run build` ใน frontend
- เปิดหน้า กลุ่มงาน, คลังเก็บไฟล์, ตารางงาน, คลังรหัสผ่าน ได้ครบ
- Scrollbar ในหน้าและใน modal เป็นโทน Dark Gold (okace-scroll)

### 5) Checklist สุดท้าย
- [ ] Build ผ่าน
- [ ] เปิดหน้า กลุ่มงาน / คลังเก็บไฟล์ / ตารางงาน / คลังรหัสผ่าน ได้ครบ
- [ ] Role matrix: staff, instructor, instructor_head, manager, admin ตรงตามข้อ 2 และ 3
- [ ] เมนู "ลงเวลา" หายทุก role, ไม่มี dead route
- [ ] Modal ใหญ่ เลื่อนได้, sticky header/footer, ฟอร์ม 2 คอลัมน์ + สิทธิ์การมองเห็นเป็น searchable multi-select + chips
