# .rst: FindPostgreSQL
# --------------------
#
# Builds a PostgreSQL installation. As opposed to finding a system-wide installation, this module
# will download and build PostgreSQL with debug enabled.
#
# By default, it'll download the latest known version of PostgreSQL (at the time of last update)
# unless `PGVER` variable is set. `PGVER` can be either a major version like `15` which will be aliased
# to the latest known minor version, or a full version.
#
# This module defines the following variables
#
# ::
#
# PostgreSQL_LIBRARIES - the PostgreSQL libraries needed for linking
#
# PostgreSQL_INCLUDE_DIRS - include directories
#
# PostgreSQL_SERVER_INCLUDE_DIRS - include directories for server programming
#
# PostgreSQL_LIBRARY_DIRS  - link directories for PostgreSQL libraries
#
# PostgreSQL_EXTENSION_DIR  - the directory for extensions
#
# PostgreSQL_SHARED_LINK_OPTIONS  - options for shared libraries
#
# PostgreSQL_LINK_OPTIONS  - options for static libraries and executables
#
# PostgreSQL_VERSION_STRING - the version of PostgreSQL found (since CMake
# 2.8.8)
#
# ----------------------------------------------------------------------------
# History: This module is derived from the existing FindPostgreSQL.cmake and try
# to use most of the existing output variables of that module, but uses
# `pg_config` to extract the necessary information instead and add a macro for
# creating extensions. The use of `pg_config` is aligned with how the PGXS code
# distributed with PostgreSQL itself works.

# Copyright 2022 Omnigres Contributors
# Copyright 2020 Mats Kindahl
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy of
# the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.

# Use latest known version if PGVER is not set
if(NOT PGVER)
    set(PGVER 15)
endif()

# If the version is not known, try resolving the alias
set(PGVER_ALIAS_15 15.3)
set(PGVER_ALIAS_14 14.8)
set(PGVER_ALIAS_13 13.11)
set(PGVER_ALIAS_12 12.15)

if("${PGVER}" MATCHES "[0-9]+.[0-9]+")
    set(PGVER_ALIAS "${PGVER}")
else()
    set(PGVER_ALIAS "${PGVER_ALIAS_${PGVER}}")

    # If it still can't be resolved, fail
    if("${PGVER_ALIAS}" MATCHES "[0-9]+.[0-9]+")
        if(NOT _POSTGRESQL_ANNOUNCED_${PGVER_ALIAS})
            message(STATUS "Resolved PostgreSQL version alias ${PGVER} to ${PGVER_ALIAS}")
        endif()
    else()
        message(FATAL_ERROR "Can't resolve PostgreSQL version ${PGVER}")
    endif()
endif()

# This is where we manage all PostgreSQL installations
set(PGDIR "${CMAKE_CURRENT_LIST_DIR}/../.pg/${CMAKE_HOST_SYSTEM_NAME}")

# This is where we manage selected PostgreSQL version's installations
set(PGDIR_VERSION "${PGDIR}/${PGVER_ALIAS}")

if(NOT EXISTS "${PGDIR_VERSION}/build/bin/postgres")
    file(MAKE_DIRECTORY ${PGDIR})
    message(STATUS "Downloading PostgreSQL ${PGVER}")
    file(DOWNLOAD "https://ftp.postgresql.org/pub/source/v${PGVER_ALIAS}/postgresql-${PGVER_ALIAS}.tar.bz2" "${PGDIR}/postgresql-${PGVER_ALIAS}.tar.bz2" SHOW_PROGRESS)
    message(STATUS "Extracting PostgreSQL ${PGVER}")
    file(ARCHIVE_EXTRACT INPUT "${PGDIR}/postgresql-${PGVER_ALIAS}.tar.bz2" DESTINATION ${PGDIR_VERSION})
    execute_process(
        COMMAND ./configure --enable-debug --prefix "${PGDIR_VERSION}/build"
        WORKING_DIRECTORY "${PGDIR_VERSION}/postgresql-${PGVER_ALIAS}")

    # Replace PGSHAREDIR with `PGSHAREDIR` environment variable so that we don't need to deploy extensions
    # between different builds into the same Postgres
    execute_process(
        COMMAND make pg_config_paths.h
        WORKING_DIRECTORY "${PGDIR_VERSION}/postgresql-${PGVER_ALIAS}/src/port")
    file(READ "${PGDIR_VERSION}/postgresql-${PGVER_ALIAS}/src/port/pg_config_paths.h" FILE_CONTENTS)
    string(APPEND FILE_CONTENTS "
#undef PGSHAREDIR
#define PGSHAREDIR (getenv(\"PGSHAREDIR\") ? (const char *)getenv(\"PGSHAREDIR\") : \"${PGDIR_VERSION}/build/share/postgresql\")
")
    file(WRITE "${PGDIR_VERSION}/postgresql-${PGVER_ALIAS}/src/port/pg_config_paths.h" ${FILE_CONTENTS})

    execute_process(

            # Ensure we always set SHELL to /bin/sh to be used in pg_regress. Otherwise it has been observed to
            # degrade to `sh` (at least, on NixOS) and pg_regress fails to start anything
            COMMAND make SHELL=/bin/sh -j ${CMAKE_BUILD_PARALLEL_LEVEL} install
            WORKING_DIRECTORY "${PGDIR_VERSION}/postgresql-${PGVER_ALIAS}")
endif()

set(PostgreSQL_ROOT "${PGDIR_VERSION}/build")

find_program(
    PG_CONFIG pg_config
    PATHS ${PostgreSQL_ROOT}
    REQUIRED
    NO_DEFAULT_PATH
    PATH_SUFFIXES bin)

if(NOT PG_CONFIG)
    message(FATAL_ERROR "Could not find pg_config")
else()
    set(PostgreSQL_FOUND TRUE)
endif()

if(PostgreSQL_FOUND)
    macro(PG_CONFIG VAR OPT)
        execute_process(
            COMMAND ${PG_CONFIG} ${OPT}
            OUTPUT_VARIABLE ${VAR}
            OUTPUT_STRIP_TRAILING_WHITESPACE)
    endmacro()

    pg_config(_pg_bindir --bindir)
    pg_config(_pg_includedir --includedir)
    pg_config(_pg_pkgincludedir --pkgincludedir)
    pg_config(_pg_sharedir --sharedir)
    pg_config(_pg_includedir_server --includedir-server)
    pg_config(_pg_libs --libs)
    pg_config(_pg_ldflags --ldflags)
    pg_config(_pg_ldflags_sl --ldflags_sl)
    pg_config(_pg_ldflags_ex --ldflags_ex)
    pg_config(_pg_pkglibdir --pkglibdir)
    pg_config(_pg_libdir --libdir)
    pg_config(_pg_version --version)

    separate_arguments(_pg_ldflags)
    separate_arguments(_pg_ldflags_sl)
    separate_arguments(_pg_ldflags_ex)

    set(_server_lib_dirs ${_pg_libdir} ${_pg_pkglibdir})
    set(_server_inc_dirs ${_pg_pkgincludedir} ${_pg_includedir_server})
    string(REPLACE ";" " " _shared_link_options
        "${_pg_ldflags};${_pg_ldflags_sl}")
    set(_link_options ${_pg_ldflags})

    if(_pg_ldflags_ex)
        list(APPEND _link_options ${_pg_ldflags_ex})
    endif()

    set(PostgreSQL_INCLUDE_DIRS
        "${_pg_includedir}"
        CACHE PATH
        "Top-level directory containing the PostgreSQL include directories."
    )
    set(PostgreSQL_EXTENSION_DIR
        "${_pg_sharedir}/extension"
        CACHE PATH "Directory containing extension SQL and control files")
    set(PostgreSQL_SERVER_INCLUDE_DIRS
        "${_server_inc_dirs}"
        CACHE PATH "PostgreSQL include directories for server include files.")
    set(PostgreSQL_LIBRARY_DIRS
        "${_pg_libdir}"
        CACHE PATH "library directory for PostgreSQL")
    set(PostgreSQL_LIBRARIES
        "${_pg_libs}"
        CACHE PATH "Libraries for PostgreSQL")
    set(PostgreSQL_SHARED_LINK_OPTIONS
        "${_shared_link_options}"
        CACHE STRING "PostgreSQL linker options for shared libraries.")
    set(PostgreSQL_LINK_OPTIONS
        "${_pg_ldflags},${_pg_ldflags_ex}"
        CACHE STRING "PostgreSQL linker options for executables.")
    set(PostgreSQL_SERVER_LIBRARY_DIRS
        "${_server_lib_dirs}"
        CACHE PATH "PostgreSQL server library directories.")
    set(PostgreSQL_VERSION_STRING
        "${_pg_version}"
        CACHE STRING "PostgreSQL version string")
    set(PostgreSQL_PACKAGE_LIBRARY_DIR
        "${_pg_pkglibdir}"
        CACHE STRING "PostgreSQL package library directory")

    find_program(
        PG_BINARY postgres
        PATHS ${PostgreSQL_ROOT_DIRECTORIES}
        HINTS ${_pg_bindir}
        PATH_SUFFIXES bin)

    if(NOT PG_BINARY)
        message(FATAL_ERROR "Could not find postgres binary")
    endif()

    find_program(PG_REGRESS pg_regress HINT
        ${PostgreSQL_PACKAGE_LIBRARY_DIR}/pgxs/src/test/regress)

    if(NOT PG_REGRESS)
        message(WARNING "Could not find pg_regress, tests not executed")
    endif()

    find_program(
        INITDB initdb
        PATHS ${PostgreSQL_ROOT_DIRECTORIES}
        HINTS ${_pg_bindir}
        PATH_SUFFIXES bin)

    if(NOT INITDB)
        message(WARNING "Could not find initdb, psql_${NAME} will not be available")
    endif()

    find_program(
        CREATEDB createdb
        PATHS ${PostgreSQL_ROOT_DIRECTORIES}
        HINTS ${_pg_bindir}
        PATH_SUFFIXES bin)

    if(NOT CREATEDB)
        message(WARNING "Could not find createdb, psql_${NAME} will not be available")
    endif()

    find_program(
        PSQL psql
        PATHS ${PostgreSQL_ROOT_DIRECTORIES}
        HINTS ${_pg_bindir}
        PATH_SUFFIXES bin)

    if(NOT PSQL)
        message(WARNING "Could not find psql, psql_${NAME} will not be available")
    endif()

    find_program(
        PG_CTL pg_ctl
        PATHS ${PostgreSQL_ROOT_DIRECTORIES}
        HINTS ${_pg_bindir}
        PATH_SUFFIXES bin)

    if(NOT PG_CTL)
        message(WARNING "Could not find pg_ctl, psql_${NAME} will not be available")
    endif()

    if(NOT _POSTGRESQL_ANNOUNCED_${PGVER_ALIAS})
        message(STATUS "Found postgres binary at ${PG_BINARY}")
        message(STATUS "PostgreSQL version ${PostgreSQL_VERSION_STRING} found")
        message(
            STATUS
            "PostgreSQL package library directory: ${PostgreSQL_PACKAGE_LIBRARY_DIR}")
        message(STATUS "PostgreSQL libraries: ${PostgreSQL_LIBRARIES}")
        message(STATUS "PostgreSQL extension directory: ${PostgreSQL_EXTENSION_DIR}")
        message(STATUS "PostgreSQL linker options: ${PostgreSQL_LINK_OPTIONS}")
        message(
            STATUS "PostgreSQL shared linker options: ${PostgreSQL_SHARED_LINK_OPTIONS}")
        set(_POSTGRESQL_ANNOUNCED_${PGVER_ALIAS} ON CACHE INTERNAL "PostgreSQL was announced")
    endif()
endif()

include(PostgreSQLExtension)