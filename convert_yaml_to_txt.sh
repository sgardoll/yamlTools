#!/bin/bash

# Set source and destination directories
SOURCE_DIR="/Users/home/Library/CloudStorage/GoogleDrive-stuart@flutterflow.io/My Drive/CONTENT/YAML Examples/flutterflow-yaml"
DEST_DIR="/Users/home/Projects/yamlTools/converted_files"

# Create the destination directory if it doesn't exist
mkdir -p "$DEST_DIR"

# Process branchio-dynamic-linking-akp5u6_yamls files
echo "Converting branchio-dynamic-linking-akp5u6_yamls files..."
for file in "$SOURCE_DIR/branchio-dynamic-linking-akp5u6_yamls/"*.yaml; do
  if [ -f "$file" ]; then
    filename=$(basename "$file")
    dest_filename="${filename%.yaml}.txt"
    cp "$file" "$DEST_DIR/$dest_filename"
    echo "Converted: $filename -> $dest_filename"
  fi
done

# Process image-to-text-a-i-detlx8_yamls files
echo "Converting image-to-text-a-i-detlx8_yamls files..."
for file in "$SOURCE_DIR/image-to-text-a-i-detlx8_yamls/"*.yaml; do
  if [ -f "$file" ]; then
    filename=$(basename "$file")
    dest_filename="${filename%.yaml}.txt"
    cp "$file" "$DEST_DIR/$dest_filename"
    echo "Converted: $filename -> $dest_filename"
  fi
done

# Process creator-checks-j887f9_yamls files
echo "Converting creator-checks-j887f9_yamls files..."
for file in "$SOURCE_DIR/creator-checks-j887f9_yamls/"*.yaml; do
  if [ -f "$file" ]; then
    filename=$(basename "$file")
    dest_filename="${filename%.yaml}.txt"
    cp "$file" "$DEST_DIR/$dest_filename"
    echo "Converted: $filename -> $dest_filename"
  fi
done

# Process any other YAML files in the root directory
echo "Converting other YAML files..."
for file in "$SOURCE_DIR/"*.yaml; do
  if [ -f "$file" ]; then
    filename=$(basename "$file")
    dest_filename="${filename%.yaml}.txt"
    cp "$file" "$DEST_DIR/$dest_filename"
    echo "Converted: $filename -> $dest_filename"
  fi
done

echo "Conversion complete! Files are in $DEST_DIR" 