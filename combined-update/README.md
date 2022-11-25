# Combined-update-scripts

This repository contains helper scripts for combined update. Combined update lets you update multiple images on the device simultaneously (more details [here](https://developer.izumanetworks.com/docs/device-management/current/connecting/implementing-combined-update.html).

NOTE! This repository has been renamed from `scripts-pelion-edge` to `scripts-edge`. Please update your `git remote` to match.

## Generating a combined update

`prepare_combined_update.sh` is a helper script for generating a combined update image, later used with FOTA on targets that support combined update. It generates an image with two sub-components: rootfs and bootloader capsule. Where:
- rootfs image can be either a delta image or a full one.
- Bootloader capsule consists the u-boot related files that complete the full set required for bootloader update (on platforms that support u-boot capsule update). 

It is assumed that both rootfs and bootloader images are available in an LmP based build platform.
In addition, the following are required to run the script:
- sudo access
- manifest-package-tool/manifest-dev-tool installation 2.4.0 or higher, initialized to work in the current directory
- mkimage & mkeficapsule utilities
- Valid package_config.yaml & u-boot-caps.its in the current directory (examples for these are given under the [samples](https://github.com/PelionIoT/scripts-edge/tree/master/combined-update/samples) directory).

Use the script as following:
```
Usage: ./prepare_combined_update.sh [-t <target-name>] [-i <image-dir>] [-s <scripts-repo-dir>] [-f|-d <base-wic>] [-x exec-util-dir]
  -t target-name:      uz3cg-dgw, uz3eg-iocc-ebbr or uz3eg-iocc
  -i image-dir:        path to images directory in build area
  -s scripts-repo-dir: path to scripts-edge repo
  -f:                  full image
  -d base-wic:         delta image with path to base wic file (if no path, taken from <image-dir>/<target-name> directory)
  -x exec-util-dir:    path to executable utilities (mkimage & mkeficapsule)
```

Examples:
```
./prepare_combined_update.sh -t uz3cg-dgw -i ~/work/edge/build/build-lmp/deploy/images -s ~/work/scripts-edge -d base-console-image-lmp-uz3cg-dgw.wic.gz -x ./exe
./prepare_combined_update.sh -t uz3eg-iocc-ebbr -i ~/work/edge/build/build-lmp/deploy/images -s ~/work/scripts-edge -f -x ./exe
```

On success, this will generate the `combined_package_file` image file. This can later be used with manifest tool as following:
```
manifest-dev-tool update -p combined_package_file --combined-image -n -s -w
```

Note:
u-boot capsule generation is currently required as there's no support for it in LmP build process. It may be removed later if build process supports it.
