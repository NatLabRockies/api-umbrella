#!/usr/bin/env bash

set -e -u

source_dir="$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"

# shellcheck source=tasks/helpers/detect_os_release.sh
source "$source_dir/tasks/helpers/detect_os_release.sh"
detect_os_release

if [[ "$ID_NORMALIZED" == "rhel" ]]; then
  core_runtime_dependencies=(
    # General
    bash
    ca-certificates
    glibc
    libffi
    libuuid
    libyaml
    libzstd-devel
    logrotate
    ncurses-libs
    openssl
    pcre
    pcre2
    postgresql
    zlib

    # geoip-auto-updater
    coreutils
    curl
    gzip

    # TrafficServer
    libxml2

    # init.d script helpers
    initscripts

    # For kill used in stop/reopen-logs commands.
    util-linux

    # For pstree used in reopen-logs command.
    psmisc

    # For OpenResty's "resty" CLI.
    perl
    perl-Time-HiRes

    # For prefixed console output (gnu version for strftime support).
    gawk

    # lua-resty-nettle
    nettle-devel

    # lualdap
    openldap
  )
  core_build_dependencies=(
    autoconf
    automake
    bzip2
    chrpath
    gcc
    gcc-c++
    gettext
    git
    libcurl-devel
    libffi-devel
    libtool
    libuuid-devel
    libxml2-devel
    libyaml-devel
    make
    ncurses-devel
    openssl-devel
    patch
    pcre-devel
    pcre2-devel
    pkgconfig
    python
    readline-devel
    rpm-build
    rsync
    tar
    unzip
    xz

    # lualdap
    openldap-devel

    # For tests and building static site.
    ruby-devel
    rubygem-bundler
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
    urw-fonts

    # For pkill/pgrep used for process tests.
    procps-ng

    # For running lsof tests in Docker as root
    sudo

    # Postgres Ruby client for tests
    libpq-devel

    # For nokogiri dependency
    libxml2-devel
    libxslt-devel
  )

  if [[ "$VERSION_ID" -le "7" ]]; then
    # Install GCC 7+ for compiling TrafficServer (C++17 required).
    core_build_dependencies+=(
      centos-release-scl
      devtoolset-7
    )
  else
    core_runtime_dependencies+=(
      # lua-icu-date-ffi
      libicu-devel

      # lua-psl
      libpsl
    )

    core_build_dependencies+=(
      # lua-psl
      libpsl-devel
    )
  fi
elif [[ "$ID_NORMALIZED" == "debian" ]]; then
  libffi_version=8
  libldap_version="2.5-0"

  if [[ "$ID" == "debian" && "$VERSION_ID" -le "11" ]]; then
    libffi_version=7
  elif [[ "$ID" == "debian" && "$VERSION_ID" -le "10" ]]; then
    libffi_version=6
  elif [[ "$ID" == "ubuntu" && "${VERSION_ID%.*}" -le "18" ]]; then
    libffi_version=6
  fi

  if [[ "$ID" == "debian" && "$VERSION_ID" -le "11" ]]; then
    libldap_version="2.4-2"
  fi

  core_runtime_dependencies=(
    # General
    bash
    ca-certificates
    libc6
    "libffi$libffi_version"
    libncurses5
    libpcre3
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
    "libldap-$libldap_version"

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
    libpcre3-dev
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

  # Install GCC 7+ for compiling TrafficServer (C++17 required).
  if [[ "$ID" == "debian" && "$VERSION_ID" -le "9" ]]; then
    core_build_dependencies+=(
      clang-7
      libc++-7-dev
      libc++abi-7-dev
    )

    core_runtime_dependencies+=(
      libc++1-7
      libc++abi1-7
    )
  fi
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
