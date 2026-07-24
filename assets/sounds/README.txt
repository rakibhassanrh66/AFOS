Notification sound files — drop your own audio files in here with these EXACT
filenames, and the Settings > Notification Sound picker will find and play
them automatically. No code changes needed.

  default.mp3   — played when "Default" is selected
  chime.mp3     — played when "Chime" is selected
  bell.mp3      — played when "Bell" is selected
  (none.mp3 is intentionally not used — "None" never plays anything)

Format: .mp3 (the code looks for exactly these names + extension). Keep
them short (under ~2 seconds) — this is a notification/preview sound, not
a song.

Until a file with the matching name exists here, tapping that option in
Settings saves the preference as before but plays nothing (the app tries
to play it and silently falls back if the file isn't found yet — it will
never crash or show an error for a missing sound file).

This folder is already wired into the app:
  - pubspec.yaml declares `assets/sounds/` as a Flutter asset directory.
  - lib/features/settings/presentation/settings_screen.dart plays
    AssetSource('sounds/$key.mp3') via the `audioplayers` package
    (already a dependency, already used elsewhere in this app for SOS
    voice notes) when a sound chip is tapped.

After adding/replacing a file here, a full rebuild (not just hot reload)
is required for Flutter to re-bundle the asset — hot restart is not
enough for new asset files.
