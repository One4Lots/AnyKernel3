# Shared OrangeFox/TWRP presentation for the backend and kernel payload.
# Partition operations and compatibility decisions remain in their own helpers.

ak_ui_emit() {
  # Encode each line separately; text is never used as a printf format string.
  printf '%s\n' "$1" | while IFS= read -r line || [ -n "$line" ]; do
    printf 'ui_print %s\nui_print\n' "$line" >> "/proc/self/fd/$OUTFD";
  done;
}

ak_ui_rule() {
  ak_ui_emit "+----------------------------------------+";
}

ak_ui_text() {
  printf '%s\n' "$*" | tr '\r\t' '  ' | fold -s -w 40 |
    while IFS= read -r line || [ -n "$line" ]; do
      ak_ui_emit "  $line";
    done;
}

ak_ui_status() (
  level=$1;
  shift;
  ak_ui_text "[$level] $*";
)

# All backend-facing wording is centralized here, including fatal checks.
ak_ui_backend_event() {
  case "$1" in
    archive_failed|tools_failed|ui_missing|payload_failed|device_unsupported|android_unsupported|system_patch_unsupported|vendor_patch_unsupported)
      ak_ui_emit " ";
      ;;
  esac;
  case "$1" in
    archive_failed)
      ak_ui_status ERROR "Unable to extract the installation ZIP.";
      ak_ui_status INFO "Download or rebuild the package.";
      ;;
    tools_failed)
      ak_ui_status ERROR "Recovery tools could not be initialized.";
      ak_ui_status INFO "Check the package and recovery compatibility.";
      ;;
    ui_missing)
      ak_ui_status ERROR "The recovery interface is missing.";
      ak_ui_status INFO "Rebuild the ZIP with tools/install-ui.sh.";
      ;;
    payload_failed)
      ak_ui_status ERROR "Installation stopped.";
      ak_ui_status INFO "Review the preceding error messages.";
      ;;
    device_unsupported)
      ak_ui_status ERROR "Device compatibility check failed.";
      ak_ui_status INFO "Use a build intended for this device.";
      ;;
    android_unsupported)
      ak_ui_status ERROR "Android version is not supported.";
      ak_ui_field "Detected" "$2";
      ak_ui_field "Supported" "$3";
      ;;
    system_patch_unsupported)
      ak_ui_status ERROR "Android security patch is not supported.";
      ak_ui_field "Detected" "$2";
      ak_ui_field "Supported" "$3";
      ;;
    vendor_patch_unsupported)
      ak_ui_status ERROR "Vendor security patch is not supported.";
      ak_ui_field "Detected" "$2";
      ak_ui_field "Supported" "$3";
      ;;
    debug_archive)
      ak_ui_status INFO "Saving installation diagnostics.";
      ak_ui_field "Destination" "$2";
      ;;
    module_data_unavailable)
      ak_ui_status WARN "Module setup skipped: /data is unavailable.";
      ;;
    module_prepare)
      ak_ui_status INFO "Preparing the systemless kernel module.";
      ;;
    module_root_missing)
      ak_ui_status SKIP "Module setup requires Magisk or KernelSU.";
      ;;
    module_install)
      ak_ui_status INFO "Installing kernel modules.";
      ;;
    *)
      # Preserve unexpected backend errors rather than silently dropping them.
      ak_ui_status ERROR "$@";
      ;;
  esac;
}

ak_ui_field() (
  # Fixed-width labels align every colon. Wrapped values retain their column.
  continued=;
  value=$(printf '%s' "${2:-Not specified}" | tr '\r\n\t' '   ');
  printf '%s\n' "$value" | fold -s -w 22 |
    while IFS= read -r line || [ -n "$line" ]; do
      if [ "$continued" = 1 ]; then
        ak_ui_emit "$(printf '%20s%s' '' "$line")";
      else
        ak_ui_emit "$(printf '  %-15s : %s' "$1" "$line")";
        continued=1;
      fi;
    done;
)

ak_ui_android() (
  version=$(file_getprop /system/build.prop ro.build.version.release 2>/dev/null);
  [ -n "$version" ] || version=$(getprop ro.build.version.release 2>/dev/null);
  printf '%s' "$version";
)

ak_ui_start() {
  ak_ui_field "Kernel Name" "$(file_getprop "$AKHOME/anykernel.sh" kernel.name)";
  ak_ui_field "Kernel Version" "$(file_getprop "$AKHOME/anykernel.sh" kernel.version)";
  ak_ui_field "Device Name" "$(getprop ro.product.device 2>/dev/null)";
  ak_ui_field "Toolchain" "$(file_getprop "$AKHOME/anykernel.sh" kernel.toolchain)";
  ak_ui_field "Android Version" "$(ak_ui_android)";
  ak_ui_field "Maintainer" "$(file_getprop "$AKHOME/anykernel.sh" kernel.maintainer)";
}

ak_ui_banner() {
  if [ -r "$AKHOME/banner" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      ak_ui_emit "$line";
    done < "$AKHOME/banner";
  else
    ak_ui_rule;
    ak_ui_emit "          KERNEL INSTALLATION";
    ak_ui_rule;
  fi;
  ak_ui_emit " ";
}

ak_ui_stage() {
  ak_ui_emit " ";
  ak_ui_emit "  [$1/3] $2";
}

ak_ui_payload_done() {
  ak_ui_emit " ";
  ak_ui_text "[INFO] Finalizing installation...";
}

ak_ui_complete() {
  # Called after cleanup: use only shell builtins, not deleted tool applets.
  ak_ui_emit " ";
  ak_ui_rule;
  ak_ui_emit "|         INSTALLATION COMPLETE          |";
  ak_ui_rule;
}

ak_ui_enable_core_messages() {
  # Source the UI again after core initialization, which defines ui_print.
  # Hooks run in the caller's shell; no flashing function is output-filtered.
  ui_print() {
    while [ "$#" -gt 0 ]; do
      case "$1" in
        "Magisk detected! Patching kernel so reflashing Magisk is not necessary...")
          ak_ui_text "[ROOT] Magisk-patched boot detected";
          ak_ui_text "[INFO] Applying Magisk compatibility handling";
          ;;
        "KernelSU detected! Setting up for kernel helper module...")
          ak_ui_text "[ROOT] KernelSU environment detected";
          ak_ui_text "[INFO] Preparing kernel helper module";
          ;;
        "dm-verity detected! Patching "*) ak_ui_text "[AVB] $1" ;;
        "Warning: "*) ak_ui_text "[WARN] $1" ;;
        *"Aborting...") ak_ui_text "[ERROR] $1" ;;
        /dev/block/*)
          # Only standalone partition paths are diagnostic-only. Never suppress
          # a line containing an explanation, warning, or error after a path.
          case "$1" in
            *[!a-zA-Z0-9_./-]*) ak_ui_text "$1" ;;
            *) printf '%s\n' "$1" >&2 ;;
          esac;
          ;;
        *) ak_ui_emit "$1" ;;
      esac;
      shift;
    done;
  }
}
