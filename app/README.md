# NiimStudio App

This Flutter application is the Android and Linux label-composition interface
for NiimStudio. The first slice previews one centered line of text for the D11
12 x 40 mm label in portrait or landscape reading orientation. Bluetooth and
printing are not implemented yet.

## Development

Use Flutter 3.47.6 or a compatible stable release:

```shell
flutter pub get
flutter analyze
flutter test
```

The Android and Linux host projects are included. Building them also requires
the platform toolchains reported by `flutter doctor -v`.

## Bundled Font

Label output uses `BarlowCondensed-Bold.ttf` from Google Fonts commit
`60824dce48f7dd28fe7d65559f2da1f6e04e585b`. Copyright belongs to The Barlow
Project Authors. The font is distributed under SIL Open Font License 1.1; see
`assets/fonts/OFL.txt`.
