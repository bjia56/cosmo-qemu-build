"""cosmo-qemu-img: Cosmopolitan builds of qemu-img as a Python package.

This package provides the qemu-img command-line utility built with Cosmopolitan libc,
allowing disk image creation, inspection and conversion across multiple platforms from
a single universal binary.

Example:
    >>> import cosmo_qemu_img
    >>> result = cosmo_qemu_img.run('info', 'disk.qcow2')
    >>> print(result.stdout.decode())

    >>> # Or use from command line:
    $ cosmo-qemu-img create -f qcow2 disk.qcow2 10G
"""

import asyncio
import platform
import subprocess
from pathlib import Path
from typing import List, Optional, Union

from ._version import __version__

__all__ = ["run", "run_async", "get_base_command", "get_binary_path"]

# Promises passed to pledge(2) when sandboxing is requested. qemu-img reads and
# writes arbitrary image files, creates new ones, locks them and may set
# their attributes.
PLEDGE_PROMISES = "stdio rpath wpath cpath flock fattr"


def get_binary_path() -> Path:
    """Get the path to the qemu-img binary.

    Linux wheels ship a native ELF (qemu-img.elf); every other platform ships
    the universal APE binary (qemu-img.com). If only the APE binary is present
    (for example when installed from an sdist), it is used on Linux too.

    Returns:
        Path object pointing to the qemu-img binary.

    Raises:
        FileNotFoundError: If the binary cannot be found.
    """
    data_dir = Path(__file__).parent / "data"
    candidates = ["qemu-img.com"]
    if platform.system() == "Linux":
        candidates.insert(0, "qemu-img.elf")
    for name in candidates:
        binary_path = data_dir / name
        if binary_path.exists():
            return binary_path
    raise FileNotFoundError(
        f"qemu-img binary not found in {data_dir}. "
        "The package may not be properly installed."
    )


def get_pledge_path() -> Path:
    """Get the path to the pledge binary.

    Returns:
        Path object pointing to the pledge binary.

    Raises:
        FileNotFoundError: If the pledge binary cannot be found.
    """
    if platform.system() != "Linux":
        raise FileNotFoundError("pledge binary is only available on Linux systems.")

    pledge_path = Path(__file__).parent / "data" / "pledge"
    if pledge_path.exists():
        return pledge_path
    raise FileNotFoundError(
        f"pledge binary not found at {pledge_path}. "
        "The package may not be properly installed."
    )


def get_base_command(pledge: bool = False) -> List[str]:
    """Get the base command to execute the qemu-img binary.

    Args:
        pledge: If True, sandbox qemu-img with pledge(2) on Linux. This is
                experimental and has no effect on other platforms.

    Returns:
        List of command components to execute the binary.
    """
    binary = get_binary_path()
    if platform.system() == "Windows":
        return [str(binary)]
    if binary.suffix == ".elf":
        if pledge:
            return [
                "sh",
                str(get_pledge_path()), "-V", "-p", PLEDGE_PROMISES,
                str(binary),
            ]
        return [str(binary)]
    # APE binaries need sh to bootstrap on Linux (without binfmt_misc) and macOS
    return ["sh", str(binary)]


def _stdin_bytes(stdin: Optional[Union[str, bytes]]) -> Optional[bytes]:
    if stdin is None:
        return None
    return stdin.encode() if isinstance(stdin, str) else stdin


def run(
    *args: Union[str, Path],
    stdin: Optional[Union[str, bytes]] = None,
    capture_output: bool = True,
    check: bool = False,
    pledge: bool = False,
    **kwargs
) -> subprocess.CompletedProcess:
    """Run qemu-img with the given arguments.

    Args:
        *args: Arguments to pass to qemu-img (e.g., subcommand, options, paths).
        stdin: Optional input to pass to stdin (str or bytes).
        capture_output: If True, capture stdout and stderr. If False, they go to
                       the parent process streams.
        check: If True, raise CalledProcessError if the command returns non-zero.
        pledge: If True, sandbox qemu-img with pledge(2) on Linux (experimental).
                Has no effect on other platforms.
        **kwargs: Additional keyword arguments to pass to subprocess.run().

    Returns:
        CompletedProcess instance with returncode, stdout, stderr attributes.

    Raises:
        FileNotFoundError: If the qemu-img binary cannot be found.
        subprocess.CalledProcessError: If check=True and command fails.

    Example:
        >>> result = cosmo_qemu_img.run('--version')
        >>> print(result.stdout.decode())

        >>> cosmo_qemu_img.run('create', '-f', 'qcow2', 'disk.qcow2', '10G', check=True)
        >>> result = cosmo_qemu_img.run('info', '--output=json', 'disk.qcow2')
    """
    cmd = get_base_command(pledge=pledge) + [str(arg) for arg in args]
    return subprocess.run(
        cmd,
        input=_stdin_bytes(stdin),
        capture_output=capture_output,
        check=check,
        **kwargs
    )


async def run_async(
    *args: Union[str, Path],
    stdin: Optional[Union[str, bytes]] = None,
    capture_output: bool = True,
    check: bool = False,
    pledge: bool = False,
    **kwargs
) -> subprocess.CompletedProcess:
    """Async version of run(). Run qemu-img with the given arguments.

    Args:
        *args: Arguments to pass to qemu-img (e.g., subcommand, options, paths).
        stdin: Optional input to pass to stdin (str or bytes).
        capture_output: If True, capture stdout and stderr. If False, they go to
                       the parent process streams.
        check: If True, raise CalledProcessError if the command returns non-zero.
        pledge: If True, sandbox qemu-img with pledge(2) on Linux (experimental).
                Has no effect on other platforms.
        **kwargs: Additional keyword arguments to pass to asyncio.create_subprocess_exec().

    Returns:
        CompletedProcess instance with returncode, stdout, stderr attributes.

    Raises:
        FileNotFoundError: If the qemu-img binary cannot be found.
        subprocess.CalledProcessError: If check=True and command fails.
    """
    cmd = get_base_command(pledge=pledge) + [str(arg) for arg in args]
    stdin_input = _stdin_bytes(stdin)

    stdout = asyncio.subprocess.PIPE if capture_output else None
    stderr = asyncio.subprocess.PIPE if capture_output else None

    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdin=asyncio.subprocess.PIPE if stdin_input is not None else None,
        stdout=stdout,
        stderr=stderr,
        **kwargs
    )
    out, err = await proc.communicate(stdin_input)

    completed = subprocess.CompletedProcess(cmd, proc.returncode, out, err)
    if check:
        completed.check_returncode()
    return completed
