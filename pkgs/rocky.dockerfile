# syntax=docker/dockerfile:1.5

ARG REDHAT_VER=9

FROM rockylinux:${REDHAT_VER} AS builder-rocky

ARG ARCH=x86_64
ARG POSTGRES_VER=16
ARG REDHAT_VER

# UPDATE
RUN dnf update -y

# SUDO IS USEFUL IF YOU WANT TO RUN AS YOUR OWN HOST'S USER & NOT ROOT
# E.G. `docker run -i -t --rm --user $(id -u):100 -v $PWD:/omni <image>`
# THIS WILL POP YOU INTO A CONTAINER WHERE YOU ARE 'redhat' IN THE GROUP
# 'users'. AND THE FILES YOU TOUCH/WRITE IN /omni WILL BE OWNED BY THE SAME
# USER ID AS YOUR HOST.
RUN dnf install -y sudo
RUN echo 'redhat ALL=(ALL) NOPASSWD: ALL' | tee /etc/sudoers.d/redhat
RUN useradd -g users -m redhat

# POSTGRES
RUN dnf install -y \
    https://download.postgresql.org/pub/repos/yum/reporpms/EL-${REDHAT_VER}-$(uname -m)/pgdg-redhat-repo-latest.noarch.rpm
RUN dnf --enablerepo=crb install -y \
    postgresql${POSTGRES_VER}-contrib \
    postgresql${POSTGRES_VER}-devel \
    postgresql${POSTGRES_VER}-plpython3 \
    postgresql${POSTGRES_VER}-server

# DEPS
RUN yum groupinstall -y "Development Tools"
RUN dnf --enablerepo=crb install -y \
    cmake \
    doxygen \
    nc \
    openssl-devel \
    perl-CPAN \
    python3-devel

# FPM
RUN dnf install -y ruby ruby-devel rubygems squashfs-tools
ENV GEM_HOME=/usr/local
RUN gem install fpm

ARG ITERATION=1

COPY ./ /omni
WORKDIR /build

# BUILD
ENV PATH /usr/pgsql-${POSTGRES_VER}/bin:${PATH}
RUN cmake -DPG_CONFIG=$(which pg_config) -DOPENSSL_CONFIGURED=1 /omni
RUN make -j all
RUN make package_extensions

WORKDIR /pkgs

# PACKAGING
RUN \
for pkg in $(cat /build/artifacts.txt|awk -F'=' '{print $1}') ; do \
    pkgline=$(grep "^$pkg\=" /build/artifacts.txt) ;\
    vers=$(echo $pkgline|cut -d'#' -f1|awk -F'=' '{print $2}') ;\
    deps="--depends postgresql$POSTGRES_VER" ;\
    for d in $(echo $pkgline|awk -F'#' '{print $2}'|tr ',' ' ') ; do \
        n=$(echo $d|awk -F'=' '{print $1}') ;\
        _=$(echo $d|awk -F'=' '{print $2}') ;\
        case $n in \
            dblink|pgcrypto) n="postgresql$POSTGRES_VER-contrib"   ;;\
            plpy*)           n="postgresql$POSTGRES_VER-plpython3" ;;\
        esac ;\
        deps="$deps --depends $n" ;\
    done ;\
    tmp=$(mktemp -d) ;\
    mkdir -p "$tmp/lib" ;\
    mkdir -p "$tmp/share/extension" ;\
    cp -a /build/packaged/$pkg--*.so        "$tmp/lib/"             2>/dev/null && arch=native || arch=all ;\
    cp -a /build/packaged/extension/$pkg--* "$tmp/share/extension/" 2>/dev/null || true ;\
    eval ${GEM_HOME}/bin/fpm \
        --input-type dir \
        --output-type rpm \
        --architecture $arch \
        --name $pkg \
        --version $vers \
        --iteration $ITERATION \
        --prefix /usr/pgsql-$POSTGRES_VER/ \
        --chdir $tmp \
        $deps \
        . ;\
done

# TEST INSTALL
RUN rpm -ivh *.rpm
