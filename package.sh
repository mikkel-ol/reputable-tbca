#!/bin/bash
# Package the Reputable addon into a zip file with a "Reputable-TBCA" folder

ADDON_NAME="Reputable-TBCA"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMP_DIR=$(mktemp -d)

mkdir -p "$TEMP_DIR/$ADDON_NAME"

# Copy all addon files
cp "$SCRIPT_DIR/$ADDON_NAME.toc" "$TEMP_DIR/$ADDON_NAME/"
cp "$SCRIPT_DIR/embeds.xml" "$TEMP_DIR/$ADDON_NAME/"
cp "$SCRIPT_DIR/$ADDON_NAME.lua" "$TEMP_DIR/$ADDON_NAME/"
cp "$SCRIPT_DIR/questDB.lua" "$TEMP_DIR/$ADDON_NAME/"
cp "$SCRIPT_DIR/variables.lua" "$TEMP_DIR/$ADDON_NAME/"
cp "$SCRIPT_DIR/Options.lua" "$TEMP_DIR/$ADDON_NAME/"
cp "$SCRIPT_DIR/gui.lua" "$TEMP_DIR/$ADDON_NAME/"
cp "$SCRIPT_DIR/changelog.txt" "$TEMP_DIR/$ADDON_NAME/"

# Copy directories
cp -r "$SCRIPT_DIR/icons" "$TEMP_DIR/$ADDON_NAME/"
cp -r "$SCRIPT_DIR/Libs" "$TEMP_DIR/$ADDON_NAME/"

# Create the zip
cd "$TEMP_DIR"
zip -r "$SCRIPT_DIR/$ADDON_NAME.zip" "$ADDON_NAME"

# Clean up
rm -rf "$TEMP_DIR"

echo "Created $ADDON_NAME.zip"
