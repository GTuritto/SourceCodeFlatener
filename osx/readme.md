# Project Digest Generator

This script generates a digest for a project by listing its directory structure and file contents, with support for frontend and backend files. It works with both local directories and Git repositories.

## Features
- Supports local directories and Git repositories.
- Extracts directory structure and file contents.
- Handles frontend files (JS, TS, JSX, TSX, HTML, CSS, SCSS, Vue) and backend files.
- Splits output into multiple files if it exceeds a size limit.
- Compatible with macOS and Linux.

## Requirements
- Bash (Linux/macOS)
- Git (if using a repository URL)

## Installation
1. Save the script as `generate_digest.sh`.
2. Give it execution permissions:
   ```sh
   chmod +x generate_digest.sh
   ```

## Usage
### For a Local Directory
```sh
./generate_digest.sh /path/to/project output.txt "Project Name"
```
- `/path/to/project`: The directory to scan.
- `output.txt`: Output file for the digest.
- `"Project Name"`: Optional project name.

### For a Git Repository
```sh
./generate_digest.sh https://github.com/example/repo.git output.txt "Project Name" main
```
- `https://github.com/example/repo.git`: Git repository URL.
- `main`: Branch to clone (optional).

## Output
- The script generates `output.txt` with directory structure and file contents.
- If the file exceeds **5MB**, it creates multiple parts: `output.txt`, `output_part2.txt`, etc.

## Example Output
```
# Project Digest: MyProject
Generated on: 2025-03-11
Source: /path/to/project
Project Directory: /path/to/project

# Directory Structure
[DIR] src
  [FILE] index.ts
  [FILE] styles.css
  [DIR] components
    [FILE] Button.tsx

# Files Content
## index.ts
console.log("Hello World");

## styles.css
body { font-family: Arial; }
```

## Cleanup
If using a Git repository, the script **automatically deletes** the cloned directory after execution.

## Troubleshooting
- Ensure you have `git` installed if using a repository URL.
- Check file permissions if you get a "Permission denied" error:
  ```sh
  chmod +x generate_digest.sh
  ```
- If you see `stat: illegal option -- c`, you're on macOS. The script **already detects this** and uses the correct command.

## License
MIT License
