import sys
from PIL import Image
img = Image.open(sys.argv[1])
img.save(sys.argv[2], format='ICO', sizes=[(256, 256)])
