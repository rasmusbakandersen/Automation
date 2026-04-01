#!/usr/bin/env bash
# find_suspicious_files.sh
# Usage: ./find_suspicious_files.sh [start_directory]
# Default start directory is current directory

START_DIR="${1:-.}"

# List of extensions to search for (without the dot)
exts=(
  exe com msi bat cmd vbs js jse wsf ps1 dll ocx scr jar
  docm xlsm pptm doc xls ppt html htm hta pdf
  zip rar 7z iso img
)

# Build the find expression dynamically
find_expr=()
for ext in "${exts[@]}"; do
  # Add: -iname "*.ext" -o ...
  if [ "${#find_expr[@]}" -gt 0 ]; then
    find_expr+=( -o )
  fi
  find_expr+=( -iname "*.${ext}" )
done

# Run find: files (-type f) with any of the listed extensions
# The parentheses group the OR conditions properly.
find "$START_DIR" -type f \( "${find_expr[@]}" \)
