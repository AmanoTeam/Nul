#!/bin/bash

set -eu

declare -r workdir="${PWD}"

declare -r revision="$(git rev-parse --short HEAD)"

declare -r gmp_tarball='/tmp/gmp.tar.xz'
declare -r gmp_directory='/tmp/gmp-6.3.0'

declare -r mpfr_tarball='/tmp/mpfr.tar.xz'
declare -r mpfr_directory='/tmp/mpfr-4.2.1'

declare -r mpc_tarball='/tmp/mpc.tar.gz'
declare -r mpc_directory='/tmp/mpc-1.3.1'

declare -r binutils_tarball='/tmp/binutils.tar.xz'
declare -r binutils_directory='/tmp/binutils-2.43'

declare -r gcc_tarball='/tmp/gcc.tar.xz'
declare -r gcc_directory='/tmp/gcc-14.2.0'

declare -r optflags='-Os'
declare -r linkflags='-Wl,-s'

declare -r max_jobs="$(($(nproc) * 17))"

declare build_type="${1}"

if [ -z "${build_type}" ]; then
	build_type='native'
fi

declare is_native='0'

if [ "${build_type}" == 'native' ]; then
	is_native='1'
fi

declare OBGGCC_TOOLCHAIN='/tmp/obggcc-toolchain'
declare CROSS_COMPILE_TRIPLET=''

declare cross_compile_flags=''

if ! (( is_native )); then
	source "./submodules/obggcc/toolchains/${build_type}.sh"
	cross_compile_flags+="--host=${CROSS_COMPILE_TRIPLET}"
fi

if ! [ -f "${gmp_tarball}" ]; then
	wget --no-verbose 'https://ftp.gnu.org/gnu/gmp/gmp-6.3.0.tar.xz' --output-document="${gmp_tarball}"
	tar --directory="$(dirname "${gmp_directory}")" --extract --file="${gmp_tarball}"
fi

if ! [ -f "${mpfr_tarball}" ]; then
	wget --no-verbose 'https://ftp.gnu.org/gnu/mpfr/mpfr-4.2.1.tar.xz' --output-document="${mpfr_tarball}"
	tar --directory="$(dirname "${mpfr_directory}")" --extract --file="${mpfr_tarball}"
fi

if ! [ -f "${mpc_tarball}" ]; then
	wget --no-verbose 'https://ftp.gnu.org/gnu/mpc/mpc-1.3.1.tar.gz' --output-document="${mpc_tarball}"
	tar --directory="$(dirname "${mpc_directory}")" --extract --file="${mpc_tarball}"
fi

if ! [ -f "${binutils_tarball}" ]; then
	wget --no-verbose 'https://ftp.gnu.org/gnu/binutils/binutils-2.43.tar.xz' --output-document="${binutils_tarball}"
	tar --directory="$(dirname "${binutils_directory}")" --extract --file="${binutils_tarball}"
	
	patch --directory="${binutils_directory}" --strip='1' --input="${workdir}/patches/0001-Revert-gold-Use-char16_t-char32_t-instead-of-uint16_.patch"
fi

if ! [ -f "${gcc_tarball}" ]; then
	wget --no-verbose 'https://ftp.gnu.org/gnu/gcc/gcc-14.2.0/gcc-14.2.0.tar.xz' --output-document="${gcc_tarball}"
	tar --directory="$(dirname "${gcc_directory}")" --extract --file="${gcc_tarball}"
fi

declare -r toolchain_directory="/tmp/nul"

[ -d "${gmp_directory}/build" ] || mkdir "${gmp_directory}/build"

cd "${gmp_directory}/build"

../configure \
	--prefix="${toolchain_directory}" \
	--enable-shared \
	--enable-static \
	${cross_compile_flags} \
	CFLAGS="${optflags}" \
	CXXFLAGS="${optflags}" \
	LDFLAGS="${linkflags}"

make all --jobs
make install

[ -d "${mpfr_directory}/build" ] || mkdir "${mpfr_directory}/build"

cd "${mpfr_directory}/build"

../configure \
	--prefix="${toolchain_directory}" \
	--with-gmp="${toolchain_directory}" \
	--enable-shared \
	--enable-static \
	${cross_compile_flags} \
	CFLAGS="${optflags}" \
	CXXFLAGS="${optflags}" \
	LDFLAGS="${linkflags}"

make all --jobs
make install

[ -d "${mpc_directory}/build" ] || mkdir "${mpc_directory}/build"

cd "${mpc_directory}/build"

../configure \
	--prefix="${toolchain_directory}" \
	--with-gmp="${toolchain_directory}" \
	--enable-shared \
	--enable-static \
	${cross_compile_flags} \
	CFLAGS="${optflags}" \
	CXXFLAGS="${optflags}" \
	LDFLAGS="${linkflags}"

make all --jobs
make install

declare -ra targets=(
	'wearable-device'
	'wearable-emulator'
	'iot-headless-device'
	'iot-headed-device-64'
	'iot-headed-device-32'
	'mobile-device'
	'mobile-emulator'
)

for target in "${targets[@]}"; do
	source "${workdir}/${target}.sh"
	
	declare sysroot_filename='/tmp/sysroot.tar.xz'
	declare sysroot_directory="/tmp/${target}"
	
	curl \
		--connect-timeout '10' \
		--retry '15' \
		--retry-all-errors \
		--fail \
		--silent \
		--location \
		--output "${sysroot_filename}" \
		--url "https://github.com/AmanoTeam/tizen-sysroot/releases/latest/download/${target}.tar.xz"
	
	[ -d "${sysroot_directory}" ] || mkdir "${sysroot_directory}"
	
	tar --extract --directory="${sysroot_directory}" --file="${sysroot_filename}"
	
	[ -d "${toolchain_directory}/${triplet}/lib" ] || mkdir --parent "${toolchain_directory}/${triplet}/lib"
	
	cp --recursive "${sysroot_directory}/lib" "${toolchain_directory}/${triplet}"
	
	if [ -d "${sysroot_directory}/lib64" ]; then
		cp --recursive "${sysroot_directory}/lib64/"* "${toolchain_directory}/${triplet}/lib"
	fi
	
	cp --recursive "${sysroot_directory}/usr/lib" "${toolchain_directory}/${triplet}"
	
	if [ -d "${sysroot_directory}/usr/lib64" ]; then
		cp --recursive "${sysroot_directory}/usr/lib64/"* "${toolchain_directory}/${triplet}/lib"
	fi
	
	cp --recursive "${sysroot_directory}/usr/include" "${toolchain_directory}/${triplet}"
	
	while read name; do
		if [ -f "${name}" ]; then
			chmod 644 "${name}"
		elif [ -d "${name}" ]; then
			chmod 755 "${name}"
		fi
	done <<< "$(find "${toolchain_directory}/${triplet}")"
	
	find "${toolchain_directory}/${triplet}/lib" -maxdepth '1' -mindepth '1' -type 'd' -exec rm --recursive {} \;
	
	sed --in-place 's|/usr/lib64|.|g; s|/lib64/|./|g; s|/usr/lib|.|g; s|/lib/|./|g' "${toolchain_directory}/${triplet}/lib/libc.so"
	
	[ -d "${binutils_directory}/build" ] || mkdir "${binutils_directory}/build"
	
	cd "${binutils_directory}/build"
	rm --force --recursive ./*
	
	../configure \
		--target="${triplet}" \
		--prefix="${toolchain_directory}" \
		--enable-gold \
		--enable-ld \
		--enable-lto \
		--disable-gprofng \
		--with-static-standard-libraries \
		--with-sysroot="${toolchain_directory}/${triplet}" \
		${cross_compile_flags} \
		CFLAGS="${optflags}" \
		CXXFLAGS="${optflags}" \
		LDFLAGS="${linkflags}"
	
	make all --jobs="${max_jobs}"
	make install
	
	[ -d "${gcc_directory}/build" ] || mkdir "${gcc_directory}/build"
	
	cd "${gcc_directory}/build"
	
	rm --force --recursive ./*
	
	../configure \
		--target="${triplet}" \
		--prefix="${toolchain_directory}" \
		--with-linker-hash-style='gnu' \
		--with-gmp="${toolchain_directory}" \
		--with-mpc="${toolchain_directory}" \
		--with-mpfr="${toolchain_directory}" \
		--with-bugurl='https://github.com/AmanoTeam/Nul/issues' \
		--with-pkgversion="Nul v0.2-${revision}" \
		--with-sysroot="${toolchain_directory}/${triplet}" \
		--with-native-system-header-dir='/include' \
		--enable-__cxa_atexit \
		--enable-cet='auto' \
		--enable-checking='release' \
		--enable-clocale='gnu' \
		--enable-default-ssp \
		--enable-gnu-indirect-function \
		--enable-gnu-unique-object \
		--enable-libstdcxx-backtrace \
		--enable-link-serialization='1' \
		--enable-linker-build-id \
		--enable-lto \
		--enable-shared \
		--enable-threads='posix' \
		--enable-libssp \
		--enable-languages='c,c++' \
		--enable-ld \
		--enable-gold \
		--disable-libgomp \
		--disable-bootstrap \
		--disable-libstdcxx-pch \
		--disable-werror \
		--disable-multilib \
		--disable-plugin \
		--disable-nls \
		--without-headers \
		${cross_compile_flags} \
		CFLAGS="${optflags}" \
		CXXFLAGS="${optflags}" \
		LDFLAGS="-Wl,-rpath-link,${OBGGCC_TOOLCHAIN}/${CROSS_COMPILE_TRIPLET}/lib ${linkflags}"
	
	LD_LIBRARY_PATH="${toolchain_directory}/lib" PATH="${PATH}:${toolchain_directory}/bin" make \
		CFLAGS_FOR_TARGET="${optflags} ${linkflags}" \
		CXXFLAGS_FOR_TARGET="${optflags} ${linkflags}" \
		all --jobs="${max_jobs}"
	make install
	
	cd "${toolchain_directory}/${triplet}/bin"
	
	for name in *; do
		rm "${name}"
		ln -s "../../bin/${triplet}-${name}" "${name}"
	done
	
	rm --recursive "${toolchain_directory}/share"
	rm --recursive "${toolchain_directory}/lib/gcc/${triplet}/"*"/include-fixed"
	
	patchelf --add-rpath '$ORIGIN/../../../../lib' "${toolchain_directory}/libexec/gcc/${triplet}/"*"/cc1"
	patchelf --add-rpath '$ORIGIN/../../../../lib' "${toolchain_directory}/libexec/gcc/${triplet}/"*"/cc1plus"
	patchelf --add-rpath '$ORIGIN/../../../../lib' "${toolchain_directory}/libexec/gcc/${triplet}/"*"/lto1"
done