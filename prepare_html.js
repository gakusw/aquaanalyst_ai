const fs = require('fs');
const path = require('path');

const iconPath = path.join(__dirname, 'assets', 'images', 'app_icon.png');
const b64 = fs.readFileSync(iconPath).toString('base64');

const html = `
<!DOCTYPE html>
<html>
<body>
  <canvas id="canvas"></canvas>
  <img id="source" src="data:image/png;base64,${b64}" style="display:none;">
  <script>
    async function processIcon() {
      const img = document.getElementById('source');
      const canvas = document.getElementById('canvas');
      canvas.width = img.width;
      canvas.height = img.height;
      const ctx = canvas.getContext('2d');
      ctx.drawImage(img, 0, 0);

      const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
      const data = imageData.data;

      for (let i = 0; i < data.length; i += 4) {
        const r = data[i];
        const g = data[i + 1];
        const b = data[i + 2];
        
        // Luminance: higher is whiter
        const lum = 0.299 * r + 0.587 * g + 0.114 * b;
        
        // Make the resulting pixel pure white (for use with color filter later)
        data[i] = 255;
        data[i + 1] = 255;
        data[i + 2] = 255;
        
        // Alpha based on luminance. 
        // Navy bg has low lum, white icon has high lum.
        // Navy: roughly 0, 30, 80 -> lum ~ 30
        // White: 255, 255, 255 -> lum ~ 255
        let alpha = (lum - 100) * 2; // sharper threshold
        data[i + 3] = Math.max(0, Math.min(255, alpha));
      }

      ctx.putImageData(imageData, 0, 0);
      return canvas.toDataURL("image/png");
    }
    // Automatically run and log to console
    setTimeout(async () => {
      const result = await processIcon();
      console.log("RESULT_START" + result + "RESULT_END");
    }, 500);
  </script>
</body>
</html>
`;

fs.writeFileSync('tmp_process_icon.html', html);
console.log('HTML prepared');
