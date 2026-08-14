#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

product_name="DshApp"
app_display_name="DeepSeek Harness"
app_name="${app_display_name}.app"
dmg_name_prefix="DeepSeek-Harness"
entitlements="$root/Packaging/DshApp.entitlements"
dist_dir="$root/dist"

# PCM 会写入编译时的绝对路径。仓库挪过目录后，旧 .build 会报
# "was compiled with module cache path ... missing required module 'SwiftShims'"。
clear_stale_module_cache() {
  local pcm
  pcm="$(find "$root/.build" -name 'SwiftShims*.pcm' -print -quit 2>/dev/null || true)"
  [[ -n "$pcm" ]] || return 0
  if grep -aFq -- "$root/.build" "$pcm"; then
    return 0
  fi
  echo "==> Stale module cache from a previous project path; cleaning ModuleCache"
  find "$root/.build" -type d -name ModuleCache -prune -exec rm -rf {} + 2>/dev/null || true
}

# 版本号优先级：环境变量 APP_VERSION > 最近的 git tag（去掉 v 前缀）> Info.plist 里的值 > 0.0.0-dev
resolve_version() {
  if [[ -n "${APP_VERSION:-}" ]]; then
    return
  fi
  if tag=$(git -C "$root" describe --tags --abbrev=0 2>/dev/null); then
    APP_VERSION="${tag#v}"
    return
  fi
  local plist_version
  plist_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$root/Packaging/Info.plist" 2>/dev/null || true)"
  if [[ -n "$plist_version" ]]; then
    APP_VERSION="$plist_version"
    return
  fi
  APP_VERSION="0.0.0-dev"
}

package_app_from_binary() {
  local build_binary="$1"
  local app_path="$2"

  local macos_dir="$app_path/Contents/MacOS"
  local resources_dir="$app_path/Contents/Resources"
  local info_plist="$app_path/Contents/Info.plist"

  rm -rf "$app_path"
  mkdir -p "$macos_dir" "$resources_dir"

  cp "$build_binary" "$macos_dir/$app_display_name"
  chmod +x "$macos_dir/$app_display_name"
  cp "$root/Packaging/Info.plist" "$info_plist"
  cp "$root/Packaging/AppIcon.icns" "$resources_dir/AppIcon.icns"
  printf 'APPL????' > "$app_path/Contents/PkgInfo"

  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$info_plist"
}

sign_app_adhoc() {
  local app_path="$1"
  codesign --force --sign - --entitlements "$entitlements" -o runtime "$app_path"
}

create_dmg() {
  local arch="$1"
  local app_path="$2"
  local dmg_path="$dist_dir/${dmg_name_prefix}-${arch}-${APP_VERSION}.dmg"
  rm -f "$dmg_path"

  local staging_dir
  staging_dir="$(mktemp -d)"
  ditto "$app_path" "$staging_dir/$app_name"
  ln -s /Applications "$staging_dir/Applications"

  hdiutil create \
    -volname "$app_display_name" \
    -srcfolder "$staging_dir" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$dmg_path" >/dev/null
  rm -rf "$staging_dir"
  echo "$dmg_path"
}

copy_to_dist() {
  local app_path="$1"
  mkdir -p "$dist_dir"
  local stable_app="$dist_dir/$app_name"
  rm -rf "$stable_app"
  ditto "$app_path" "$stable_app"
  echo "$stable_app"
}

build_local() {
  local configuration="${1:-release}"
  case "$configuration" in
    debug|Debug) configuration="debug" ;;
    *) configuration="release" ;;
  esac

  resolve_version
  clear_stale_module_cache
  swift build -c "$configuration" --product "$product_name"

  local bin_dir binary
  bin_dir="$(swift build -c "$configuration" --show-bin-path)"
  binary="$bin_dir/$product_name"
  if [[ ! -x "$binary" ]]; then
    echo "没有找到可执行文件：$binary" >&2
    exit 1
  fi

  local app_path="$bin_dir/$app_name"
  package_app_from_binary "$binary" "$app_path"
  sign_app_adhoc "$app_path"

  local stable_app
  stable_app="$(copy_to_dist "$app_path")"
  echo "Built: $stable_app"
  du -sh "$stable_app"
}

build_only() {
  local arch="${1:-universal}"
  local do_sign=0
  local do_dmg=0
  shift || true

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sign) do_sign=1 ;;
      --dmg) do_dmg=1 ;;
      *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
  done

  local build_args=(-c release --product "$product_name")
  case "$arch" in
    universal) build_args+=(--arch arm64 --arch x86_64) ;;
    arm64)     build_args+=(--arch arm64) ;;
    x86_64)    build_args+=(--arch x86_64) ;;
    *) echo "unknown arch: $arch (expected universal|arm64|x86_64)" >&2; exit 2 ;;
  esac

  resolve_version
  clear_stale_module_cache
  echo "==> Building $arch (version $APP_VERSION)"
  swift build "${build_args[@]}"

  local bin_dir binary
  bin_dir="$(swift build --show-bin-path "${build_args[@]}")"
  binary="$bin_dir/$product_name"
  if [[ ! -x "$binary" ]]; then
    echo "没有找到可执行文件：$binary" >&2
    exit 1
  fi

  local app_path="$bin_dir/$app_name"
  package_app_from_binary "$binary" "$app_path"

  if [[ $do_sign -eq 1 ]]; then
    echo "==> Ad-hoc signing"
    sign_app_adhoc "$app_path"
  fi

  local stable_app
  stable_app="$(copy_to_dist "$app_path")"

  if [[ $do_dmg -eq 1 ]]; then
    echo "==> Creating DMG"
    create_dmg "$arch" "$stable_app"
  fi

  echo "==> Done: $stable_app"
}

print_usage() {
  echo "usage: $0 [debug|release|--build-only <arch> [--sign] [--dmg]]" >&2
  echo "  arch: universal | arm64 | x86_64" >&2
}

case "${1:-release}" in
  --build-only|build-only)
    build_only "${@:2}"
    ;;
  debug|Debug|release|Release)
    build_local "${1:-release}"
    ;;
  -h|--help|help)
    print_usage
    ;;
  *)
    print_usage
    exit 2
    ;;
esac
