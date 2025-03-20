#!/bin/bash

set -e

# Detect OS type
if [[ "$(uname)" == "Darwin" ]]; then
    STAT_CMD="stat -f%z"
else
    STAT_CMD="stat -c%s"
fi

# Function to write to output file and handle rotation
write_line_to_output() {
    local line="$1"
    echo "$line" >> "$CURRENT_OUTPUT_FILE"
    
    local current_size=$($STAT_CMD "$CURRENT_OUTPUT_FILE")
    if [[ $current_size -gt $MAX_OUTPUT_FILE_SIZE ]]; then
        ((FILE_PART++))
        CURRENT_OUTPUT_FILE="${BASE_OUTPUT_FILE}_part${FILE_PART}${OUTPUT_FILE_EXTENSION}"
        echo -e "# Project Digest Continued: $PROJECT_NAME (Part $FILE_PART)\nGenerated on: $(date)\n" > "$CURRENT_OUTPUT_FILE"
    fi
}

# Function to process directory structure
process_directory() {
    local dir="$1"
    local indent="$2"
    
    echo "${indent}[DIR] $(basename "$dir")"
    for item in "$dir"/*; do
        if [[ -d "$item" ]]; then
            process_directory "$item" "  $indent"
        elif [[ -f "$item" ]]; then
            local ext="${item##*.}"
            if [[ "$ext" =~ ^(ps1|cs|sln|md|txt|json|xml|yaml|yml|py|js|ts|tsx|jsx|html|css|scss|vue)$ ]]; then
                echo "${indent}  [FILE] $(basename "$item")"
            fi
        fi
    done
}

# Function to process file contents
process_file_contents() {
    local file="$1"
    local content
    content=$(cat "$file")
    
    local filename=$(basename "$file")
    echo -e "\n## $filename\n$content"
}

# Function to clone Git repository
clone_repository() {
    local repo_url="$1"
    local branch="$2"
    
    local temp_dir=$(mktemp -d)
    echo "Cloning repository $repo_url into $temp_dir ..."
    if [[ -n "$branch" ]]; then
        git clone --single-branch --branch "$branch" "$repo_url" "$temp_dir"
    else
        git clone --depth=1 "$repo_url" "$temp_dir"
    fi
    echo "$temp_dir"
}

# Main script
SOURCE="$1"
OUTPUT_FILE="$2"
PROJECT_NAME="$3"
MAX_FILE_SIZE=$((10 * 1024 * 1024))  # 10MB default
MAX_OUTPUT_FILE_SIZE=$((5 * 1024 * 1024))  # 5MB default
BRANCH="$4"

BASE_OUTPUT_FILE="${OUTPUT_FILE%.*}"
OUTPUT_FILE_EXTENSION=".${OUTPUT_FILE##*.}"
CURRENT_OUTPUT_FILE="$OUTPUT_FILE"
FILE_PART=1

# Detect if source is a Git repository
if [[ "$SOURCE" =~ ^https?:// ]]; then
    PROJECT_DIR=$(clone_repository "$SOURCE" "$BRANCH")
else
    if [[ ! -d "$SOURCE" ]]; then
        echo "Error: Directory '$SOURCE' does not exist."
        exit 1
    fi
    PROJECT_DIR="$SOURCE"
fi

# Write header
cat <<EOF > "$CURRENT_OUTPUT_FILE"
# Project Digest: $PROJECT_NAME
Generated on: $(date)
Source: $SOURCE
Project Directory: $PROJECT_DIR
EOF

# Write directory structure
write_line_to_output "\n# Directory Structure\n"
process_directory "$PROJECT_DIR" "" | while read -r line; do write_line_to_output "$line"; done

# Write file contents
write_line_to_output "\n# Files Content\n"
file_count=0
dir_count=0
total_bytes=0

while IFS= read -r -d '' file; do
    ((file_count++))
    file_size=$($STAT_CMD "$file")
    total_bytes=$((total_bytes + file_size))
    process_file_contents "$file" | while read -r line; do write_line_to_output "$line"; done
done < <(find "$PROJECT_DIR" -type f \( -name "*.ps1" -o -name "*.cs" -o -name "*.sln" -o -name "*.md" -o -name "*.txt" -o -name "*.json" -o -name "*.xml" -o -name "*.yaml" -o -name "*.yml" -o -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.tsx" -o -name "*.jsx" -o -name "*.html" -o -name "*.css" -o -name "*.scss" -o -name "*.vue" \) -print0)

dir_count=$(find "$PROJECT_DIR" -type d | wc -l)

# Write summary
summary="Repository Summary:\nFiles analyzed: $file_count\nDirectories scanned: $dir_count\nTotal size: $total_bytes bytes\n"
{ echo -e "$summary\n"; cat "$OUTPUT_FILE"; } > temp_output && mv temp_output "$OUTPUT_FILE"

# Cleanup if cloned
if [[ "$SOURCE" =~ ^https?:// ]]; then
    echo "Cleaning up temporary repository at $PROJECT_DIR"
    rm -rf "$PROJECT_DIR"
fi

echo "Documentation has been generated (possibly across multiple files starting at '$OUTPUT_FILE')."
