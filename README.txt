JXR Auto Crop v2

Folder layout:

  JXR-Auto-Crop.bat
  JXR-Auto-Crop.ps1

  i\   <- put HDR .jxr source files here
  o\   <- results appear here; created automatically if missing

Double-click JXR-Auto-Crop.bat.

Choose:
  1 = 1.90:1
  2 = 1.85:1
  3 = 2.39:1
  X = enter any custom X:1 ratio

Every .jxr directly inside i is center-cropped.
No resizing is performed.
Output filenames remain exactly unchanged.
An existing same-name file in o is replaced only after the new file is successfully generated and verified.

v2 fixes an E_HANDLE / "The handle is invalid" save error caused by carrying source metadata/color-context objects into the output frame after the decoder stream had been closed.
