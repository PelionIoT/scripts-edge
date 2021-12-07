#!/bin/bash
usage() 
{ 
  echo "Usage: $0 [-t <target-name>] [-i <image-dir>] [-s <scripts-repo-dir>] [-f|-d <base-wic>] [-x exec-util-dir]" 1>&2
  echo "  -t target-name:      uz3cg-dgw, uz3eg-iocc-ebbr or uz3eg-iocc" 1>&2
  echo "  -i image-dir:        path to "images" directory in build area" 1>&2
  echo "  -s scripts-repo-dir: path to scripts-pelion-edge repo" 1>&2
  echo "  -f:                  full image" 1>&2
  echo "  -d base-wic:         delta image with path to base wic file (if no path, taken from <image-dir>/<target-name> directory)" 1>&2
  echo "  -x exec-util-dir:    path to executable utilities (mkimage & mkeficapsule)" 1>&2
  echo 1>&2
  echo "Requires:" 1>&2
  echo "- sudo access" 1>&2
  echo "- Latest manifest-package-tool/manifest-dev-tool installation (initialized to work in the current directory)" 1>&2
  echo "- mkimage & mkeficapsule utilities" 1>&2
  echo "- Valid package_config.yaml & u-boot-caps.its in the current directory" 1>&2
  echo 1>&2
  echo "Examples:" 1>&2
  echo "$0 -t uz3cg-dgw -i ~/work/pelion_edge/build/build-lmp/deploy/images -s ~/work/scripts-pelion-edge -d base-console-image-lmp-uz3cg-dgw.wic.gz -x ./exe" 1>&2
  echo "$0 -t uz3eg-iocc-ebbr -i ~/work/pelion_edge/build/build-lmp/deploy/images -s ~/work/scripts-pelion-edge -f -x ./exe" 1>&2
  exit 1
}

fail()
{
  echo "Failed!" 1>&2
  exit -1
}

cwd=`pwd`
while getopts "t:i:s:fd:x:h" opt; do
  case "$opt" in
    t) target=$OPTARG
       [[ "$target" != uz3cg-dgw ]] && [[ "$target" != uz3eg-iocc-ebbr ]] && [[ "$target" != uz3eg-iocc ]] && usage
       ;;
    i) img_dir=$OPTARG
       ;;
    s) scripts_dir="$OPTARG"/ostree
       ;;
    f) [[ ! -z "$img_type" ]] && usage
       img_type="full"
       ;;
    d) [[ ! -z "$img_type" ]] && usage
       img_type="delta"
       base_wic=$OPTARG
       ;;
    x) exec_util_dir=$OPTARG
       ;;
    h) usage
       ;;
  esac
done

[[ -z "$target" ]] && [[ -z "$img_dir" ]] && [[ -z "$scripts_dir" ]] && [[ -z "$img_type" ]] && [[ -z "$exec_util_dir" ]] && usage
[ ! -d .manifest-dev-tool ] && echo ".manifest-dev-tool directory doesn't exist - run manifest-dev-tool init to initialize it" 1>&2 && usage
[ ! -x "$exec_util_dir"/mkimage -o ! -x "$exec_util_dir"/mkeficapsule ] && echo "No mkimage/mkeficapsule in the given direcory" 1>&2 && usage
[ ! -f package_config.yaml ] && echo "No package_config.yaml in the current directory" 1>&2 && usage
[ ! -f u-boot-caps.its ] && echo "No u-boot-caps.its in the current directory" 1>&2 && usage
[ ! $(command -v manifest-package-tool) ] >& /dev/null && echo "manifest-package-tool not installed" 1>&2 && usage

[[ "$base_wic" != *"/"* ]] && base_wic="$img_dir"/"$target"/"$base_wic"

echo "Preparing combined update image..." 1>&2

cd $scripts_dir
if [[ "$img_type" == "delta" ]]; then
  sudo bash ./createOSTreeUpgrade.sh $base_wic $img_dir/$target/console-image-lmp-"$target".wic.gz $cwd/rootfs.tar.gz 1>&2 > /dev/null || fail
else
  sudo bash ./createOSTreeUpgrade.sh --empty $img_dir/$target/console-image-lmp-"$target".wic.gz $cwd/rootfs.tar.gz 1>&2 > /dev/null || fail
fi

cd $cwd
tar xzvf rootfs.tar.gz ./metadata 1>&2 > /dev/null
hash=`grep To-sha metadata | sed s/.*://`
rm -f metadata
sed -i 0,/vendor_data:/{"s/vendor_data: .*/vendor_data: $hash/"} package_config.yaml 

rm -f boot.bin u-boot.itb
ln -s $img_dir/$target/boot.bin .
ln -s $img_dir/$target/u-boot.itb .
"$exec_util_dir"/mkimage -f u-boot-caps.its u-boot-caps.itb 1>&2 > /dev/null || fail
"$exec_util_dir"/mkeficapsule --fit u-boot-caps.itb -i 1 u-boot-caps.bin 1>&2 > /dev/null || fail
rm -f boot.bin u-boot.itb u-boot-caps.itb 

manifest-package-tool create --config package_config.yaml --output combined_package_file 1>&2 > /dev/null || fail

rm -f rootfs.tar.gz u-boot-caps.bin

echo "Success!"
exit 0
