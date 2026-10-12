JXR Cropping

Folder layout:

  Main.bat
  cropping.ps1

  i\   <- put HDR .jxr source files here

Finished .jxr files are written directly to this folder, beside Main.bat and cropping.ps1.
There is no output "o" folder.

Double-click Main.bat.

Choose:
  1 = 1.5:1
  2 = 1.78:1
  3 = 1.85:1
  4 = 1.9:1
  5 = 2.2:1
  6 = 2.39:1
  7 = 2.55:1
  8 = 2.76:1
  X = enter any custom X:1 ratio

You may also type a preset ratio itself at the Selection prompt.

Every .jxr directly inside i is center-cropped.
No resizing is performed.
Output filenames remain exactly unchanged.

If a same-name .jxr already exists beside the scripts, it is replaced only after the new temporary output has been successfully generated and verified for dimensions and bit depth.

The HDR path remains the same as the previously working version:
compressed-domain transcode is attempted first; if unavailable, the script uses the lossless floating-point JXR re-encode fallback.
