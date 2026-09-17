# SPDX-License-Identifier: GPL-2.0-only

PKG_NAME="ashipaos-dev-baseline"
PKG_VERSION="0.0.1-dev"
PKG_LICENSE="GPL-2.0-only"
PKG_SITE="https://github.com/ashipaos/ashipaos"
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="AshipaOS development baseline metadata and boot evidence service"
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  mkdir -p "${INSTALL}/usr/lib/ashipaos" "${INSTALL}/usr/lib/systemd/system"
  cp "${PKG_DIR}/scripts/initialize-dev-release" "${INSTALL}/usr/lib/ashipaos/"
  cp "${PKG_DIR}/system.d/ashipaos-dev-baseline.service" "${INSTALL}/usr/lib/systemd/system/"
}

post_install() {
  enable_service ashipaos-dev-baseline.service
}
