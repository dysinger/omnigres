# syntax=docker/dockerfile:1.5

ARG UBUNTU_VER=noble

FROM ubuntu:${UBUNTU_VER} AS builder-ubuntu

ARG UBUNTU_VER
ARG POSTGRES_VER=16

ENV UBUNTU_VER=${UBUNTU_VER}
ENV POSTGRES_VER=${POSTGRES_VER}

# UPDATE / UPGRADE
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -y

# SUDO (USEFUL FOR EXPERIMENTS WITHOUT BEING ROOT ALL THE TIME)
RUN apt-get install -y sudo
RUN echo 'ubuntu ALL=(ALL) NOPASSWD: ALL' | tee /etc/sudoers.d/ubuntu
RUN useradd -g users -m redhat

# POSTGRES SERVER
RUN apt install -y postgresql-common
RUN yes|/usr/share/postgresql-common/pgdg/apt.postgresql.org.sh
RUN apt-get update
RUN apt-get install -y \
    postgresql-${POSTGRES_VER} \
    postgresql-plpython3-${POSTGRES_VER} \
    postgresql-server-dev-${POSTGRES_VER}

# DEPENDENCIES
RUN apt-get install -y -t ${UBUNTU_VER}-backports cmake
RUN apt-get install -y \
    build-essential \
    doxygen \
    flex \
    git \
    libreadline-dev \
    libssl-dev \
    ncat \
    pkg-config \
    python3-dev \
    python3-venv

# FPM FOR PACKAGES
RUN apt-get install -y ruby ruby-dev ruby-rubygems squashfs-tools
ENV GEM_HOME=/usr/local
RUN gem install fpm

# VERSION ARGS
ARG OMNI_VER
ARG OMNI_CONTAINERS_VER
ARG OMNI_HTTPC_VER
ARG OMNI_HTTPD_VER
ARG OMNI_SEQ_VER
ARG OMNI_SQL_VER
ARG OMNI_TYPES_VER
ARG OMNI_VAR_VER
ARG OMNI_WEB_VER
ARG OMNI_XML_VER
ARG RELEASE=1

COPY ./ /omni
WORKDIR /build

RUN cmake -DPG_CONFIG=$(which pg_config) -DOPENSSL_CONFIGURED=1 /omni
RUN INCLUDE_PATH="$(dirname $(which pg_config) --include-dir-server)" make -j all
RUN make package_extensions

WORKDIR /artifacts

RUN mkdir -p /build/pkgs/omni-${OMNI_VER}/{lib/postgresql/${POSTGRES_VER}/lib,share/postgresql/${POSTGRES_VER}/extension}
RUN cp /build/packaged/omni--*.so /build/pkgs/omni-${OMNI_VER}/lib/postgresql/${POSTGRES_VER}/lib/
RUN cp /build/packaged/extension/omni--* /build/pkgs/omni-${OMNI_VER}/share/postgresql/${POSTGRES_VER}/extension/
RUN fpm \
    -s dir \
    -t deb \
    --prefix /usr \
    -n omni \
    -v ${OMNI_VER}-${RELEASE} \
    -p omni-${OMNI_VER}-${RELEASE}.$(uname -m).deb \
    -C /build/pkgs/omni-${OMNI_VER}/
