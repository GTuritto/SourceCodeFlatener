#!/usr/bin/env python3
"""
SourceCodeFlatener - Python Implementation
A tool for creating comprehensive digests of source code repositories.
"""

import os
import sys
import argparse
import subprocess
import tempfile
import shutil
import re
from pathlib import Path
from typing import List, Dict, Optional, Set, Tuple
import datetime

# Default settings
DEFAULT_MAX_FILE_SIZE = 10 * 1024 * 1024  # 10 MB
DEFAULT_MAX_OUTPUT_SIZE = 5 * 1024 * 1024  # 5 MB
DEFAULT_EXCLUDE_PATTERNS = [
    "bin/*", "obj/*", "debug/*", "release/*", "node_modules/*", 
    "*.dll", "*.exe", "*.pdb", "*.cache"
]
SUPPORTED_FILE_EXTENSIONS = {
    'ps1', 'cs', 'sln', 'md', 'txt', 'json', 'xml', 'yaml', 'yml', 'py', 'js'
}

class OutputFile:
    """Manages the output file, handling rotation when size limits are reached."""
    
    def __init__(self, output_path: str, max_size: int, project_name: str):
        self.base_path = Path(output_path)
        self.max_size = max_size
        self.project_name = project_name or "Unnamed Project"
        self.part = 1
        
        # Extract base name and extension
        self.base_name = self.base_path.stem
        self.extension = self.base_path.suffix
        self.directory = self.base_path.parent
        
        # Initialize the current output file
        self.current_path = self.base_path
        self._ensure_directory_exists()
        
        # Write initial header
        with open(self.current_path, 'w') as f:
            f.write(f"# Project Digest: {self.project_name}\n")
            f.write(f"Generated on: {datetime.datetime.now()}\n\n")
    
    def _ensure_directory_exists(self):
        """Create the output directory if it doesn't exist."""
        os.makedirs(self.directory, exist_ok=True)
    
    def _check_and_rotate(self):
        """Check if file size exceeds limit and rotate if needed."""
        if not os.path.exists(self.current_path):
            return
            
        if os.path.getsize(self.current_path) > self.max_size:
            self.part += 1
            new_path = self.directory / f"{self.base_name}_part{self.part}{self.extension}"
            self.current_path = new_path
            
            # Write header to new part
            with open(self.current_path, 'w') as f:
                f.write(f"# Project Digest Continued: {self.project_name}\n")
                f.write(f"Generated on: {datetime.datetime.now()}\n\n")
    
    def write_line(self, line: str):
        """Write a line to the output file and rotate if necessary."""
        with open(self.current_path, 'a') as f:
            f.write(line + '\n')
        self._check_and_rotate()
    
    def write_block(self, block: str):
        """Write a block of text to the output file, rotating if necessary."""
        for line in block.split('\n'):
            self.write_line(line)
    
    def get_path(self) -> str:
        """Get the current output file path."""
        return str(self.current_path)


class SourceCodeFlatener:
    """Main class for the SourceCodeFlatener tool."""
    
    def __init__(self, args):
        self.source = args.source
        self.output = args.output
        self.project_name = args.project_name
        self.max_file_size = args.max_file_size
        self.max_output_size = args.max_output_size
        self.include_patterns = args.include_patterns or []
        self.exclude_patterns = args.exclude_patterns or DEFAULT_EXCLUDE_PATTERNS
        self.branch = args.branch
        
        # Statistics
        self.file_count = 0
        self.dir_count = 0
        self.total_bytes = 0
        
        # Temporary repository directory (if cloning)
        self.temp_repo_path = None
        
        # Determine project directory
        if self.source.startswith(('http://', 'https://')):
            self.project_dir = self._clone_repository()
        else:
            if not os.path.isdir(self.source):
                print(f"Error: Directory '{self.source}' does not exist.", file=sys.stderr)
                sys.exit(1)
            self.project_dir = os.path.abspath(self.source)
        
        # Initialize output file
        self.output_file = OutputFile(
            self.output, 
            self.max_output_size, 
            self.project_name
        )
        
        # Update output file with source info
        self.output_file.write_line(f"Source: {self.source}")
        self.output_file.write_line(f"Project Directory: {self.project_dir}")
        self.output_file.write_line("")
    
    def _clone_repository(self) -> str:
        """Clone a git repository to a temporary directory."""
        print(f"Source appears to be a URL: {self.source}", file=sys.stderr)
        self.temp_repo_path = tempfile.mkdtemp(prefix="repo_")
        print(f"Cloning repository {self.source} into {self.temp_repo_path} ...", file=sys.stderr)
        
        cmd = ["git", "clone"]
        if self.branch:
            cmd.extend(["--branch", self.branch])
        else:
            cmd.append("--depth=1")
        
        cmd.extend([self.source, self.temp_repo_path])
        
        try:
            subprocess.run(cmd, check=True, capture_output=True, text=True)
        except subprocess.CalledProcessError as e:
            print(f"Error cloning repository: {e.stderr}", file=sys.stderr)
            if self.temp_repo_path and os.path.exists(self.temp_repo_path):
                shutil.rmtree(self.temp_repo_path)
            sys.exit(1)
        
        return self.temp_repo_path
    
    def _should_ignore(self, rel_path: str) -> bool:
        """Determine if a file or directory should be ignored."""
        # If include patterns are specified and path doesn't match any, ignore it
        if self.include_patterns:
            match_found = False
            for pattern in self.include_patterns:
                if self._glob_match(rel_path, pattern):
                    match_found = True
                    break
            if not match_found:
                return True
        
        # Check if path matches any exclude pattern
        for pattern in self.exclude_patterns:
            if self._glob_match(rel_path, pattern):
                return True
        
        return False
    
    def _glob_match(self, path: str, pattern: str) -> bool:
        """Match a path against a glob pattern."""
        # Convert glob patterns to regex
        regex_pattern = "^" + pattern.replace(".", "\\.").replace("*", ".*") + "$"
        return bool(re.match(regex_pattern, path))
    
    def _get_relative_path(self, path: str) -> str:
        """Get path relative to project directory."""
        return os.path.relpath(path, self.project_dir)
    
    def _process_directory(self, directory: str, indent: str = ""):
        """Process a directory, outputting its structure."""
        rel_path = self._get_relative_path(directory)
        
        if rel_path == ".":
            self.output_file.write_line("[DIR] .")
        else:
            dir_name = os.path.basename(directory)
            self.output_file.write_line(f"{indent}[DIR] {dir_name}")
        
        self.dir_count += 1
        
        # Process directory contents
        for item in os.listdir(directory):
            # Skip hidden files
            if item.startswith('.'):
                continue
            
            full_path = os.path.join(directory, item)
            item_rel = self._get_relative_path(full_path)
            
            # Skip the output file itself
            if os.path.basename(full_path) == os.path.basename(self.output):
                continue
            
            # Skip ignored files/directories
            if self._should_ignore(item_rel):
                continue
            
            if os.path.isdir(full_path):
                self._process_directory(full_path, f"  {indent}")
            else:
                # Check if it's a supported file type
                ext = os.path.splitext(item)[1][1:].lower()
                if ext in SUPPORTED_FILE_EXTENSIONS:
                    self.output_file.write_line(f"{indent}  [FILE] {item}")
    
    def _process_file_contents(self, filepath: str):
        """Process and write the contents of a file."""
        rel_path = self._get_relative_path(filepath)
        ext = os.path.splitext(filepath)[1][1:].lower()
        
        if ext not in SUPPORTED_FILE_EXTENSIONS:
            return
        
        # Skip files that are too large
        if os.path.getsize(filepath) > self.max_file_size:
            self.output_file.write_line("")
            self.output_file.write_line(f"## {rel_path}")
            self.output_file.write_line("[File too large to process]")
            return
        
        self.output_file.write_line("")
        self.output_file.write_line(f"## {rel_path}")
        
        try:
            with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
                content = f.read()
                
                # For markdown files, we might want to strip formatting
                if filepath.endswith('.md'):
                    content = self._strip_markdown(content)
                
                self.output_file.write_block(content)
                
                # Update statistics
                self.file_count += 1
                self.total_bytes += os.path.getsize(filepath)
        except Exception as e:
            self.output_file.write_line(f"[Error reading file: {str(e)}]")
    
    def _strip_markdown(self, content: str) -> str:
        """Strip basic markdown formatting from a string."""
        # Remove markdown headers
        content = re.sub(r'^#+\s*', '', content, flags=re.MULTILINE)
        # Remove bold: **text**
        content = re.sub(r'\*\*([^*]+)\*\*', r'\1', content)
        # Remove italic: *text*
        content = re.sub(r'\*([^*]+)\*', r'\1', content)
        # Remove underline: _text_
        content = re.sub(r'_([^_]+)_', r'\1', content)
        # Remove links: [text](url)
        content = re.sub(r'\[([^\]]+)\]\([^)]*\)', r'\1', content)
        # Remove code blocks (from ``` to ```)
        content = re.sub(r'```.*?```', '', content, flags=re.DOTALL)
        # Remove inline code: `text`
        content = re.sub(r'`([^`]+)`', r'\1', content)
        return content
    
    def _generate_summary(self) -> str:
        """Generate a summary of the repository analysis."""
        approx_tokens = self.total_bytes // 4  # Rough estimate
        return (
            "Repository Summary:\n"
            f"Files analyzed: {self.file_count}\n"
            f"Directories scanned: {self.dir_count}\n"
            f"Total size: {self.total_bytes} bytes\n"
            f"Estimated tokens: {approx_tokens}\n\n"
        )
    
    def process(self):
        """Process the source and generate the digest."""
        try:
            # Write Directory Structure section
            self.output_file.write_line("")
            self.output_file.write_line("# Directory Structure")
            self._process_directory(self.project_dir)
            
            # Write Files Content section
            self.output_file.write_line("")
            self.output_file.write_line("# Files Content")
            
            # Walk through all files in the project
            for root, _, files in os.walk(self.project_dir):
                for filename in files:
                    # Skip hidden files
                    if filename.startswith('.'):
                        continue
                    
                    filepath = os.path.join(root, filename)
                    rel_path = self._get_relative_path(filepath)
                    
                    # Skip the output file itself
                    if os.path.basename(filepath) == os.path.basename(self.output):
                        continue
                    
                    # Skip ignored files
                    if self._should_ignore(rel_path):
                        continue
                    
                    # Check if it's a supported file type
                    ext = os.path.splitext(filename)[1][1:].lower()
                    if ext in SUPPORTED_FILE_EXTENSIONS:
                        self._process_file_contents(filepath)
            
            # Generate summary
            summary = self._generate_summary()
            
            # Prepend summary to output file
            temp_file = tempfile.NamedTemporaryFile(mode='w', delete=False)
            temp_file_path = temp_file.name
            
            with open(temp_file_path, 'w') as temp:
                temp.write(summary)
                with open(self.output_file.get_path(), 'r') as original:
                    temp.write(original.read())
            
            shutil.move(temp_file_path, self.output_file.get_path())
            
            print(f"Documentation has been generated at '{self.output_file.get_path()}'.", file=sys.stderr)
            
        finally:
            # Clean up temporary repository if one was created
            if self.temp_repo_path and os.path.exists(self.temp_repo_path):
                print(f"Cleaning up temporary repository at {self.temp_repo_path}", file=sys.stderr)
                shutil.rmtree(self.temp_repo_path)


def main():
    """Parse arguments and run the flattener."""
    parser = argparse.ArgumentParser(
        description="SourceCodeFlatener - Python Implementation"
    )
    
    parser.add_argument(
        "-s", "--source", required=True,
        help="Source (local directory or Git repository URL)"
    )
    parser.add_argument(
        "-o", "--output", required=True,
        help="Output file (base name; parts will have _partN appended if rotated)"
    )
    parser.add_argument(
        "-n", "--project-name",
        help="Project name (optional)"
    )
    parser.add_argument(
        "-f", "--max-file-size", type=int, default=DEFAULT_MAX_FILE_SIZE,
        help=f"Max file size for analysis in bytes (default: {DEFAULT_MAX_FILE_SIZE})"
    )
    parser.add_argument(
        "-O", "--max-output-size", type=int, default=DEFAULT_MAX_OUTPUT_SIZE,
        help=f"Max output file size in bytes before rotating (default: {DEFAULT_MAX_OUTPUT_SIZE})"
    )
    parser.add_argument(
        "-i", "--include-patterns", 
        help="Include patterns (comma-separated, e.g. '*.ps1,src/*')"
    )
    parser.add_argument(
        "-e", "--exclude-patterns",
        help=f"Exclude patterns (comma-separated, default: {','.join(DEFAULT_EXCLUDE_PATTERNS)})"
    )
    parser.add_argument(
        "-b", "--branch",
        help="Git branch (if cloning a repository)"
    )
    
    args = parser.parse_args()
    
    # Process comma-separated include/exclude patterns
    if args.include_patterns:
        args.include_patterns = [p.strip() for p in args.include_patterns.split(',')]
    
    if args.exclude_patterns:
        args.exclude_patterns = [p.strip() for p in args.exclude_patterns.split(',')]
    
    # Ensure output file has an extension (default to .md if none)
    if not os.path.splitext(args.output)[1]:
        args.output += ".md"
    
    # Run the flattener
    flattener = SourceCodeFlatener(args)
    flattener.process()


if __name__ == "__main__":
    main()
