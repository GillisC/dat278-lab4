#!/bin/bash

find . -type f -print0 | while IFS= read -r -d '' file; do

    # Detect ELF binary
    if file "$file" | grep -q "ELF"; then
        chmod +x "$file"
        echo "Binary made executable: $file"
        continue
    fi

    # Detect scripts with shebang — without reading whole binary into memory
    if head -c 2 "$file" | grep -q "^#!"; then
        chmod +x "$file"
        echo "Script made executable: $file"
    fi

done