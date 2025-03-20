# SourceCodeFlatener

A smart tool for creating comprehensive digests of source code repositories, designed to flatten and document your codebase for easier review and sharing.

## Overview

SourceCodeFlatener is a utility that generates a flattened representation of a code repository. Available in Bash, Python, C#, and PowerShell implementations, it can process both local directories and remote Git repositories, creating a markdown document that contains the structure and content of your codebase in an easily digestible format. This tool is particularly useful for:

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

## Project Structure

The project is organized into the following directories:

```
.
├── README.md         # This documentation
├── LICENSE           # MIT License
├── bash/             # Bash implementation
│   └── CodeFlatener.sh
├── python/           # Python implementation
│   └── CodeFlatener.py
├── csharp/           # C# implementation
│   ├── CodeDigest.cs
│   └── CodeDigest.csproj
└── powershell/       # PowerShell implementation
    └── CodeFlatener.ps1
```

## Installation

Clone the repository or download the source files:

```bash
# Clone the repository
git clone https://github.com/username/SourceCodeFlatener.git
cd SourceCodeFlatener

# Make the implementation scripts executable
chmod +x bash/CodeFlatener.sh python/CodeFlatener.py
```

### Language-Specific Setup

#### Bash Implementation
No additional setup required!

#### Python Implementation
Requires Python 3.6+.

#### C# Implementation
Requires .NET 6.0+. Build the solution:

```bash
cd csharp
dotnet build
```

#### PowerShell Implementation
Requires PowerShell Core (pwsh).

## Usage

### Usage

You can also run each implementation directly:

#### Bash
```bash
./bash/CodeFlatener.sh -s <source> -o <output_file> [options]
```

#### Python
```bash
python3 python/CodeFlatener.py -s <source> -o <output_file> [options]
# or if made executable:
./python/CodeFlatener.py -s <source> -o <output_file> [options]
```

#### C#
```bash
cd csharp
dotnet run -- -s <source> -o <output_file> [options]
# or if published:
./CodeDigest -s <source> -o <output_file> [options]
```

#### PowerShell
```bash
pwsh -File powershell/CodeFlatener.ps1 -Source <source> -OutputFile <output_file> [options]
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

#### Process a local directory with Bash:
```bash
./bash/CodeFlatener.sh -s /path/to/your/project -o project_digest.md -n "My Project"
```

#### Process a remote Git repository with Python:
```bash
python3 python/CodeFlatener.py -s https://github.com/username/repo.git -o repo_digest.md -b main
```

#### Customize file patterns with C#:
```bash
dotnet csharp/bin/Debug/net6.0/CodeDigest.dll -s /path/to/project -o digest.md -i "*.py,*.js" -e "tests/*,docs/*"
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
./bash/CodeFlatener.sh -s /path/to/project -o docs/project_documentation.md -n "Project Documentation"
```

### Sharing Code with Collaborators

```bash
./bash/CodeFlatener.sh -s /path/to/module -o shared/module_code.md -i "src/*.py,tests/*.py" -e "*.pyc,__pycache__/*"
```

### Generating a Codebase Snapshot

```bash
./bash/CodeFlatener.sh -s https://github.com/username/repo.git -o snapshots/repo_$(date +%Y%m%d).md -b develop
```

### Comparing Implementation Performance

You can easily compare the performance of different implementations on the same codebase:

```bash
time ./bash/CodeFlatener.sh -s /path/to/project -o output_bash.md
time python3 python/CodeFlatener.py -s /path/to/project -o output_python.md
time dotnet csharp/bin/Debug/net6.0/CodeDigest.dll -s /path/to/project -o output_csharp.md
```

## Requirements

### Bash Implementation
- Bash shell
- Git (for cloning repositories)
- Python 3 (for relative path calculations)

### Python Implementation
- Python 3.6+
- Git (for cloning repositories)

### C# Implementation
- .NET 6.0+
- Git (for cloning repositories)

## License

MIT License - Copyright (c) 2025 Giuseppe Turitto

See [LICENSE](LICENSE) for details.
