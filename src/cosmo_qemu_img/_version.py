"""Version information for cosmo-qemu-img package.

This module defines the version of the Python package and the upstream QEMU version
being packaged.

Versioning scheme: {QEMU_MAJOR}.{QEMU_MINOR}.{PACKAGE_PATCH}
  - QEMU_MAJOR.QEMU_MINOR: Version of upstream QEMU being packaged
  - PACKAGE_PATCH: Python package-specific updates (starts at 0 for each new QEMU version)

Examples:
  - 9.2.0: First release packaging QEMU 9.2
  - 9.2.1: Bugfix/improvement to Python packaging for QEMU 9.2
  - 10.0.0: First release packaging QEMU 10.0
"""

# Python package version
__version__ = "9.2.0"

# Git tag from https://gitlab.com/qemu-project/qemu/-/tags to build
QEMU_GIT_TAG = "v9.2.0"
