using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace SourceCodeFlatener
{
    class Program
    {
        // Default settings
        private const long DEFAULT_MAX_FILE_SIZE = 10 * 1024 * 1024; // 10 MB
        private const long DEFAULT_MAX_OUTPUT_SIZE = 5 * 1024 * 1024; // 5 MB

        private static readonly HashSet<string> SUPPORTED_FILE_EXTENSIONS = new HashSet<string>
        {
            ".ps1", ".cs", ".sln", ".md", ".txt", ".json", ".xml", ".yaml", ".yml", ".py", ".js"
        };

        private static readonly HashSet<string> DEFAULT_EXCLUDE_PATTERNS = new HashSet<string>
        {
            "bin/*", "obj/*", "debug/*", "release/*", "node_modules/*",
            "*.dll", "*.exe", "*.pdb", "*.cache"
        };

        static async Task Main(string[] args)
        {
            var options = ParseCommandLine(args);
            if (options == null)
            {
                PrintUsage();
                return;
            }

            var flattener = new SourceCodeFlatener(options);
            await flattener.ProcessAsync();
        }

        static void PrintUsage()
        {
            Console.WriteLine("SourceCodeFlatener - C# Implementation");
            Console.WriteLine("Usage: dotnet CodeDigest.dll -s <source> -o <output_file> [options]");
            Console.WriteLine();
            Console.WriteLine("Parameters:");
            Console.WriteLine("  -s, --source         Source (local directory or Git repository URL)");
            Console.WriteLine("  -o, --output         Output file (base name; parts will have _partN appended if rotated)");
            Console.WriteLine("  -n, --project-name   Project name (optional)");
            Console.WriteLine($"  -f, --max-file-size  Max file size for analysis in bytes (default: {DEFAULT_MAX_FILE_SIZE})");
            Console.WriteLine($"  -O, --max-output-size Max output file size in bytes before rotating (default: {DEFAULT_MAX_OUTPUT_SIZE})");
            Console.WriteLine("  -i, --include        Include patterns (comma-separated, e.g. \"*.ps1,src/*\")");
            Console.WriteLine("  -e, --exclude        Exclude patterns (comma-separated)");
            Console.WriteLine("  -b, --branch         Git branch (if cloning a repository)");
        }

        static Options ParseCommandLine(string[] args)
        {
            var options = new Options
            {
                MaxFileSize = DEFAULT_MAX_FILE_SIZE,
                MaxOutputSize = DEFAULT_MAX_OUTPUT_SIZE,
                ExcludePatterns = new HashSet<string>(DEFAULT_EXCLUDE_PATTERNS)
            };

            for (int i = 0; i < args.Length; i++)
            {
                string arg = args[i].ToLower();
                string nextArg = (i + 1 < args.Length) ? args[i + 1] : null;

                if (string.IsNullOrEmpty(nextArg) || nextArg.StartsWith("-"))
                    nextArg = null;

                switch (arg)
                {
                    case "-s":
                    case "--source":
                        if (nextArg != null)
                        {
                            options.Source = nextArg;
                            i++;
                        }
                        break;
                    case "-o":
                    case "--output":
                        if (nextArg != null)
                        {
                            options.Output = nextArg;
                            i++;
                        }
                        break;
                    case "-n":
                    case "--project-name":
                        if (nextArg != null)
                        {
                            options.ProjectName = nextArg;
                            i++;
                        }
                        break;
                    case "-f":
                    case "--max-file-size":
                        if (nextArg != null && long.TryParse(nextArg, out long maxFileSize))
                        {
                            options.MaxFileSize = maxFileSize;
                            i++;
                        }
                        break;
                    case "-o":
                    case "--max-output-size":
                        if (nextArg != null && long.TryParse(nextArg, out long maxOutputSize))
                        {
                            options.MaxOutputSize = maxOutputSize;
                            i++;
                        }
                        break;
                    case "-i":
                    case "--include":
                        if (nextArg != null)
                        {
                            options.IncludePatterns = new HashSet<string>(
                                nextArg.Split(',').Select(p => p.Trim()).Where(p => !string.IsNullOrWhiteSpace(p))
                            );
                            i++;
                        }
                        break;
                    case "-e":
                    case "--exclude":
                        if (nextArg != null)
                        {
                            options.ExcludePatterns = new HashSet<string>(
                                nextArg.Split(',').Select(p => p.Trim()).Where(p => !string.IsNullOrWhiteSpace(p))
                            );
                            i++;
                        }
                        break;
                    case "-b":
                    case "--branch":
                        if (nextArg != null)
                        {
                            options.Branch = nextArg;
                            i++;
                        }
                        break;
                }
            }

            // Validate required parameters
            if (string.IsNullOrEmpty(options.Source) || string.IsNullOrEmpty(options.Output))
                return null;

            // Ensure output file has an extension (default to .md if none)
            if (!Path.HasExtension(options.Output))
                options.Output += ".md";

            return options;
        }
    }

    class Options
    {
        public string Source { get; set; }
        public string Output { get; set; }
        public string ProjectName { get; set; }
        public long MaxFileSize { get; set; }
        public long MaxOutputSize { get; set; }
        public HashSet<string> IncludePatterns { get; set; } = new HashSet<string>();
        public HashSet<string> ExcludePatterns { get; set; } = new HashSet<string>();
        public string Branch { get; set; }
    }

    class OutputFile
    {
        private readonly string _basePath;
        private readonly long _maxSize;
        private readonly string _projectName;
        private int _part = 1;
        private string _currentPath;
        private readonly string _baseName;
        private readonly string _extension;
        private readonly string _directory;

        public OutputFile(string outputPath, long maxSize, string projectName)
        {
            _basePath = Path.GetFullPath(outputPath);
            _maxSize = maxSize;
            _projectName = projectName ?? "Unnamed Project";

            _directory = Path.GetDirectoryName(_basePath);
            _baseName = Path.GetFileNameWithoutExtension(_basePath);
            _extension = Path.GetExtension(_basePath);
            _currentPath = _basePath;

            // Create directory if it doesn't exist
            Directory.CreateDirectory(_directory);

            // Write initial header
            using (var writer = new StreamWriter(_currentPath, false, Encoding.UTF8))
            {
                writer.WriteLine($"# Project Digest: {_projectName}");
                writer.WriteLine($"Generated on: {DateTime.Now}");
                writer.WriteLine();
            }
        }

        private void CheckAndRotate()
        {
            if (!File.Exists(_currentPath))
                return;

            var fileInfo = new FileInfo(_currentPath);
            if (fileInfo.Length > _maxSize)
            {
                _part++;
                _currentPath = Path.Combine(_directory, $"{_baseName}_part{_part}{_extension}");

                // Write header to new part
                using (var writer = new StreamWriter(_currentPath, false, Encoding.UTF8))
                {
                    writer.WriteLine($"# Project Digest Continued: {_projectName}");
                    writer.WriteLine($"Generated on: {DateTime.Now}");
                    writer.WriteLine();
                }
            }
        }

        public void WriteLine(string line)
        {
            using (var writer = new StreamWriter(_currentPath, true, Encoding.UTF8))
            {
                writer.WriteLine(line);
            }
            CheckAndRotate();
        }

        public void WriteBlock(string block)
        {
            foreach (var line in block.Split('\n'))
            {
                WriteLine(line.TrimEnd('\r'));
            }
        }

        public string GetPath() => _currentPath;
    }

    class SourceCodeFlatener
    {
        private readonly Options _options;
        private readonly string _projectDir;
        private readonly OutputFile _outputFile;
        private readonly string _tempRepoPath;
        private int _fileCount = 0;
        private int _dirCount = 0;
        private long _totalBytes = 0;

        public SourceCodeFlatener(Options options)
        {
            _options = options;

            // Determine project directory
            if (options.Source.StartsWith("http://") || options.Source.StartsWith("https://"))
                _projectDir = _tempRepoPath = CloneRepository();
            else
            {
                if (!Directory.Exists(options.Source))
                    throw new DirectoryNotFoundException($"Directory '{options.Source}' does not exist.");
                _projectDir = Path.GetFullPath(options.Source);
            }

            // Initialize output file
            _outputFile = new OutputFile(
                options.Output,
                options.MaxOutputSize,
                options.ProjectName
            );

            // Update output file with source info
            _outputFile.WriteLine($"Source: {options.Source}");
            _outputFile.WriteLine($"Project Directory: {_projectDir}");
            _outputFile.WriteLine("");
        }

        private string CloneRepository()
        {
            Console.Error.WriteLine($"Source appears to be a URL: {_options.Source}");
            string tempPath = Path.Combine(Path.GetTempPath(), $"repo_{Guid.NewGuid()}");
            Directory.CreateDirectory(tempPath);
            
            Console.Error.WriteLine($"Cloning repository {_options.Source} into {tempPath} ...");

            string args = $"clone ";
            if (!string.IsNullOrEmpty(_options.Branch))
                args += $"--branch {_options.Branch} ";
            else
                args += "--depth=1 ";

            args += $"{_options.Source} {tempPath}";

            var processInfo = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = args,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            try
            {
                using (var process = Process.Start(processInfo))
                {
                    process.WaitForExit();
                    if (process.ExitCode != 0)
                    {
                        string error = process.StandardError.ReadToEnd();
                        throw new Exception($"Error cloning repository: {error}");
                    }
                }
            }
            catch (Exception ex)
            {
                if (Directory.Exists(tempPath))
                    Directory.Delete(tempPath, true);
                throw new Exception($"Failed to clone repository: {ex.Message}");
            }

            return tempPath;
        }

        private bool ShouldIgnore(string relPath)
        {
            // If include patterns are specified and path doesn't match any, ignore it
            if (_options.IncludePatterns.Count > 0)
            {
                bool matchFound = false;
                foreach (var pattern in _options.IncludePatterns)
                {
                    if (GlobMatch(relPath, pattern))
                    {
                        matchFound = true;
                        break;
                    }
                }
                if (!matchFound)
                    return true;
            }

            // Check if path matches any exclude pattern
            foreach (var pattern in _options.ExcludePatterns)
            {
                if (GlobMatch(relPath, pattern))
                    return true;
            }

            return false;
        }

        private bool GlobMatch(string path, string pattern)
        {
            // Convert glob pattern to regex
            string regex = "^" + Regex.Escape(pattern).Replace("\\*", ".*") + "$";
            return Regex.IsMatch(path, regex);
        }

        private string GetRelativePath(string path) =>
            Path.GetRelativePath(_projectDir, path);

        private async Task ProcessDirectoryAsync(string directory, string indent = "")
        {
            string relPath = GetRelativePath(directory);

            if (relPath == ".")
                _outputFile.WriteLine("[DIR] .");
            else
            {
                string dirName = Path.GetFileName(directory);
                _outputFile.WriteLine($"{indent}[DIR] {dirName}");
            }

            _dirCount++;

            // Process directory contents
            foreach (var item in Directory.GetFileSystemEntries(directory))
            {
                // Skip hidden files/directories
                string itemName = Path.GetFileName(item);
                if (itemName.StartsWith("."))
                    continue;

                string itemRel = GetRelativePath(item);

                // Skip the output file itself
                if (Path.GetFileName(item) == Path.GetFileName(_options.Output))
                    continue;

                // Skip ignored files/directories
                if (ShouldIgnore(itemRel))
                    continue;

                if (Directory.Exists(item))
                    await ProcessDirectoryAsync(item, $"  {indent}");
                else
                {
                    // Check if it's a supported file type
                    string ext = Path.GetExtension(item).ToLowerInvariant();
                    if (SUPPORTED_FILE_EXTENSIONS.Contains(ext))
                        _outputFile.WriteLine($"{indent}  [FILE] {itemName}");
                }
            }
        }

        private async Task ProcessFileContentsAsync(string filepath)
        {
            string relPath = GetRelativePath(filepath);
            string ext = Path.GetExtension(filepath).ToLowerInvariant();

            if (!SUPPORTED_FILE_EXTENSIONS.Contains(ext))
                return;

            // Skip files that are too large
            var fileInfo = new FileInfo(filepath);
            if (fileInfo.Length > _options.MaxFileSize)
            {
                _outputFile.WriteLine("");
                _outputFile.WriteLine($"## {relPath}");
                _outputFile.WriteLine("[File too large to process]");
                return;
            }

            _outputFile.WriteLine("");
            _outputFile.WriteLine($"## {relPath}");

            try
            {
                string content = await File.ReadAllTextAsync(filepath);

                // For markdown files, we might want to strip formatting
                if (ext == ".md")
                    content = StripMarkdown(content);

                _outputFile.WriteBlock(content);

                // Update statistics
                _fileCount++;
                _totalBytes += fileInfo.Length;
            }
            catch (Exception ex)
            {
                _outputFile.WriteLine($"[Error reading file: {ex.Message}]");
            }
        }

        private string StripMarkdown(string content)
        {
            // Remove markdown headers
            content = Regex.Replace(content, @"^#+\s*", "", RegexOptions.Multiline);
            // Remove bold: **text**
            content = Regex.Replace(content, @"\*\*([^*]+)\*\*", "$1");
            // Remove italic: *text*
            content = Regex.Replace(content, @"\*([^*]+)\*", "$1");
            // Remove underline: _text_
            content = Regex.Replace(content, @"_([^_]+)_", "$1");
            // Remove links: [text](url)
            content = Regex.Replace(content, @"\[([^\]]+)\]\([^)]*\)", "$1");
            // Remove code blocks (from ``` to ```)
            content = Regex.Replace(content, @"```.*?```", "", RegexOptions.Singleline);
            // Remove inline code: `text`
            content = Regex.Replace(content, @"`([^`]+)`", "$1");
            return content;
        }

        private string GenerateSummary()
        {
            long approxTokens = _totalBytes / 4; // Rough estimate
            return
                "Repository Summary:\n" +
                $"Files analyzed: {_fileCount}\n" +
                $"Directories scanned: {_dirCount}\n" +
                $"Total size: {_totalBytes} bytes\n" +
                $"Estimated tokens: {approxTokens}\n\n";
        }

        public async Task ProcessAsync()
        {
            try
            {
                // Write Directory Structure section
                _outputFile.WriteLine("");
                _outputFile.WriteLine("# Directory Structure");
                await ProcessDirectoryAsync(_projectDir);

                // Write Files Content section
                _outputFile.WriteLine("");
                _outputFile.WriteLine("# Files Content");

                // Walk through all files in the project
                foreach (var filepath in Directory.GetFiles(_projectDir, "*", SearchOption.AllDirectories))
                {
                    // Skip hidden files
                    string filename = Path.GetFileName(filepath);
                    if (filename.StartsWith("."))
                        continue;

                    string relPath = GetRelativePath(filepath);

                    // Skip the output file itself
                    if (Path.GetFileName(filepath) == Path.GetFileName(_options.Output))
                        continue;

                    // Skip ignored files
                    if (ShouldIgnore(relPath))
                        continue;

                    // Check if it's a supported file type
                    string ext = Path.GetExtension(filepath).ToLowerInvariant();
                    if (SUPPORTED_FILE_EXTENSIONS.Contains(ext))
                        await ProcessFileContentsAsync(filepath);
                }

                // Generate summary
                string summary = GenerateSummary();

                // Prepend summary to output file
                string tempFilePath = Path.GetTempFileName();
                try
                {
                    using (var writer = new StreamWriter(tempFilePath, false, Encoding.UTF8))
                    {
                        writer.Write(summary);
                        writer.Write(await File.ReadAllTextAsync(_outputFile.GetPath()));
                    }

                    File.Move(tempFilePath, _outputFile.GetPath(), true);
                }
                finally
                {
                    if (File.Exists(tempFilePath))
                        File.Delete(tempFilePath);
                }

                Console.Error.WriteLine($"Documentation has been generated at '{_outputFile.GetPath()}'.");
            }
            finally
            {
                // Clean up temporary repository if one was created
                if (!string.IsNullOrEmpty(_tempRepoPath) && Directory.Exists(_tempRepoPath))
                {
                    Console.Error.WriteLine($"Cleaning up temporary repository at {_tempRepoPath}");
                    Directory.Delete(_tempRepoPath, true);
                }
            }
        }
    }
}
