#!/usr/bin/python3

from PIL import Image
image_out = Image.new(mode="RGB",size=(512,256))
data_out = open("output.dat", mode="rb")
for pidx in range(0,256*512):
        pix = int.from_bytes(data_out.read(1), "little");
        image_out.putpixel((pidx % 512, 255-int(pidx/512)), (pix,pix,pix));

image_out.save('output.png')
image_out.show()
