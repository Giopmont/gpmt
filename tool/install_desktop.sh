#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_NAME="gpmt"
LINUX_PREFIX="/opt/${APP_NAME}"
LINUX_BIN_LINK="/usr/local/bin/${APP_NAME}"
LINUX_DESKTOP_FILE="/usr/local/share/applications/${APP_NAME}.desktop"
LINUX_ICON_FILE="/usr/local/share/icons/hicolor/256x256/apps/${APP_NAME}.png"
MACOS_APP_NAME="${APP_NAME}.app"
MACOS_APP_TARGET="/Applications/${MACOS_APP_NAME}"
MACOS_BIN_LINK="/usr/local/bin/${APP_NAME}"

BUILD_ONLY=0
SKIP_BUILD=0

get_real_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    printf '%s\n' "${SUDO_USER}"
  else
    id -un
  fi
}

get_user_home() {
  local user="$1"
  getent passwd "${user}" | cut -d: -f6
}

usage() {
  cat <<'EOF'
Uso: ./tool/install_desktop.sh [opções]

Opções:
  --build-only   Apenas compila, sem instalar
  --skip-build   Reaproveita o build existente
  -h, --help     Mostra esta ajuda

Linux:
  Instala em /opt/gpmt
  Cria link em /usr/local/bin/gpmt
  Instala ícone e arquivo .desktop do sistema

macOS:
  Instala em /Applications/gpmt.app
  Cria link em /usr/local/bin/gpmt
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Comando obrigatório não encontrado: $1" >&2
    exit 1
  fi
}

while (($# > 0)); do
  case "$1" in
    --build-only)
      BUILD_ONLY=1
      ;;
    --skip-build)
      SKIP_BUILD=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Opção inválida: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

build_linux() {
  require_command flutter
  if ((SKIP_BUILD == 0)); then
    echo "Compilando release para Linux..."
    flutter build linux --release
  fi
}

install_linux() {
  local bundle_dir="${PROJECT_ROOT}/build/linux/x64/release/bundle"
  local desktop_source="${PROJECT_ROOT}/linux/gpmt.desktop"
  local real_user
  local user_home
  local local_app_dir
  local local_bin_link
  local local_desktop_file
  local temp_desktop

  if [[ ! -d "${bundle_dir}" ]]; then
    echo "Bundle Linux não encontrado em ${bundle_dir}" >&2
    exit 1
  fi

  real_user="$(get_real_user)"
  user_home="$(get_user_home "${real_user}")"
  local_app_dir="${user_home}/.local/share/${APP_NAME}"
  local_bin_link="${user_home}/.local/bin/${APP_NAME}"
  local_desktop_file="${user_home}/.local/share/applications/${APP_NAME}.desktop"

  sudo mkdir -p "${LINUX_PREFIX}"
  sudo rm -rf "${LINUX_PREFIX}"
  sudo mkdir -p "${LINUX_PREFIX}"
  sudo cp -a "${bundle_dir}/." "${LINUX_PREFIX}/"
  sudo chown -R root:root "${LINUX_PREFIX}"

  sudo mkdir -p "$(dirname "${LINUX_BIN_LINK}")"
  sudo ln -sfn "${LINUX_PREFIX}/${APP_NAME}" "${LINUX_BIN_LINK}"

  sudo mkdir -p "$(dirname "${LINUX_ICON_FILE}")"
  sudo cp "${PROJECT_ROOT}/assets/icon.png" "${LINUX_ICON_FILE}"

  sudo mkdir -p "$(dirname "${LINUX_DESKTOP_FILE}")"
  temp_desktop="$(mktemp)"
  sudo sed \
    -e "s|^Exec=gpmt %f$|Exec=${LINUX_PREFIX}/${APP_NAME} %f|" \
    -e "s|^Exec=gpmt --extract %f$|Exec=${LINUX_PREFIX}/${APP_NAME} --extract %f|" \
    -e "s|^Icon=.*|Icon=${APP_NAME}|" \
    "${desktop_source}" > "${temp_desktop}"
  sudo mv "${temp_desktop}" "${LINUX_DESKTOP_FILE}"
  sudo chmod 644 "${LINUX_DESKTOP_FILE}"

  if command -v update-desktop-database >/dev/null 2>&1; then
    sudo update-desktop-database /usr/local/share/applications || true
  fi

  if command -v gtk-update-icon-cache >/dev/null 2>&1 && [[ -f /usr/local/share/icons/hicolor/index.theme ]]; then
    sudo gtk-update-icon-cache -f /usr/local/share/icons/hicolor || true
  fi

  mkdir -p "${local_app_dir}" "$(dirname "${local_bin_link}")" "$(dirname "${local_desktop_file}")"
  rm -f "${local_app_dir}/${APP_NAME}"
  rm -f "${local_bin_link}"
  ln -s "${LINUX_PREFIX}/${APP_NAME}" "${local_app_dir}/${APP_NAME}"
  ln -s "${LINUX_PREFIX}/${APP_NAME}" "${local_bin_link}"
  cp "${PROJECT_ROOT}/assets/icon.png" "${local_app_dir}/icon.png"

  temp_desktop="$(mktemp)"
  sed \
    -e "s|^Exec=gpmt %f$|Exec=${LINUX_PREFIX}/${APP_NAME} %f|" \
    -e "s|^Exec=gpmt --extract %f$|Exec=${LINUX_PREFIX}/${APP_NAME} --extract %f|" \
    -e "s|^Icon=.*|Icon=${local_app_dir}/icon.png|" \
    "${desktop_source}" > "${temp_desktop}"
  mv "${temp_desktop}" "${local_desktop_file}"
  chmod 644 "${local_desktop_file}"
  chown -R "${real_user}:${real_user}" "${local_app_dir}" "$(dirname "${local_bin_link}")" "$(dirname "${local_desktop_file}")"

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${user_home}/.local/share/applications" || true
  fi

  echo "Instalação Linux concluída:"
  echo "  Binário: ${LINUX_PREFIX}/${APP_NAME}"
  echo "  Link:    ${LINUX_BIN_LINK}"
  echo "  Desktop: ${LINUX_DESKTOP_FILE}"
  echo "  User link: ${local_bin_link}"
  echo "  User desktop: ${local_desktop_file}"
}

build_macos() {
  require_command flutter
  if ((SKIP_BUILD == 0)); then
    echo "Compilando release para macOS..."
    flutter build macos --release
  fi
}

install_macos() {
  local app_bundle="${PROJECT_ROOT}/build/macos/Build/Products/Release/${MACOS_APP_NAME}"

  if [[ ! -d "${app_bundle}" ]]; then
    echo "Bundle macOS não encontrado em ${app_bundle}" >&2
    exit 1
  fi

  require_command ditto
  sudo rm -rf "${MACOS_APP_TARGET}"
  sudo ditto "${app_bundle}" "${MACOS_APP_TARGET}"

  sudo mkdir -p "$(dirname "${MACOS_BIN_LINK}")"
  sudo ln -sfn "${MACOS_APP_TARGET}/Contents/MacOS/${APP_NAME}" "${MACOS_BIN_LINK}"

  echo "Instalação macOS concluída:"
  echo "  App:  ${MACOS_APP_TARGET}"
  echo "  Link: ${MACOS_BIN_LINK}"
}

main() {
  cd "${PROJECT_ROOT}"

  case "$(uname -s)" in
    Linux)
      build_linux
      if ((BUILD_ONLY == 0)); then
        install_linux
      fi
      ;;
    Darwin)
      build_macos
      if ((BUILD_ONLY == 0)); then
        install_macos
      fi
      ;;
    *)
      echo "Sistema operacional não suportado: $(uname -s)" >&2
      exit 1
      ;;
  esac
}

main "$@"
