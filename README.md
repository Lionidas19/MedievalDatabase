# Medieval Price Database

A normalized SQLite database of 13th–15th century English price records
(sourced from Thorold Rogers' *History of Agriculture and Prices in
England*), plus a Flutter web app for browsing, filtering, sorting and
editing it.

## Layout

```
Copy of 1270s80sDatabase.xlsx   original source spreadsheet
tools/build_normalized_db.py    rebuilds the sqlite db from the spreadsheet
app/                            the Flutter viewer/editor app
app/data/                       default database folder (source of truth)
```

## Running the app

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) and
a Chromium-based browser (**Chrome or Edge** — the app uses the browser's
File System Access API to read/write your local database folder directly,
which Firefox and Safari don't support yet).

```bash
cd app
flutter pub get
flutter run -d chrome
```

### From VS Code

1. Install the recommended extensions when prompted (Dart + Flutter), or
   install `Dart-Code.flutter` manually.
2. Open this repository's root folder in VS Code.
3. Run and Debug (`F5`) → pick **"Price Explorer (Chrome)"**.

### First run

The app will ask you to pick a folder — choose `app/data` (already included
in this repo with a sample database). The browser remembers your choice, so
you won't be asked again next time you open the app in the same browser.

That folder is always the source of truth: the app opens the most recently
saved `.sqlite` file in it, and every save writes a new timestamped file
back into the same folder (nothing is overwritten in place).

## Regenerating the database from the spreadsheet

```bash
pip install openpyxl
python tools/build_normalized_db.py
```

This reads `Copy of 1270s80sDatabase.xlsx` and rebuilds
`app/data/1270s80sDatabase_normalized.sqlite` from scratch, normalizing the
spreadsheet's flat sheets into proper dimension/junction tables with UUID
keys (counties, places, categories → subcategories → specifics, units,
sources, etc.), joined by a `price_entries` fact table.
