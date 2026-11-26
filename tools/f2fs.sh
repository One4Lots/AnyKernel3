# F2FS extension_list helpers, sourced by anykernel.sh (POSIX shell).
# The kernel stores at most 64 hot+cold extensions, each 1-7 bytes long.
# Compare normalized records, not a hash of sysfs headers/order/whitespace.

f2fs_message() {
  if type ak_ui_text >/dev/null 2>&1; then
    ak_ui_text "$@";
  else
    ui_print "$@";
  fi;
}

# Technical details stay in recovery.log, separate from compact status lines.
f2fs_diagnostic() {
  printf 'F2FS: %s\n' "$*" >&2;
}

f2fs_validate_records() (
  records=$(awk '
    NF != 2 || $1 !~ /^[ch]$/ || $2 !~ /^[a-zA-Z0-9_-]+$/ ||
      length($2) > 7 { bad = 1; next }
    { key = tolower($2); if (seen[key]++) bad = 1; print $1, $2; count++ }
    END { if (bad || count > 64) exit 1 }
  ') || exit 1;
  printf '%s\n' "$records" | LC_ALL=C sort;
)

f2fs_desired_records() (
  [ -r "$AKHOME/f2fs-cold.list" ] && [ -r "$AKHOME/f2fs-hot.list" ] || exit 1;
  records=$(awk '
    { sub(/#.*/, ""); gsub(/\r/, ""); if (!NF) next }
    { print (FILENAME == ARGV[1] ? "c" : "h"), $0 }
  ' "$AKHOME/f2fs-cold.list" "$AKHOME/f2fs-hot.list") || exit 1;
  [ -n "$records" ] || exit 1;
  printf '%s\n' "$records" | f2fs_validate_records;
)

f2fs_current_records() (
  # Some Android kernels expose the historical "extenstion" header typo.
  records=$(awk '
    { sub(/\r$/, ""); sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") }
    /^cold file exten(s|st)ion(s)?:$/ {
      if (cold++ || hot) bad = 1; section = "c"; next
    }
    /^hot file exten(s|st)ion(s)?:$/ {
      if (!cold || hot++) bad = 1; section = "h"; next
    }
    !NF { next }
    { if (!section) bad = 1; print section, $0 }
    END { if (bad || cold != 1 || hot != 1) exit 1 }
  ' "$1") || exit 1;
  if [ -n "$records" ]; then
    printf '%s\n' "$records" | f2fs_validate_records;
  fi;
)

# One command per write: sysfs does not accept a whole list in one write.
f2fs_write_extension() {
  printf '[%s]%s\n' "$2" "$3" > "$1";
}

f2fs_update_one() (
  list_path=$1;
  desired=$2;
  current=$(f2fs_current_records "$list_path") || {
    f2fs_diagnostic "Unrecognized list format at $list_path; left unchanged.";
    f2fs_message "[WARN] F2FS list format unsupported";
    exit 1;
  };
  if [ "$current" = "$desired" ]; then
    f2fs_diagnostic "List already updated: $list_path";
    f2fs_message "[SKIP] F2FS extensions already updated";
    exit 0;
  fi;
  [ -w "$list_path" ] || {
    f2fs_diagnostic "List is not writable: $list_path";
    f2fs_message "[WARN] F2FS list is not writable";
    exit 1;
  };

  f2fs_diagnostic "Applying extension policy to $list_path";
  f2fs_message "[INFO] Updating F2FS extension list";

  # Remove only obsolete records first, freeing slots before adding new ones.
  # Preserve matching records to minimize superblock commits/wear. On failure,
  # stop and warn; the next invocation re-reads actual state and can converge.
  failed=;
  for action in remove add; do
    if [ "$action" = remove ]; then
      source_records=$current; target_records=$desired; prefix='!';
    else
      source_records=$desired; target_records=$current; prefix=;
    fi;
    while read -r class ext; do
      [ -n "$class" ] || continue;
      if ! printf '%s\n' "$target_records" | grep -Fqx "$class $ext"; then
        if ! f2fs_write_extension "$list_path" "$class" "$prefix$ext"; then
          failed=1;
          break;
        fi;
      fi;
    done <<EOF
$source_records
EOF
    if [ "$failed" = 1 ]; then
      f2fs_diagnostic "Write failed at $list_path; list may be partially updated.";
      f2fs_message "[WARN] F2FS update stopped";
      f2fs_message "[WARN] List may be partially updated";
      exit 1;
    fi;
  done;
  actual=$(f2fs_current_records "$list_path") || {
    f2fs_diagnostic "Could not read back list at $list_path.";
    f2fs_message "[WARN] F2FS read-back failed";
    exit 1;
  };
  if [ "$actual" != "$desired" ]; then
    f2fs_diagnostic "Read-back mismatch at $list_path.";
    f2fs_message "[WARN] F2FS verification failed";
    exit 1;
  fi;
  f2fs_diagnostic "List updated and read-back verified: $list_path";
  f2fs_message "[OK] F2FS extension list updated";
)

f2fs_update_extensions() (
  desired=$(f2fs_desired_records) || {
    f2fs_diagnostic "Invalid/missing policy: unique 1-7 character entries, 64 total max; skipping.";
    f2fs_message "[WARN] Invalid or missing F2FS policy";
    exit 0;
  };
  # An unmatched glob is harmless. Only mounted filesystems expose this node;
  # no need to mount /data or require decrypted user storage in recovery.
  found=0; warnings=0;
  for list_path in /sys/fs/f2fs*/extension_list /sys/fs/f2fs*/*/extension_list; do
    [ -f "$list_path" ] || continue;
    found=$((found + 1));
    f2fs_update_one "$list_path" "$desired" || warnings=$((warnings + 1));
  done;
  if [ "$found" = 0 ]; then
    f2fs_diagnostic "No mounted F2FS extension_list exposed by this recovery.";
    f2fs_message "[SKIP] No F2FS extension list available";
  else
    f2fs_diagnostic "Filesystems checked: $found; warnings: $warnings";
  fi;
)
