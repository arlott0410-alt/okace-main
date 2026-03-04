# Cloudflare Image Resizing (Optional)

ฟีเจอร์นี้เป็น **optional** — ถ้าไม่ได้ตั้งค่า ระบบจะใช้ URL รูปเดิมทั้งหมด ไม่กระทบ flow เดิม

## การตั้งค่า

- **VITE_CF_IMAGE_BASE** (Frontend): โดเมนที่เปิด Image Resizing แล้ว (เช่น `https://your-domain.com` หรือ `your-domain.com`). ถ้าเว้นว่าง ฟังก์ชัน `buildCfImageUrl` จะคืนค่า URL เดิมเสมอ

## วิธีใช้

ใช้เฉพาะในจุดที่ต้องการให้ resize/transform รูป (ไม่แทนที่รูปทั้งระบบ):

```ts
import { buildCfImageUrl } from '@/lib/cfImage';

// รูป thumbnail ความกว้าง 200, quality 80, format webp
const thumbUrl = buildCfImageUrl(originalUrl, { width: 200, quality: 80, format: 'webp' });

// รูปขนาดคงที่
const cardUrl = buildCfImageUrl(originalUrl, { width: 400, height: 300, quality: 85 });
```

- **width / height**: จำนวนพิกเซล (ตัวเลขเท่านั้น)
- **quality**: 0–100
- **format**: `'auto' | 'webp' | 'avif' | 'jpeg' | 'png' | 'gif'`

ถ้า `VITE_CF_IMAGE_BASE` ไม่ได้ตั้งค่า `buildCfImageUrl` จะคืน `originalUrl` ทันที

## ข้อควรระวัง

- ต้องเปิด Image Resizing / Polish ใน Cloudflare Dashboard สำหรับโดเมนนั้น
- ห้ามไปแทนที่รูปเดิมทั้งระบบ — ใช้เฉพาะที่เรียก `buildCfImageUrl` เท่านั้น
