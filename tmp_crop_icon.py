from PIL import Image
import os

input_path = r'c:\development\develop\aquaanalyst_ai\assets\images\app_icon.png'
output_path = r'c:\development\develop\aquaanalyst_ai\assets\images\app_icon_nav.png'

if not os.path.exists(input_path):
    print(f"Error: {input_path} not found")
    exit(1)

with Image.open(input_path) as img:
    # Get the bounding box of the non-zero transparency
    bbox = img.getbbox()
    if bbox:
        # Crop to the bounding box
        cropped_img = img.crop(bbox)
        # Save the result
        cropped_img.save(output_path)
        print(f"Successfully cropped and saved to {output_path}")
        print(f"Original size: {img.size}, Cropped size: {cropped_img.size}")
    else:
        print("Error: Image is fully transparent")
        exit(1)
