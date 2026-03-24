from PIL import Image
import os

input_path = r'c:\development\develop\aquaanalyst_ai\assets\images\app_icon.png'
output_path = r'c:\development\develop\aquaanalyst_ai\assets\images\app_icon_nav.png'

with Image.open(input_path) as img:
    img = img.convert("RGBA")
    data = img.getdata()
    
    new_data = []
    for item in data:
        # Calculate alpha based on luminance: Alpha = 1.5*(R+G+B) - 320
        # This matches the matrix logic used in Flutter
        r, g, b, a = item
        lum = r + g + b
        new_alpha = int(min(255, max(0, 1.5 * lum - 320)))
        
        # We want to keep the white parts as white (or original color) but set alpha
        # Actually, for the crop, simply setting anything below a threshold to transparent is enough
        new_data.append((r, g, b, new_alpha))
    
    img.putdata(new_data)
    
    # Get the bounding box of the non-transparent area
    bbox = img.getbbox()
    if bbox:
        # Add a small 2px padding to avoid tight clipping
        padding = 4
        bbox = (
            max(0, bbox[0] - padding),
            max(0, bbox[1] - padding),
            min(img.width, bbox[2] + padding),
            min(img.height, bbox[3] + padding)
        )
        
        cropped_img = img.crop(bbox)
        # Convert back to RGB or keep RGBA? PNG supports RGBA.
        # But wait, if I keep it as white on transparent, I don't need the matrix anymore in Flutter!
        # The user said "remove the navy background".
        # If I save it with transparency, I can just use Image.asset directly with a color filter simple.
        
        cropped_img.save(output_path)
        print(f"Successfully cropped and saved to {output_path}")
        print(f"Original size: {img.size}, Cropped size: {cropped_img.size}, BBox: {bbox}")
    else:
        print("Error: Could not find any non-background pixels")
        exit(1)
