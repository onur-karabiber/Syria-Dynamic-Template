import shutil
import os

src_dir = 'src'
output_filename = 'build/Syria_Dynamic_Template'
final_miz = 'build/Syria_Dynamic_Template.miz'

# Varsa eski build'i temizle
if os.path.exists(final_miz):
    os.remove(final_miz)
if os.path.exists(f"{output_filename}.zip"):
    os.remove(f"{output_filename}.zip")

# src klasörünü zip formatında paketle
print("Paketleniyor...")
shutil.make_archive(output_filename, 'zip', src_dir)

# Uzantıyı .miz olarak değiştir
os.rename(f"{output_filename}.zip", final_miz)

print(f"Build başarılı! Dosya konumu: {final_miz}")