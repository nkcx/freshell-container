#!/bin/bash
# Reclaims apt cache/list space after an EXTRA_PACKAGES install.
#
# Exists as a standalone root-owned script so the coder user can be granted
# NOPASSWD sudo for exactly this operation. Granting sudo for `rm` directly
# would be equivalent to granting full root.
set -e

rm -rf /var/lib/apt/lists/*
apt-get clean
