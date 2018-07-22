. ${UTILSDIR:?}/common.inc.sh; _u_set_loaded umoci

test -x "${UMOCI:=$(command -v umoci)}" || return

u_cleanup_umoci () {
	# use ???? to not accidentally delete other files
	rm -rf ${BUILDDIR:-.}/image.????
	rm -rf ${BUILDDIR:-.}/bundle.????
	rm -rf ${BUILDDIR:-.}/imgclone.????
	rm -rf ${BUILDDIR:-.}/imgopen.????
}

### images

u_create_image () {
	local path
	path=$(mktemp -udp "${BUILDDIR:-.}" image.XXXX)
	${UMOCI} init --layout "$path"
	echo "$path"
}

u_clone_image () {
	local img path src
	img="${1:?}"
	if [ -d "${BUILDDIR:-.}/${img}" ]; then
		src="${BUILDDIR:-.}/${img}"
		path=$(mktemp -dp "${BUILDDIR:-.}" imgclone.XXXX)
		# reset mode
		chmod $(printf %o $((0777 & ~$(umask)))) "$path"
		# hardlink files in blobs to save space
		cp -r -l "${src}/blobs" "$path"
		# copy everything else normally
		cp -r $(find "$src" -mindepth 1 -maxdepth 1 ! -path "${src}/blobs") "$path"
		echo "$path"
	elif [ -f "${BUILDDIR:-.}/${img}.oci" ]; then
		path=$(mktemp -dp "${BUILDDIR:-.}" imgclone.XXXX)
		# reset mode
		chmod $(printf %o $((0777 & ~$(umask)))) "$path"
		tar -xzf "${BUILDDIR:-.}/${img}.oci" -C "$path"
		echo "$path"
	else
		return 1
	fi
}

u_open_image () {
	local img path
	img="${1:?}"
	if [ -d "${BUILDDIR:-.}/${img}" ]; then
		echo "${BUILDDIR:-.}/${img}"
	elif [ -f "${BUILDDIR:-.}/${img}.oci" ]; then
		path=$(mktemp -dp "${BUILDDIR:-.}" imgopen.XXXX)
		# reset mode
		chmod $(printf %o $((0777 & ~$(umask)))) "$path"
		tar -xzf "${BUILDDIR:-.}/${img}.oci" -C "$path"
		echo "$path"
	else
		return 1
	fi
}

u_set_image_name () {
	local newpath
	newpath="$(dirname "${1:?}")/${2:?}"
	mv -T "${1}" "$newpath"
	echo "$newpath"
}

u_clean_image () {
	${UMOCI} gc --layout "${1:?}"
}

u_serialize_image () {
	local archive
	archive="${BUILDDIR:-.}/${2:?}.oci"
	( cd "${1:?}" && find -mindepth 1 -maxdepth 1 | sed 's:^./::' ) | \
		tar -c --hard-dereference --numeric-owner --owner 0 --group 0 -z -f "$archive" -C "${1}" --files-from -
	echo "$archive"
}

### image refs

u_gen_refname () {
	mktemp -u "${1:+$1:}XXXX"
}

u_create_ref () {
	local ref
	ref=$(u_gen_refname "${1:?}")
	${UMOCI} new --image "$ref"
	echo "$ref"
}

u_clone_ref () {
	local oldref tag
	oldref=$(u_get_ref "${1:?}" "${2:?}")
	tag=$(u_gen_refname)
	u_write_ref "$oldref" "$tag"
	echo $(u_get_ref "$1" "$tag")
}

u_get_ref () {
	echo "${1:?}:${2:?}"
}

u_list_refs () {
	${UMOCI} list --layout "${1:?}"
}

u_write_ref () {
	${UMOCI} tag --image "${1:?}" "${2:?}"
}

u_remove_ref () {
	${UMOCI} rm --image "${1:?}"
}

u_remove_refs_except () {
	local img ref exclude
	img="${1:?}"
	shift
	[ $# -ge 1 ] || return
	for ref in "$@"; do
		# remove image prefix (if any) when adding to the exclude list
		exclude="${exclude} ${ref#*:}"
	done
	for ref in $(u_list_refs "$img"); do
		if ! echo "$exclude" | grep -qwF "$ref"; then
			u_remove_ref $(u_get_ref "$img" "$ref")
		fi
	done
}

### image ref layers

u_open_layer () {
	local img bundle
	img="${1:?}"
	shift
	bundle=$(mktemp -udp "${BUILDDIR:-.}" bundle.XXXX)
	${UMOCI} unpack --image "$img" "$bundle" "$@"
	echo "$bundle"
}

u_continue_layer () {
	local img bundle
	img="${2:?}"
	bundle="${1:?}"
	shift 2
	${UMOCI} repack --refresh-bundle --image "$img" "$bundle" "$@"
}

u_close_layer () {
	local img bundle
	img="${2:?}"
	bundle="${1:?}"
	shift 2
	${UMOCI} repack --image "$img" "$bundle" "$@"
	rm -rf "$bundle"
}

### image ref config

u_config () {
	local img
	img="${1:?}"
	shift
	${UMOCI} config --image "$img" "$@"
}

### layer utilities

u_layer_path () {
	local bundle="${1:?}" path="${2:?}"
	# make sure the path has a single leading slash and no trailing slashes
	path="$(echo -n "/${path}" | sed 's#^\s*/*\(/\([^/]\(.*[^/]\)\?\)\?\)/\?\s*$#\1#')"
	echo "${bundle}/rootfs${path}"
}