# Files

Embedded in the application using `@embedFile`:

* *.ttf - Fonts for GUI

MacOS-specific:

* Info.plist - [property list for icons, executable path, etc.](https://developer.apple.com/documentation/bundleresources/information_property_list)

Windows-specific:

* win.rc - [resource-definition script for icons and EXE properties](https://learn.microsoft.com/en-us/windows/win32/menurc/about-resource-files)


# Generating .ico for Windows

```bash
apt get install imagemagick
convert icon.png -resize 256x256 -background transparent icon.ico
```

