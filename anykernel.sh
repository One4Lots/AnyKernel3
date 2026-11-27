### AnyKernel3 Kernel Install Script
## osm0sis @ xda-developers

### AnyKernel setup
# Fill in metadata and compatibility properties before distributing a build.
# Device checking is enabled: fill device.name* or installation will abort.
properties() { '
kernel.name=Upstream Kernel
kernel.string=
kernel.version=6.14.7
kernel.toolchain=Android clang
kernel.maintainer=One4Lots@GithHub
device.name1=curtana
device.name2=
supported.versions=16-17
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=1
'; } # end properties

# miatoll uses non-slot boot; review these settings for future devices.
# Resolve the actual boot block through standard by-name paths.
BLOCK=boot;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;
NO_BLOCK_DISPLAY=1;

# Import core helpers and initialize the installer (DO NOT REMOVE).
. tools/ak3-core.sh;

# Recovery presentation uses standard ui_print, not terminal escape codes.
. "$AKHOME/tools/install-ui.sh";
ak_ui_enable_core_messages;
# The backend owns the header; retain a standalone-script fallback.
if [ "$AK_UI_METADATA_SHOWN" != 1 ]; then
  ak_ui_banner;
  ak_ui_start;
fi;

# Preserve the existing ramdisk; no ramdisk unpack/repack or patches needed.
ak_ui_stage 1 "BOOT IMAGE";
ak_ui_text "[INFO] Reading and splitting boot image";
split_boot || abort "[ERROR] Boot image preparation failed.";
ak_ui_text "[INFO] Rebuilding and writing boot image";
flash_boot || abort "[ERROR] Boot image installation failed.";
ak_ui_text "[OK] Boot image step completed";

# Optional dtbo/dtbo.img: core handles partition discovery and size checks.
# flash_boot does not flash DTBO itself (write_boot would).
ak_ui_stage 2 "DEVICE TREE OVERLAYS";
if [ -f "$AKHOME/dtbo" ] || [ -f "$AKHOME/dtbo.img" ]; then
  ak_ui_text "[INFO] Installing packaged DTBO image";
  flash_generic dtbo || abort "[ERROR] DTBO installation failed.";
  dtbo_result="[OK] DTBO image step completed";
else
  dtbo_result="[SKIP] No DTBO image packaged";
fi;
ak_ui_text "$dtbo_result";

# Best-effort tuning of mounted F2FS filesystems, independent of /data access.
ak_ui_stage 3 "F2FS EXTENSION POLICY";
ak_ui_text "[INFO] Checking mounted F2FS filesystems";
. "$AKHOME/tools/f2fs.sh";
f2fs_update_extensions;

# The backend reports completion after environment restoration and cleanup.
ak_ui_payload_done;
