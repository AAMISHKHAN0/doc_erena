import os
from PIL import Image, ImageDraw, ImageFont

os.makedirs('verification/sample_outputs', exist_ok=True)

# 1. ID Photo Input: Portrait
def make_portrait():
    im = Image.new('RGB', (800, 1000), color='#F1F5F9')
    draw = ImageDraw.Draw(im)
    # Background subtle vignette / gradient
    for y in range(1000):
        c = int(240 - (y / 1000) * 20)
        draw.line([(0, y), (800, y)], fill=(c, c+2, c+5))
    # Head & Shoulders
    draw.ellipse([270, 220, 530, 520], fill='#475569')  # head
    draw.ellipse([340, 480, 460, 600], fill='#334155')  # neck
    draw.polygon([(180, 1000), (280, 560), (520, 560), (620, 1000)], fill='#1E293B')  # suit / shoulders
    draw.polygon([(360, 580), (440, 580), (400, 660)], fill='#FFFFFF')  # white collar
    # Facial guidelines
    draw.text((400, 350), "PORTRAIT INPUT", fill='#94A3B8', anchor="mm")
    im.save('verification/sample_outputs/01_id_photo_input.png')
    print("Saved 01_id_photo_input.png (800x1000)")

# 2. Restore Photo Input: Faded, scratched photograph
def make_faded():
    im = Image.new('RGB', (640, 480), color='#A8A090')
    draw = ImageDraw.Draw(im)
    # Faded landscape hills
    draw.polygon([(0, 480), (120, 280), (320, 360), (500, 250), (640, 480)], fill='#928A7A')
    draw.polygon([(0, 480), (200, 340), (400, 400), (640, 480)], fill='#80786A')
    # Faded sun
    draw.ellipse([450, 80, 530, 160], fill='#C4BCAC')
    # Scratches / dust specks
    draw.line([(60, 40), (110, 220)], fill='#D8D0C0', width=2)
    draw.line([(480, 50), (450, 350)], fill='#DBD4C4', width=2)
    draw.line([(240, 180), (290, 210)], fill='#DBD4C4', width=1)
    draw.point([(150, 120), (152, 121), (380, 90), (381, 91)], fill='#E5DFD2')
    draw.text((320, 200), "FADED ARCHIVAL PRINT", fill='#635D50', anchor="mm")
    im.save('verification/sample_outputs/02_restore_photo_input.png')
    print("Saved 02_restore_photo_input.png (640x480)")

# 3. Smart Erase Input: Document with Coffee Stain / Blemish
def make_blemish():
    im = Image.new('RGB', (700, 500), color='#FFFFFF')
    draw = ImageDraw.Draw(im)
    # Document header and text
    draw.rectangle([40, 40, 660, 460], outline='#E2E8F0', width=2)
    draw.text((60, 60), "PURCHASE AGREEMENT & INVOICE", fill='#0F172A')
    draw.text((60, 90), "DocErena Verified Enterprise Document", fill='#64748B')
    draw.line([(60, 115), (640, 115)], fill='#CBD5E1', width=1)
    for row, y in enumerate(range(140, 380, 30)):
        draw.text((60, y), f"Line Item {row+1}: Standard consulting and software audit services", fill='#334155')
        draw.text((560, y), f"${(row+1)*250}.00", fill='#0F172A')
    # Prominent coffee stain / unwanted blemish at (500, 380)
    draw.ellipse([460, 340, 550, 430], fill='#9A3412')  # dark brown stain
    draw.ellipse([475, 355, 535, 415], fill='#C2410C')
    draw.text((505, 385), "BLEMISH", fill='#FEF08A', anchor="mm")
    im.save('verification/sample_outputs/03_smart_erase_input.png')
    print("Saved 03_smart_erase_input.png (700x500)")

# 4a. Slide Input: Presentation slide with projector glare hotspot
def make_slide():
    im = Image.new('RGB', (960, 540), color='#1E1B4B')  # deep indigo slide bg
    draw = ImageDraw.Draw(im)
    # Title & bullets
    draw.text((60, 40), "CLOUD ARCHITECTURE ROADMAP 2027", fill='#38BDF8')
    draw.line([(60, 80), (900, 80)], fill='#6366F1', width=2)
    draw.text((80, 120), "• Offline-first resilient edge deployment", fill='#F8FAFC')
    draw.text((80, 160), "• Zero network dependency & on-device machine intelligence", fill='#F8FAFC')
    draw.text((80, 200), "• Full ISO 32000-1 PDF export compliance", fill='#F8FAFC')
    draw.text((80, 240), "• 100% data sovereignty & local cryptographic integrity", fill='#F8FAFC')
    # Diagram box
    draw.rectangle([80, 300, 420, 460], outline='#38BDF8', width=2, fill='#312E81')
    draw.text((100, 320), "CORE ENGINE (OFFLINE)", fill='#38BDF8')
    draw.text((100, 360), "Local Pixel Pipeline", fill='#E2E8F0')
    draw.text((100, 400), "Median Filter + Poisson Diffusion", fill='#E2E8F0')
    # Specular projector glare hotspot at center (680, 340)
    for r in range(120, 0, -5):
        alpha = int(255 * (1 - r / 120))
        draw.ellipse([680 - r, 340 - r, 680 + r, 340 + r], fill=(min(255, 120 + alpha), min(255, 120 + alpha), min(255, 180 + alpha)))
    draw.text((680, 340), "PROJECTOR GLARE", fill='#FFFFFF', anchor="mm")
    im.save('verification/sample_outputs/04_slide_input.png')
    print("Saved 04_slide_input.png (960x540)")

# 4b. Whiteboard Input: Dry-erase board with off-white surface and marker handwriting
def make_whiteboard():
    im = Image.new('RGB', (800, 600), color='#E2E8F0')  # grayish whiteboard surface
    draw = ImageDraw.Draw(im)
    # Board aluminum frame
    draw.rectangle([10, 10, 790, 590], outline='#94A3B8', width=6)
    # Black dry-erase marker
    draw.text((60, 50), "SPRINT 42 RETROSPECTIVE", fill='#1E293B')
    draw.line([(60, 85), (550, 85)], fill='#1E293B', width=3)
    # Blue dry-erase marker
    draw.text((60, 120), "WHAT WENT WELL:", fill='#2563EB')
    draw.text((80, 160), "1. Fast offline scan processing", fill='#1D4ED8')
    draw.text((80, 200), "2. Clean native Android APK build", fill='#1D4ED8')
    # Red dry-erase marker
    draw.text((60, 260), "ACTION ITEMS & RISKS:", fill='#DC2626')
    draw.text((80, 300), "• Eliminate cloud telemetry completely", fill='#B91C1C')
    draw.text((80, 340), "• Add median scratch restoration", fill='#B91C1C')
    # Green dry-erase marker
    draw.text((60, 400), "TEAM DECISION: SHIP IT!", fill='#16A34A')
    draw.rectangle([55, 395, 450, 440], outline='#15803D', width=2)
    im.save('verification/sample_outputs/04_whiteboard_input.png')
    print("Saved 04_whiteboard_input.png (800x600)")

# 5. Greeting Card Input: Personal festive photo
def make_card_photo():
    im = Image.new('RGB', (400, 300), color='#FDE047')
    draw = ImageDraw.Draw(im)
    # Festive balloons & smiling icon
    draw.ellipse([60, 40, 160, 160], fill='#EF4444')
    draw.ellipse([140, 30, 240, 150], fill='#3B82F6')
    draw.ellipse([220, 50, 320, 170], fill='#10B981')
    draw.text((200, 230), "SMILE! FAMILY GATHERING", fill='#1E1B18', anchor="mm")
    im.save('verification/sample_outputs/05_card_photo_input.png')
    print("Saved 05_card_photo_input.png (400x300)")

make_portrait()
make_faded()
make_blemish()
make_slide()
make_whiteboard()
make_card_photo()
print("All 6 test inputs generated successfully!")
