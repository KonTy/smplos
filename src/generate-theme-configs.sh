#!/bin/bash
# smplOS Dev Tool: Generate all config files for every theme
# Reads colors.toml from each theme, expands _templates, writes results into the theme dir
# Run this whenever you change a template or add a new theme.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
THEMES_DIR="$SCRIPT_DIR/shared/themes"
TEMPLATES_DIR="$THEMES_DIR/_templates"

if [[ ! -d "$TEMPLATES_DIR" ]]; then
  echo "ERROR: Templates directory not found: $TEMPLATES_DIR"
  exit 1
fi

hex_to_rgb() {
  local hex="${1#\#}"
  printf "%d,%d,%d" "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

generate_theme() {
  local theme_dir="$1"
  local name="$(basename "$theme_dir")"
  local colors_file="$theme_dir/colors.toml"

  if [[ ! -f "$colors_file" ]]; then
    echo "  SKIP $name (no colors.toml)"
    return
  fi

  # Build sed script from colors.toml
  local sed_script
  sed_script=$(mktemp)

  while IFS='=' read -r key value; do
    key="${key//[\"\' ]/}"
    [[ $key && $key != \#* ]] || continue
    value="${value#*[\"\']}"
    value="${value%%[\"\']*}"

    printf 's|{{ %s }}|%s|g\n' "$key" "$value"
    printf 's|{{ %s_strip }}|%s|g\n' "$key" "${value#\#}"
    if [[ $value =~ ^# ]]; then
      local rgb
      rgb=$(hex_to_rgb "$value")
      echo "s|{{ ${key}_rgb }}|${rgb}|g"
    fi
  done < "$colors_file" > "$sed_script"

  # Decoration defaults (applied only if theme didn't set them)
  for pair in "rounding:10" "blur_size:6" "blur_passes:3" "opacity_active:0.92" "opacity_inactive:0.85" "term_opacity_active:1.0" "term_opacity_inactive:1.0" "popup_opacity:0.60"; do
    local dkey="${pair%%:*}" dval="${pair#*:}"
    if ! grep -q "{{ ${dkey} }}" "$sed_script"; then
      printf 's|{{ %s }}|%s|g\n' "$dkey" "$dval" >> "$sed_script"
    fi
  done

  # Expand each template into the theme directory
  local count=0
  local skipped=0
  for tpl in "$TEMPLATES_DIR"/*.tpl; do
    local filename
    filename=$(basename "$tpl" .tpl)
    sed -f "$sed_script" "$tpl" > "$theme_dir/$filename"
    count=$((count + 1))
  done

  rm "$sed_script"
  echo "  OK   $name ($count files generated)"
}

echo "Generating theme configs from templates..."
echo ""

for theme_dir in "$THEMES_DIR"/*/; do
  [[ "$(basename "$theme_dir")" == _* ]] && continue
  generate_theme "$theme_dir"
done

echo ""
echo "Done. All themes now have pre-baked config files."
