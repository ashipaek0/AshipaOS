#!/usr/bin/env bash
# Shared storage contract. Keep all producers, selector, installer and VM tests on it.
APPLIANCE_IMAGE_BYTES=$((20 * 1024 * 1024 * 1024))
INSTALL_DISK_MARGIN_BYTES=$((64 * 1024 * 1024))
MIN_INSTALL_DISK_BYTES=$((APPLIANCE_IMAGE_BYTES + INSTALL_DISK_MARGIN_BYTES))