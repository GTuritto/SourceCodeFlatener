# SourceCodeFlatener

A smart tool for creating comprehensive digests of source code repositories, designed to flatten and document your codebase for easier review and sharing.

## Overview

SourceCodeFlatener is a bash-based utility that generates a flattened representation of a code repository. It can process both local directories and remote Git repositories, creating a markdown document that contains the structure and content of your codebase in an easily digestible format. This tool is particularly useful for:

- Code reviews and audits
- Documentation generation
- Sharing code snippets with collaborators
- Creating codebase snapshots for archival purposes
- Preparing code samples for tutorials or educational materials

## Features

- Process local directories or remote Git repositories
- Support for multiple file types (ps1, cs, sln, md, txt, json, xml, yaml, yml, py, js)
- Customizable file size limits to handle large files
- Intelligent file exclusion patterns to skip irrelevant content
- Output file rotation for large codebases (automatically splits into multiple parts)
- Hierarchical directory structure representation for easy navigation
- Markdown formatting for better readability
- Automatic Git repository cloning with branch selection
- Special handling for markdown files (stripping formatting when needed)
- Repository summary statistics (files analyzed, directories scanned, total size, estimated tokens)

## Installation

No installation required! Simply download the `code_digest.sh` script and make it executable:

```bash
chmod +x code_digest.sh
```

## Usage

```bash
./code_digest.sh -s <source> -o <output_file> [options]
```

### Parameters

- `-s` Source (local directory or Git repository URL)
- `-o` Output file (base name; parts will have _partN appended if rotated)
- `-n` Project name (optional, used in the digest header)
- `-f` Max file size for analysis in bytes (default: 10MB)
- `-O` Max output file size in bytes before rotating (default: 5MB)
- `-i` Include patterns (comma-separated, e.g. "*.ps1,src/*")
- `-e` Exclude patterns (comma-separated, default: "bin/*, obj/*, debug/*, release/*, node_modules/*, *.dll, *.exe, *.pdb, *.cache")
- `-b` Git branch (if cloning a repository)

### Examples

#### Process a local directory:
```bash
./code_digest.sh -s /path/to/your/project -o project_digest.md -n "My Project"
```

#### Process a remote Git repository:
```bash
./code_digest.sh -s https://github.com/username/repo.git -o repo_digest.md -b main
```

#### Customize file patterns:
```bash
./code_digest.sh -s /path/to/project -o digest.md -i "*.py,*.js" -e "tests/*,docs/*"
```

## Output Format

The generated digest follows this structure:

1. **Project Header** - Information about the project, generation date, and source
2. **Repository Summary** - Statistics including files analyzed, directories scanned, total size, and estimated tokens
3. **Directory Structure** - Hierarchical representation of directories and files
4. **Files Content** - The actual content of each file, organized by file path

For large codebases, the output will be automatically split into multiple files (part1, part2, etc.) to prevent creating excessively large documents.

## Common Use Cases

### Creating Documentation for a Project

```bash
./code_digest.sh -s /path/to/project -o docs/project_documentation.md -n "Project Documentation"
```

### Sharing Code with Collaborators

```bash
./code_digest.sh -s /path/to/module -o shared/module_code.md -i "src/*.py,tests/*.py" -e "*.pyc,__pycache__/*"
```

### Generating a Codebase Snapshot

```bash
./code_digest.sh -s https://github.com/username/repo.git -o snapshots/repo_$(date +%Y%m%d).md -b develop
```

## Requirements

- Bash shell
- Git (for cloning repositories)
- Python 3 (for relative path calculations)

## License

MIT License - Copyright (c) 2025 Giuseppe Turitto

See [LICENSE](LICENSE) for details.
