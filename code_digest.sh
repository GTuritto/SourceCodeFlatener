#!/bin/bash
set -euo pipefail

# --- Default settings ---
# Maximum size in bytes (10 MB default for file analysis; 5 MB default for output rotation)
MAX_FILE_SIZE=$((10 * 1024 * 1024))
MAX_OUTPUT_FILE_SIZE=$((5 * 1024 * 1024))
# Default exclude patterns (you can override these via command-line)
EXCLUDE_PATTERNS=("bin/*" "obj/*" "debug/*" "release/*" "node_modules/*" "*.dll" "*.exe" "*.pdb" "*.cache")
# Include patterns (if specified, only files matching one of these will be processed)
INCLUDE_PATTERNS=()

# --- Global variables for output rotation ---
FILE_PART=1
CURRENT_OUTPUT_FILE=""
BASE_OUTPUT_FILE=""
OUTPUT_FILE_EXTENSION=""
OUTPUT_FILE_DIRECTORY=""

# Temporary repository clone path (if cloning a remote repo)
TEMP_REPO_PATH=""

# --- Usage function ---
usage() {
    cat <<EOF
Usage: $0 -s <source> -o <output_file> [options]

Parameters:
  -s  Source (local directory or Git repository URL)
  -o  Output file (base name; if rotated, parts will have _partN appended). 
      The output file must have an extension; if none is provided, '.md' will be appended.
  -n  Project name (optional)
  -f  Max file size for analysis in bytes (default: ${MAX_FILE_SIZE})
  -O  Max output file size in bytes before rotating (default: ${MAX_OUTPUT_FILE_SIZE})
  -i  Include patterns (comma-separated, e.g. "*.ps1,src/*")
  -e  Exclude patterns (comma-separated, default: ${EXCLUDE_PATTERNS[*]})
  -b  Git branch (if cloning a repository)
EOF
    exit 1
}

# --- Parse command-line arguments ---
while getopts "s:o:n:f:O:i:e:b:" opt; do
    case "$opt" in
        s) SOURCE="$OPTARG" ;;
        o) OUTPUT_FILE="$OPTARG" ;;
        n) PROJECT_NAME="$OPTARG" ;;
        f) MAX_FILE_SIZE="$OPTARG" ;;
        O) MAX_OUTPUT_FILE_SIZE="$OPTARG" ;;
        i) IFS=',' read -r -a INCLUDE_PATTERNS <<< "$OPTARG" ;;
        e) IFS=',' read -r -a EXCLUDE_PATTERNS <<< "$OPTARG" ;;
        b) BRANCH="$OPTARG" ;;
        *) usage ;;
    esac
done

if [ -z "${SOURCE:-}" ] || [ -z "${OUTPUT_FILE:-}" ]; then
    usage
fi

# --- Ensure output file has an extension (default to .md if none) ---
filename=$(basename "$OUTPUT_FILE")
if [[ "$filename" != *.* ]]; then
    OUTPUT_FILE="${OUTPUT_FILE}.md"
fi

# --- Prepare output file variables ---
OUTPUT_FILE_DIR=$(dirname "$OUTPUT_FILE")
mkdir -p "$OUTPUT_FILE_DIR"
# Create absolute path for OUTPUT_FILE (without requiring the file to exist)
OUTPUT_FILE=$(cd "$OUTPUT_FILE_DIR" && pwd)/$(basename "$OUTPUT_FILE")

BASE_OUTPUT_FILE_NAME=$(basename "$OUTPUT_FILE")
# Remove extension from base name:
BASE_OUTPUT_FILE="${BASE_OUTPUT_FILE_NAME%.*}"
OUTPUT_FILE_EXTENSION=".${BASE_OUTPUT_FILE_NAME##*.}"
OUTPUT_FILE_DIRECTORY=$(dirname "$OUTPUT_FILE")
CURRENT_OUTPUT_FILE="$OUTPUT_FILE"

# --- Helper function: get relative path using Python3 ---
# Usage: relpath <target> <base>
relpath() {
    python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$1" "$2"
}

# --- Function to write a line and rotate output if needed ---
write_line_to_output() {
    local line="$1"
    echo "$line" >> "$CURRENT_OUTPUT_FILE"
    local current_size
    # macOS-compatible stat
    current_size=$(stat -f%z "$CURRENT_OUTPUT_FILE")
    if (( current_size > MAX_OUTPUT_FILE_SIZE )); then
        FILE_PART=$((FILE_PART + 1))
        CURRENT_OUTPUT_FILE="${OUTPUT_FILE_DIRECTORY}/${BASE_OUTPUT_FILE}_part${FILE_PART}${OUTPUT_FILE_EXTENSION}"
        {
            echo "# Project Digest Continued: ${PROJECT_NAME:-Unnamed Project}"
            echo "Generated on: $(date)"
        } > "$CURRENT_OUTPUT_FILE"
    fi
}

# --- Function to write a block of text (line by line) ---
write_block_to_output() {
    local block="$1"
    while IFS= read -r line; do
        write_line_to_output "$line"
    done <<< "$block"
}

# --- Function to clone a Git repository ---
clone_repository() {
    local repo_url="$1"
    local branch="${2:-}"
    TEMP_REPO_PATH=$(mktemp -d -t repo_XXXXXX)
    echo "Cloning repository $repo_url into $TEMP_REPO_PATH ..." >&2
    if [ -n "$branch" ]; then
        git clone --branch "$branch" "$repo_url" "$TEMP_REPO_PATH"
    else
        git clone --depth=1 "$repo_url" "$TEMP_REPO_PATH"
    fi
    echo "$TEMP_REPO_PATH"
}

# --- Function to strip basic markdown formatting ---
strip_markdown() {
    local content
    content="$(cat)"
    # Remove markdown headers
    content=$(echo "$content" | sed -E 's/^#+[[:space:]]*//g')
    # Remove bold: **text**
    content=$(echo "$content" | sed -E 's/\*\*([^*]+)\*\*/\1/g')
    # Remove italic: *text*
    content=$(echo "$content" | sed -E 's/\*([^*]+)\*/\1/g')
    # Remove underline: _text_
    content=$(echo "$content" | sed -E 's/_([^_]+)_/\1/g')
    # Remove links: [text](url)
    content=$(echo "$content" | sed -E 's/\[([^]]+)\]\([^)]*\)/\1/g')
    # Remove code blocks (from ``` to ```)
    content=$(echo "$content" | sed -E '/```/,/```/d')
    # Remove inline code: `text`
    content=$(echo "$content" | sed -E 's/`([^`]+)`/\1/g')
    echo "$content"
}

# --- Function to decide if a file/directory should be ignored ---
should_ignore() {
    local relpath_val="$1"
    # If include patterns are specified and relpath does not match any, ignore it.
    if [ ${#INCLUDE_PATTERNS[@]} -gt 0 ]; then
        local match_found=false
        for pattern in "${INCLUDE_PATTERNS[@]}"; do
            if [[ "$relpath_val" == $pattern ]]; then
                match_found=true
                break
            fi
        done
        if ! $match_found; then
            return 0
        fi
    fi

    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        if [[ "$relpath_val" == $pattern ]]; then
            return 0
        fi
    done
    return 1
}

# --- Function to recursively process the directory structure ---
process_directory() {
    local current_dir="$1"
    local indent="$2"
    local relpath_val
    relpath_val=$(relpath "$current_dir" "$PROJECT_DIR")
    if [ "$relpath_val" = "." ]; then
        write_line_to_output "[DIR] ."
    else
        local dir_name
        dir_name=$(basename "$current_dir")
        write_line_to_output "${indent}[DIR] $dir_name"
    fi

    # Loop over directory contents (hidden files are skipped)
    for item in "$current_dir"/*; do
        [ -e "$item" ] || continue
        local item_rel
        item_rel=$(relpath "$item" "$PROJECT_DIR")
        # Skip the output file itself
        if [ "$(basename "$item")" == "$(basename "$OUTPUT_FILE")" ]; then
            continue
        fi
        should_ignore "$item_rel" && continue

        if [ -d "$item" ]; then
            process_directory "$item" "  $indent"
        else
            # Process only allowed file types
            case "${item##*.}" in
                ps1|cs|sln|md|txt|json|xml|yaml|yml|py|js)
                    write_line_to_output "${indent}  [FILE] $(basename "$item")"
                    ;;
            esac
        fi
    done
}

# --- Function to process file contents ---
process_file_contents() {
    local filepath="$1"
    local relpath_val
    relpath_val=$(relpath "$filepath" "$PROJECT_DIR")
    # Allowed file types only:
    case "${filepath##*.}" in
        ps1|cs|sln|md|txt|json|xml|yaml|yml|py|js)
            write_line_to_output ""
            write_line_to_output "## $relpath_val"
            if [[ "$filepath" == *.md ]]; then
                content=$(cat "$filepath" | strip_markdown)
                write_block_to_output "$content"
            else
                write_block_to_output "$(cat "$filepath")"
            fi
            ;;
    esac
}

# --- Function to generate summary info ---
generate_summary() {
    local file_count="$1"
    local dir_count="$2"
    local total_bytes="$3"
    local approx_tokens=$(( total_bytes / 4 ))
    cat <<EOF
Repository Summary:
Files analyzed: $file_count
Directories scanned: $dir_count
Total size: $total_bytes bytes
Estimated tokens: $approx_tokens

EOF
}

# --- Main Execution ---

# Determine if SOURCE is a URL or a local directory
if [[ "$SOURCE" =~ ^https?:// ]]; then
    echo "Source appears to be a URL." >&2
    PROJECT_DIR=$(clone_repository "$SOURCE" "${BRANCH:-}")
else
    if [ ! -d "$SOURCE" ]; then
        echo "Error: Directory '$SOURCE' does not exist." >&2
        exit 1
    fi
    # Use cd + pwd to get absolute path
    PROJECT_DIR=$(cd "$SOURCE" && pwd)
fi

# Initialize output file with header
header="# Project Digest: ${PROJECT_NAME:-Unnamed Project}
Generated on: $(date)
Source: $SOURCE
Project Directory: $PROJECT_DIR

"
echo "$header" > "$CURRENT_OUTPUT_FILE"

# Write Directory Structure section
write_line_to_output ""
write_line_to_output "# Directory Structure"
process_directory "$PROJECT_DIR" ""

# Write Files Content section
write_line_to_output ""
write_line_to_output "# Files Content"
file_count=0
total_bytes=0

# Process files recursively (using find)
while IFS= read -r -d '' file; do
    # Skip the output file
    if [ "$(basename "$file")" == "$(basename "$OUTPUT_FILE")" ]; then
        continue
    fi
    local_rel=$(relpath "$file" "$PROJECT_DIR")
    should_ignore "$local_rel" && continue

    case "${file##*.}" in
        ps1|cs|sln|md|txt|json|xml|yaml|yml|py|js)
            file_count=$((file_count + 1))
            bytes=$(stat -f%z "$file")
            total_bytes=$((total_bytes + bytes))
            process_file_contents "$file"
            ;;
    esac
done < <(find "$PROJECT_DIR" -type f -print0)

# Count directories
dir_count=$(find "$PROJECT_DIR" -type d | wc -l)

# Generate summary and prepend it to the output file.
summary=$(generate_summary "$file_count" "$dir_count" "$total_bytes")
tmpfile=$(mktemp)
{
    echo "$summary"
    cat "$OUTPUT_FILE"
} > "$tmpfile"
mv "$tmpfile" "$OUTPUT_FILE"

echo "Documentation has been generated (possibly across multiple files starting at '$OUTPUT_FILE')." >&2

# Cleanup temporary clone if one was used
if [ -n "$TEMP_REPO_PATH" ]; then
    echo "Cleaning up temporary repository at $TEMP_REPO_PATH" >&2
    rm -rf "$TEMP_REPO_PATH"
fi

exit 0
