sed -i \
  -e 's/a netinst image name/a DVD-1 image name/' \
  -e 's/the plain netinst image/the plain DVD-1 image/' \
  -e 's/netinst_name/dvd_name/g' \
  -e 's/netinst_ok/debian_cd_image_ok/g' \
  -e 's/amd64-netinst\.iso/amd64-DVD-1.iso/g' \
  tools/test-install-iso.sh
