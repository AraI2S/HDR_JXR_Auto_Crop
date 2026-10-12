Cropping

Folder layout:

  Main.bat
  cropping.ps1

  i\   <- put source images here

Finished images are written directly to this folder, beside Main.bat and cropping.ps1.
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

Supported input types are detected automatically:
  .jxr
  .png
  .jpg
  .jpeg

The user workflow is identical for every supported format.
Every supported image directly inside i is center-cropped.
No resizing is performed.
Output filenames and file types remain exactly unchanged.

If a same-name output already exists beside the scripts, it is replaced only after the new temporary output has been successfully generated and verified.

JXR:
  Keeps the previously working HDR path unchanged.
  Compressed-domain transcode is attempted first.
  If unavailable, the script uses the lossless floating-point JXR re-encode fallback.

PNG:
  Uses lossless PNG encoding.
  Embedded color context/ICC information is preserved when Windows accepts it; if that optional step fails, the image is still saved through the clean lossless frame path.

JPG/JPEG:
  Uses JPEG encoding at WPF QualityLevel 100.
  JPEG is inherently lossy, so an arbitrary crop requires re-encoding and cannot guarantee pixel-identical retained regions.
  The original .jpg or .jpeg extension and filename are preserved.
