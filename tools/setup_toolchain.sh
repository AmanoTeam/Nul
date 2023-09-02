#!/bin/bash

set -eu

declare -r NUL_HOME='/tmp/nul-toolchain'

if [ -d "${NUL_HOME}" ]; then
	PATH+=":${NUL_HOME}/bin"
	export NUL_HOME \
		PATH
	return 0
fi

declare -r NUL_CROSS_TAG="$(jq --raw-output '.tag_name' <<< "$(curl --retry 10 --retry-delay 3 --silent --url 'https://api.github.com/repos/AmanoTeam/Nul/releases/latest')")"
declare -r NUL_CROSS_TARBALL='/tmp/nul.tar.xz'
declare -r NUL_CROSS_URL="https://github.com/AmanoTeam/Nul/releases/download/${NUL_CROSS_TAG}/x86_64-unknown-linux-gnu.tar.xz"

curl --connect-timeout '10' --retry '15' --retry-all-errors --fail --silent --location --url "${NUL_CROSS_URL}" --output "${NUL_CROSS_TARBALL}"
tar --directory="$(dirname "${NUL_CROSS_TARBALL}")" --extract --file="${NUL_CROSS_TARBALL}"

rm "${NUL_CROSS_TARBALL}"

mv '/tmp/nul' "${NUL_HOME}"

PATH+=":${NUL_HOME}/bin"

export NUL_HOME \
	PATH
