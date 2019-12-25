#/bin/bash

clear() 
{
  hdiutil info | grep 'Install macOS' | awk '{print $1}' | while read -r i; do
    hdiutil detach "$i" 2>/dev/null || true
  done
  hdiutil info | grep 'OS X Base System' | awk '{print $1}' | while read -r i; do
    hdiutil detach "$i" 2>/dev/null || true
  done
  hdiutil info | grep 'InstallESD' | awk '{print $1}' | while read -r i; do
    hdiutil detach "$i" 2>/dev/null || true
  done
  hdiutil detach "$VOLUME_DESTINATION" 2>/dev/null || true
  hdiutil detach /Volumes/EFI 2>/dev/null || true
  find /Volumes/ -maxdepth 1 -name "NO NAME*" -exec hdiutil detach {} \; 2>/dev/null || true
}

echo "Hello this script will create Catalina image for VirtualBox"

echo "Please enter desire Image location"

read IMAGE_DIR

echo "Please enter Image name"

read IMAGE_NAME

readonly MACOS_INSTALL_APPLICATION="$(find /Applications -maxdepth 1 -type d -name 'Install macOS *' -print -quit)"
readonly MACOS_INSTALLATOR="$MACOS_INSTALL_APPLICATION/Contents/Resources/createinstallmedia"

readonly IMAGE_DESTINATION=$IMAGE_DIR/$IMAGE_NAME.dmg
readonly VOLUME_DESTINATION=/Volumes/$IMAGE_NAME

readonly ISO_DESTINATION=$IMAGE_DIR/$IMAGE_NAME.iso

echo "IMAGE_DESTINATION: $IMAGE_DESTINATION"
echo "VOLUME_DESTINATION: $VOLUME_DESTINATION"

mkdir -p "$IMAGE_DIR"

hdiutil create -o "$IMAGE_DESTINATION" -size 10g -layout SPUD -fs HFS+J &&
hdiutil attach "$IMAGE_DESTINATION" -mountpoint "$VOLUME_DESTINATION" &&

sudo "$MACOS_INSTALLATOR" --nointeraction --volume "$VOLUME_DESTINATION" --applicationpath "$MACOS_INSTALL_APPLICATION" ||
    echo "Could create or run installer. Please look in the log file..."
    clear

hdiutil convert "$IMAGE_DESTINATION" -format UDTO -o "$ISO_DESTINATION"

echo "Convert to ISO: $?"

# Create patch efi image

readonly PATCH_EFI_IMAGE=$IMAGE_DIR/PatchEfi.dmg
readonly APFS_EFI="/usr/standalone/i386/apfs.efi"

hdiutil create -size 1m -fs MS-DOS -volname "EFI" "$PATCH_EFI_IMAGE"
EFI_DEVICE=$(hdiutil attach -nomount "$PATCH_EFI_IMAGE" 2>&1)

echo "EFI_DEVICE: $EFI_DEVICE"

result="$?"
if [ "$result" -ne "0" ]; then
    echo "Couldn't mount EFI disk: $EFI_DEVICE"
    clear
    exit 92
fi

EFI_DEVICE=$(echo $EFI_DEVICE|egrep -o '/dev/disk[[:digit:]]{1}' |head -n1)

echo "EFI_DEVICE: $EFI_DEVICE"

 # add APFS driver to EFI
if [ -d "/Volumes/EFI/" ]; then
    echo "The folder '/Volumes/EFI/' already exists!"
    clear
    exit 94
fi

diskutil mount "${EFI_DEVICE}s1"
mkdir -p /Volumes/EFI/EFI/drivers >/dev/null 2>&1||true
cp "$APFS_EFI" /Volumes/EFI/EFI/drivers/

# create startup script to boot macOS or the macOS installer
  cat <<EOT > /Volumes/EFI/startup.nsh
@echo -off
set StartupDelay 0
for %d in fs0 fs1 fs2 fs3
  if exist "%d:\EFI\drivers\apfs.efi" then
    load "fs0:\EFI\drivers\apfs.efi"
  endif
endfor
map -r
echo "Searching bootable device..."
for %p in "macOS Install Data" "macOS Install Data\Locked Files\Boot Files" "OS X Install Data" "Mac OS X Install Data" "System\Library\CoreServices" ".IABootFiles"
  for %d in fs2 fs3 fs4 fs5 fs6 fs1
    if exist "%d:\%p\boot.efi" then
      echo "boot: %d:\%p\boot.efi ..."
      "%d:\%p\boot.efi"
    endif
  endfor
endfor
echo "Failed."
EOT

echo "EFI_DEVICE: $EFI_DEVICE"

# close disk again
diskutil unmount "${EFI_DEVICE}s1"

echo "EFI_DEVICE: $EFI_DEVICE"

VBoxManage convertfromraw "${EFI_DEVICE}" "$PATCH_EFI_IMAGE.efi.vdi" --format VDI
diskutil eject "${EFI_DEVICE}"

clear

