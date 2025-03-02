#!/bin/bash
set -e

# SourceCodeFlatener - Main script launcher
# This script detects the available implementations and runs the appropriate one

SCRIPT_DIR=$(dirname "$(realpath "$0")")
BASH_IMPL="${SCRIPT_DIR}/bash/code_digest.sh"
PYTHON_IMPL="${SCRIPT_DIR}/python/code_digest.py"
CSHARP_IMPL="${SCRIPT_DIR}/csharp/CodeDigest.dll"
POWERSHELL_IMPL="${SCRIPT_DIR}/powershell/code_digest.ps1"

# If no arguments provided, show usage
if [ $# -eq 0 ]; then
    echo "SourceCodeFlatener - Code Repository Digest Tool"
    echo "Usage: $0 [implementation] [options]"
    echo ""
    echo "Implementations:"
    echo "  bash       Use Bash implementation (default)"
    echo "  python     Use Python implementation"
    echo "  csharp     Use C# implementation"
    echo "  powershell Use PowerShell implementation"
    echo ""
    echo "For implementation-specific options, run with the implementation name and no options."
    echo "Example: $0 python"
    echo ""
    echo "To run directly with options, just provide the options (defaults to bash implementation):"
    echo "Example: $0 -s /path/to/source -o output.md"
    exit 1
fi

# Check if first argument is an implementation name
IMPLEMENTATION="bash"  # Default
if [[ "$1" == "bash" || "$1" == "python" || "$1" == "csharp" || "$1" == "powershell" ]]; then
    IMPLEMENTATION="$1"
    shift  # Remove the implementation argument
fi

# If no arguments left, show the implementation-specific help
if [ $# -eq 0 ]; then
    case "$IMPLEMENTATION" in
        bash)
            if [ -x "$BASH_IMPL" ]; then
                "$BASH_IMPL"
            else
                echo "Error: Bash implementation not found or not executable."
                echo "Expected at: $BASH_IMPL"
                exit 1
            fi
            ;;
        python)
            if [ -x "$PYTHON_IMPL" ]; then
                "$PYTHON_IMPL"
            elif command -v python3 &>/dev/null; then
                python3 "$PYTHON_IMPL"
            else
                echo "Error: Python implementation not found or Python not installed."
                echo "Expected at: $PYTHON_IMPL"
                exit 1
            fi
            ;;
        csharp)
            if [ -f "$CSHARP_IMPL" ] && command -v dotnet &>/dev/null; then
                dotnet "$CSHARP_IMPL"
            elif command -v dotnet &>/dev/null; then
                echo "C# implementation not built. Building now..."
                (cd "$(dirname "$CSHARP_IMPL")" && dotnet build)
                dotnet "$(dirname "$CSHARP_IMPL")/bin/Debug/net6.0/CodeDigest.dll"
            else
                echo "Error: C# implementation not found or .NET not installed."
                echo "Expected at: $CSHARP_IMPL"
                exit 1
            fi
            ;;
        powershell)
            if [ -f "$POWERSHELL_IMPL" ] && command -v pwsh &>/dev/null; then
                pwsh -File "$POWERSHELL_IMPL"
            else
                echo "Error: PowerShell implementation not found or PowerShell not installed."
                echo "Expected at: $POWERSHELL_IMPL"
                exit 1
            fi
            ;;
    esac
    exit 0
fi

# Run the selected implementation with the provided arguments
case "$IMPLEMENTATION" in
    bash)
        if [ -x "$BASH_IMPL" ]; then
            "$BASH_IMPL" "$@"
        else
            echo "Error: Bash implementation not found or not executable."
            echo "Expected at: $BASH_IMPL"
            exit 1
        fi
        ;;
    python)
        if [ -x "$PYTHON_IMPL" ]; then
            "$PYTHON_IMPL" "$@"
        elif command -v python3 &>/dev/null; then
            python3 "$PYTHON_IMPL" "$@"
        else
            echo "Error: Python implementation not found or Python not installed."
            echo "Expected at: $PYTHON_IMPL"
            exit 1
        fi
        ;;
    csharp)
        if [ -f "$CSHARP_IMPL" ] && command -v dotnet &>/dev/null; then
            dotnet "$CSHARP_IMPL" "$@"
        elif command -v dotnet &>/dev/null; then
            echo "C# implementation not built. Building now..."
            (cd "$(dirname "$CSHARP_IMPL")" && dotnet build)
            dotnet "$(dirname "$CSHARP_IMPL")/bin/Debug/net6.0/CodeDigest.dll" "$@"
        else
            echo "Error: C# implementation not found or .NET not installed."
            echo "Expected at: $CSHARP_IMPL"
            exit 1
        fi
        ;;
    powershell)
        if [ -f "$POWERSHELL_IMPL" ] && command -v pwsh &>/dev/null; then
            pwsh -File "$POWERSHELL_IMPL" "$@"
        else
            echo "Error: PowerShell implementation not found or PowerShell not installed."
            echo "Expected at: $POWERSHELL_IMPL"
            exit 1
        fi
        ;;
esac
