# AnyKernel3 for miatoll

A ramdisk-preserving kernel installer for miatoll, built on [AnyKernel3](https://github.com/osm0sis/AnyKernel3) by osm0sis. It provides optional DTBO installation, an Android-oriented F2FS extension policy, and a structured recovery interface using standard OrangeFox/TWRP-style recovery messages.

The default target is miatoll's non-slot boot partition. Supporting another device requires reviewing its partition layout, boot image format, and device-tree requirements.

## Repository layout

| Path | Purpose |
| --- | --- |
| `anykernel.sh` | Build properties, target configuration, and installation sequence |
| `banner` | Opening panel displayed above the aligned release details |
| `tools/install-ui.sh` | Build information, stage panels, and conditional core-message formatting |
| `tools/f2fs.sh` | Extension-list validation, comparison, and sysfs updates |
| `f2fs-cold.list` | Media, archives, packages, code, documents, and fonts |
| `f2fs-hot.list` | Databases, temporary files, caches, and logs |
| `tools/ak3-core.sh` | Upstream image preparation, repacking, and flashing helpers |
| `META-INF/com/google/android/update-binary` | Recovery entry point, shared UI lifecycle, compatibility checks, and environment management |
| `META-INF/com/google/android/updater-script` | Compatibility stub and upstream version marker |
| `LICENSE` | Licensing terms for scripts and bundled components |

Module payloads, ramdisk overlays, and patch directories are not used by this configuration. The upstream core may create working directories during installation.

## Configure a release

### Build properties

Edit the `properties()` block in `anykernel.sh`:

```text
kernel.name=
kernel.string=
kernel.version=
kernel.toolchain=
kernel.maintainer=
device.name1=
device.name2=
supported.versions=
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=1
```

Metadata and compatibility values are intentionally left for the release maintainer to supply.

| Property | Usage |
| --- | --- |
| `kernel.name` | Value of the aligned `Kernel Name` row |
| `kernel.string` | Build description retained for backend metadata; not repeated in the compact header |
| `kernel.version` | Kernel release identifier |
| `kernel.toolchain` | Compiler/toolchain description |
| `kernel.maintainer` | Maintainer name or contact |
| `device.nameN` | Accepted device identifiers; add numbered entries as required |
| `supported.versions` | Supported Android release list or range; blank leaves the version unrestricted |
| `do.devicecheck` | `1` enables the upstream device compatibility check |
| `do.modules` / `do.systemless` | Both disabled; no module payload is installed |
| `do.cleanup` / `do.cleanuponabort` | Remove the installation workspace after completion or abort |

**Device checking is enabled. Installation rejects all devices until a matching `device.nameN` is configured.** The backend checks `ro.product.device`, `ro.build.product`, `ro.product.vendor.device`, and `ro.vendor.product.device`.

For a kernel that supports the entire miatoll family, accepted identifiers may include `curtana`, `gram`, `excalibur`, and `joyeuse`. Add only identifiers supported by the kernel being distributed. Additional entries such as `device.name3` and `device.name4` are supported.

Android versions may be expressed as a list, such as `13, 14, 15`, or a range, such as `13 - 15`. Configure the actual supported releases rather than relying on the examples.

### Boot target

```sh
BLOCK=boot;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;
NO_BLOCK_DISPLAY=1;
```

`BLOCK=boot` selects the boot partition by name. The core resolves the actual device node through standard paths, including `/dev/block/bootdevice/by-name/boot` on miatoll; it is not a relative filename.

`IS_SLOT_DEVICE=0` configures a non-slot target. For another device, review slot handling, boot header version, DTB location, AVB requirements, and whether `init_boot`, `vendor_boot`, or other partitions need separate handling. These defaults are not a universal multi-device installer.

## Kernel and device-tree payloads

Place the selected kernel image at the ZIP root using a filename recognized by the core, such as `Image.gz-dtb` or `Image.gz`. Include **one kernel candidate**: the core chooses the first recognized filename, not necessarily the newest file.

### DTBO

A compatible root-level `dtbo.img` is installed with:

```sh
flash_generic dtbo;
```

The helper resolves the DTBO partition and checks image size. It also accepts the filename `dtbo`. With neither file present, the installer reports a skip and leaves the partition untouched. Include only one DTBO payload.

Partition discovery and size checks do not establish that an overlay matches the hardware or kernel. Package only a DTBO image validated for the intended devices.

### DTB

A Device Tree Blob describes hardware to the kernel. DTBO images contain overlays for a device tree; the two are not interchangeable.

A generated `dtb.img` may contain a raw DTB, concatenated DTBs, or a platform-specific container. Choose its packaging from the kernel build recipe and the device's boot image layout:

- **Appended DTB:** If the build produces an `Image.gz-dtb` containing the required DTBs, use that kernel payload. A separate DTB replacement is generally unnecessary for this layout.
- **Separate boot-image component:** The core recognizes root-level `dtb` and `dtb.img`. In the bundled magiskboot repack path, the replacement is copied into the separate `dtb` component only when that component was extracted from the existing image.
- **Separate build outputs:** An `Image.gz` plus `dtb.img` requires checking the packaging recipe. Concatenation is suitable only when the device expects an appended DTB and the output format supports it.

Do not flash DTB bytes directly to `boot`, place `dtb.img` on the DTBO partition, or add a standalone DTB-partition write without verified device requirements. Devices storing DTBs in another boot-related image need an appropriate partition workflow.

## Installation sequence

The backend extracts the ZIP, prepares its tools and environment, displays the banner and release details, and silently runs compatibility checks before starting `anykernel.sh`. A failed check remains a visible, fatal error; routine successful-check messages are not printed.

1. **Boot image** — `split_boot` reads and splits the existing boot image; `flash_boot` rebuilds it with the selected kernel and writes the result. The existing ramdisk is retained without unpacking/repacking or custom ramdisk patches.
2. **Device-tree overlays** — a packaged DTBO payload is passed to `flash_generic dtbo`; absent payloads are skipped.
3. **F2FS extension policy** — mounted filesystems exposing a supported `extension_list` node are checked and updated as needed.

After the payload steps, the backend restores the environment, performs cleanup, and displays one completion panel. Failed payloads take the abort path and never display that panel. Wait for the recovery's final installation result before rebooting. Back up the original boot image and any partition being replaced before testing a release.

## Recovery interface

The backend and kernel payload share `tools/install-ui.sh`. A boxed ASCII banner is followed immediately by six aligned rows, with no separate information heading:

```text
  Kernel Name     : Alecto Kernel
  Kernel Version  : 4.14.357
  Device Name     : curtana
  Toolchain       : Android Clang
  Android Version : 16
  Maintainer      : One4Lots
```

These values illustrate the layout; release properties in the repository remain blank. Labels use a fixed-width column, and long values continue under the value column without truncation. Missing metadata displays as `Not specified`.

The device identifier is read from `getprop`. Android version prefers the mounted system's `build.prop`, falling back to `getprop`; the available values depend on the recovery environment. Partition paths, slot details, the running recovery kernel, and duplicate build descriptions are not printed in the header.

### Lifecycle and status messages

The display follows one sequence: **banner → release details → installation stages → final completion**. Compatibility checks execute without success chatter. `NO_BLOCK_DISPLAY=1` prevents the core from printing partition paths during setup and generic flashing. ZIP extraction is quiet, with extraction errors still reported.

The three numbered stages distinguish boot image installation, optional DTBO installation, and F2FS policy updates. Status tags identify information, completed steps, skips, warnings, root-handling events, AVB handling, and errors. Backend messages are dispatched through `ak_ui_backend_event`; their wording and layout live in the shared UI, including compatibility failures, optional module notices, and diagnostic-archive output. There are no direct backend `ui_print` calls or a separate legacy message style.

A failed device, Android-version, or security-patch check remains fatal. Android-version and patch-level failures display aligned detected/supported values. The abort path still collects requested diagnostics, restores the environment, and applies the configured cleanup policy; it never prints the success panel.

Extraction, tool initialization, and a missing UI helper can fail before the shared UI is available. A minimal shell-builtin fallback emits the same tagged, 42-column recovery format for these early failures. It requires neither bundled tools nor a successfully extracted package.

No ANSI effects, animations, artificial delays, or simulated verification results are used. Custom output is limited to 42 columns for OrangeFox/TWRP-style consoles; final appearance depends on the recovery font and theme.

`AK_UI_METADATA_SHOWN` prevents the payload process from repeating the header. Running the payload independently retains a header fallback. The backend displays completion only after payload execution, environment restoration, and configured cleanup. Final rendering uses shell builtins so it does not depend on tools removed during cleanup.

### Conditional core messages

The shared `ui_print` hook formats recognized Magisk, KernelSU helper-module, AVB, warning, and abort events. For example, the core's Magisk compatibility branch produces:

```text
  [ROOT] Magisk-patched boot detected
  [INFO] Applying Magisk compatibility
  handling
```

These report actual core branches, not independent root detection or guarantees of root preservation. KernelSU helper-module events also depend on upstream module settings, which are disabled in this configuration. AVB messages describe the core's handling, not independent cryptographic validation.

Unknown messages pass through, warnings and abort messages retain their original text, and stderr/debug diagnostics remain available. Standalone partition-path notifications are diagnostic-only; messages explaining a path-related error are not suppressed. The hook never runs flashing helpers in output-filtering pipelines or subshells.

### Customization and entry points

- Edit `banner` for the opening artwork; keep every line within 42 columns.
- Edit `tools/install-ui.sh` for metadata rows, stage labels, and conditional message mappings.
- Keep `update-binary`: it is required to extract the package, prepare tools, validate compatibility, execute the payload, and restore the environment. Its presentation calls are integrated with the shared UI.
- Keep `updater-script` as the compatibility stub and upstream version marker. It is not an Edify installation script in this package.
- Keep `tools/ak3-core.sh` unchanged unless a separately reviewed flashing change is required.

## F2FS extension policy

The policy contains **52 cold** and **8 hot** extensions, leaving four slots available within the common F2FS limit of 64 total entries. Cold entries cover mostly read-oriented assets; hot entries cover frequently rewritten state. These are workload-dependent allocation hints, not guaranteed performance improvements.

### List format

- Use one extension per line without a leading dot.
- Keep entries within 1–7 ASCII characters using letters, digits, `_`, or `-`.
- Keep extensions unique across both lists, including case-insensitive duplicates.
- Keep the combined count at or below 64.
- Blank lines, full-line `#` comments, inline comments, and CRLF line endings are supported.

Comments and whitespace are removed before validation and are never submitted as extension entries. Extension-prefix and compound-suffix matching vary between kernel versions; explicit extensions are used for portability.

### Update behavior

The installer compares sorted class/extension records from both lists with live sysfs contents. Matching contents skip all writes, regardless of ordering. There is no hardcoded MD5/SHA value to regenerate when the policy changes.

Recovery status lines remain compact: `[SKIP] F2FS extensions already updated`, `[INFO] Updating F2FS extension list`, and `[OK] F2FS extension list updated`. Filesystem paths and the checked-filesystem/warning counts are written to stderr for recovery diagnostics rather than printed in the console. A checked filesystem is one mounted F2FS instance exposing an `extension_list` node, not an individual extension.

Updates remove obsolete records before adding new ones, preserving matching entries and freeing capacity first. Each operation uses a separate sysfs write (`[c]ext`, `[h]ext`, `[c]!ext`, or `[h]!ext`), followed by a read-back comparison. Standard headers and the historical `extenstion` spelling are recognized.

F2FS tuning is best-effort:

- Only mounted filesystems exposing supported nodes are eligible. The installer does not mount or decrypt `/data`.
- Missing nodes produce a skip; invalid policy data produces a warning without applying the policy.
- Unrecognized or unwritable nodes are left unchanged; failed writes or read-back mismatches produce warnings.
- A write failure stops updates to that filesystem and may leave partial state. There is no transactional rollback. A later invocation re-reads actual state and can complete the update.
- Other filesystems continue to be checked after a node fails. F2FS warnings do not convert a successful kernel flash into a fatal installation failure.

The running recovery kernel controls sysfs support. Unmounted filesystems are not changed, and these hints primarily affect subsequent file allocation rather than relocating existing data.

## Package a release

1. Fill in release metadata, supported devices, and Android compatibility.
2. Confirm the boot/DTB layout and place one kernel payload at the repository root.
3. Add a validated `dtbo.img` or separate DTB component only when required.
4. Run the checks below and test the release on the intended device/recovery combination.
5. Create a new ZIP containing the required paths and selected payloads.

For an `Image.gz-dtb` release without optional device-tree payloads, run from the repository root:

```sh
zip -r9 ../kernel-miatoll.zip \
  META-INF tools anykernel.sh banner \
  f2fs-cold.list f2fs-hot.list LICENSE Image.gz-dtb
```

Use a fresh output filename or remove the previous archive first: updating an existing ZIP can retain obsolete payload entries. Replace `Image.gz-dtb` with the chosen kernel filename, and append `dtbo.img` or a required separate DTB component to the input list when applicable. Do not include multiple kernel candidates or unrelated build artifacts. The `LICENSE` file must remain in distributed ZIPs.

Backups and hardware validation are required before public distribution. A successful host-side check cannot establish bootability, device-tree compatibility, or root preservation.

## Validation and maintenance

Run shell syntax and whitespace checks from the repository root:

```sh
sh -n anykernel.sh
sh -n tools/install-ui.sh
sh -n tools/f2fs.sh
sh -n META-INF/com/google/android/update-binary
git diff --check
```

Review the packaged file list, enabled device check, supported identifiers, image selection, and optional DTBO behavior. On-device validation should cover the intended recovery, boot behavior, conditional root handling, and F2FS availability. Development-only test files are not required in release ZIPs.

Review upstream core/backend changes together with bundled binary updates. Preserve the backend UI integration, quiet compatibility-check presentation, custom UI helper, and F2FS helper when rebasing. Recheck exact message mappings when upstream wording changes, and review all device-specific settings before adapting the installer to another target.

## Credits and license

- **osm0sis and AnyKernel contributors:** installer framework and recovery integration.
- **topjohnwu and Magisk contributors:** magiskboot and related tooling.
- **Bundled component authors:** see `LICENSE` for licensing details.

Upstream documentation and support: [AnyKernel3](https://github.com/osm0sis/AnyKernel3).
