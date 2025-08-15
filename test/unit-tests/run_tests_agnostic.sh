#!/bin/sh

# SKU agnostic Unit Tests
# This script is designed to run unit tests that are not specific to any SKU.

print_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -h, --help      Show this help message"
    echo "  -d, --dir DIR   Set the NHC directory"
}

# Parse options using getopt
options=$(getopt -o hd: -l help,dir: -- "$@")
if [ $? -ne 0 ]; then
    print_help
    exit 1
fi

eval set -- "$options"

while true; do
    case "$1" in
        -h|--help)
            print_help
            exit 0
            ;;
        -d|--dir)
            NHC_DIR="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Unknown option: $1"
            print_help
            exit 1
            ;;
    esac
done

# Check if NHC_DIR is set and is a directory
if [ -n "$NHC_DIR" ] && [ ! -d "$NHC_DIR" ]; then
    echo "Error: Directory '$NHC_DIR' does not exist or is not a directory."
    exit 1
fi

# Set NHC_DIR if empty
script_path="$(realpath "$0")"
parent_dir="$(dirname "$script_path")"
if [ -z "$NHC_DIR" ]; then
    NHC_DIR="$(realpath "$parent_dir/../..")"
    echo "NHC_DIR not set. Using default: $NHC_DIR"
fi

# Get Common Functions for Testing
export NHC_DIR
source "$NHC_DIR/test/unit-tests/nhc-test-common.sh"

# Run Unit Tests
bats --pretty "$NHC_DIR/test/unit-tests/nhc-hardware-test.sh"