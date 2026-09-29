"""CLI entry point for cosmo-qemu-img.

This module provides the command-line interface that forwards all arguments
directly to the qemu-img binary, streaming stdin/stdout/stderr transparently.
"""

import sys
import subprocess
from . import get_base_command


def main():
    """Main CLI entry point.

    Executes the qemu-img binary with all command-line arguments,
    forwarding stdin/stdout/stderr directly to the parent process.

    Returns:
        Exit code from qemu-img.
    """
    try:
        result = subprocess.run(
            get_base_command() + sys.argv[1:],
            stdin=sys.stdin.buffer,
            stdout=sys.stdout.buffer,
            stderr=sys.stderr.buffer,
        )
        return result.returncode
    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130  # Standard exit code for SIGINT
    except Exception as e:
        print(f"Error executing qemu-img: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
