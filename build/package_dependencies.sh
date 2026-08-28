#!/usr/bin/env bash

set -e -u

source_dir="$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"

# shellcheck source=tasks/helpers/detect_os_release.sh
source "$source_dir/tasks/helpers/detect_os_release.sh"
detect_os_release

if [[ "$ID_NORMALIZED" == "debian" && "$VERSION_ID" == "13" ]]; then
  core_runtime_dependencies=(
    # General
    bash
    ca-certificates
    libc6
    libffi8
    libncurses6
    libpcre2-8-0
    libuuid1
    libyaml-0-2
    libzstd-dev
    logrotate
    openssl
    postgresql-client-18
    runit
    zlib1g

    # geoip-auto-updater
    coreutils
    curl
    gzip

    # TrafficServer
    libhwloc15
    libjemalloc2
    libunwind8
    libxml2

    # init.d script helpers
    sysvinit-utils
    lsb-base

    # For kill used in stop/reopen-logs commands.
    procps

    # For pstree used in reopen-logs command.
    psmisc

    # For OpenResty's "resty" CLI.
    perl

    # For prefixed console output (gnu version for strftime support).
    gawk

    # libcidr-ffi
    libcidr-dev

    # lua-icu-date-ffi
    libicu-dev

    # lua-resty-nettle
    "nettle-dev"

    # lualdap
    "libldap2"

    # lua-psl
    libpsl5

    # ngx_http_geoip2_module
    libmaxminddb0
  )
  core_build_dependencies=(
    autoconf
    automake
    bzip2
    chrpath
    g++
    gcc
    gettext
    git
    libcurl4-openssl-dev
    libffi-dev
    libjansson-dev
    libncurses-dev
    libpcre2-dev
    libreadline-dev
    libssl-dev
    libtool
    libtool-bin
    libxml2-dev
    libyaml-dev
    lsb-release
    make
    patch
    pkg-config
    python3
    rsync
    tar
    unzip
    uuid-dev
    xz-utils
    zlib1g-dev

    # lualdap
    libldap-dev

    # For tests and building static site.
    ruby-dev
    ruby-bundler

    # lua-psl
    libpsl-dev

    # ngx_http_geoip2_module
    libmaxminddb-dev

    # TrafficServer
    libhwloc-dev
    libjemalloc-dev
    libunwind-dev

    # Fluent Bit
    bison
    cmake
    flex
  )
  test_runtime_dependencies=(
    unbound
  )
  test_build_dependencies=(
    # Binary and readelf tests
    file
    binutils

    # For checking for file descriptor leaks during the tests.
    lsof

    # Fonts for Capybara screenshots.
    gsfonts

    # For pkill/pgrep used for process tests.
    procps

    # For running lsof tests in Docker as root
    sudo

    # Postgres Ruby client for tests
    libpq-dev

    # For nokogiri dependency
    libxml2-dev
    libxslt-dev
  )
else
  echo "Unknown build system"
  exit 1
fi

all_build_dependencies=(
  "${core_runtime_dependencies[@]}"
  "${core_build_dependencies[@]}"
)

# shellcheck disable=SC2034
all_dependencies=(
  "${all_build_dependencies[@]}"
  "${test_runtime_dependencies[@]}"
  "${test_build_dependencies[@]}"
)
