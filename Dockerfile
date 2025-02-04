ARG IMAGE=amd64/debian:stretch-slim

FROM $IMAGE as builder

MAINTAINER datarhei <info@datarhei.org>

ARG NASM_VERSION=2.14.02
ARG LAME_VERSION=3.100
ARG X264_VERSION=20190409-2245-stable
ARG X265_VERSION=3.0
ARG FFMPEG_VERSION=4.1.3
ARG NGINX_VERSION=1.14.2
ARG NGINXRTMP_VERSION=1.2.1
ARG NODE_VERSION=10.15.3

ENV SRC="/usr/local/" \
    LD_LIBRARY_PATH="/usr/local/lib" \
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig"

RUN apt-get update && \
    apt-get install -y \
        pkg-config \
        curl \
        libpcre3-dev \
        libtool \
        libssl-dev \
        zlib1g-dev \
        libasound2-dev \
        build-essential \
        cmake

# nasm
RUN mkdir -p /dist && cd /dist && \
    curl -OL "https://www.nasm.us/pub/nasm/releasebuilds/${NASM_VERSION}/nasm-${NASM_VERSION}.tar.xz" && \
    tar -xvJ -f nasm-${NASM_VERSION}.tar.xz && \
    cd nasm-${NASM_VERSION} && \
    ./configure && \
    make -j$(nproc) && \
    make install

# x264
RUN mkdir -p /dist && cd /dist && \
    curl -OL "http://ftp.videolan.org/pub/videolan/x264/snapshots/x264-snapshot-${X264_VERSION}.tar.bz2" && \
    tar -xvj -f x264-snapshot-${X264_VERSION}.tar.bz2 && \
    cd x264-snapshot-${X264_VERSION} && \
    ./configure --prefix="${SRC}" --bindir="${SRC}/bin" --enable-shared && \
    make -j$(nproc) && \
    make install

# x265
RUN mkdir -p /dist && cd /dist && \
    curl -OL "http://ftp.videolan.org/pub/videolan/x265/x265_${X265_VERSION}.tar.gz" && \
    tar -xvz -f x265_${X265_VERSION}.tar.gz && \
    cd x265_${X265_VERSION}/build && \
    cmake ../source && \
    make -j$(nproc) && \
    make install

# libmp3lame
RUN mkdir -p /dist && cd /dist && \
    curl -OL "https://downloads.sourceforge.net/project/lame/lame/${LAME_VERSION}/lame-${LAME_VERSION}.tar.gz" && \
    tar -xvz -f lame-${LAME_VERSION}.tar.gz && \
    cd lame-${LAME_VERSION} && \
    ./configure --prefix="${SRC}" --bindir="${SRC}/bin" --disable-static --enable-nasm && \
    make -j$(nproc) && \
    make install

# ffmpeg && patch
COPY ./contrib/ffmpeg /dist/restreamer/contrib/ffmpeg

RUN mkdir -p /dist && cd /dist && \
    curl -OL "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.gz" && \
    tar -xvz -f ffmpeg-${FFMPEG_VERSION}.tar.gz && \
    cd ffmpeg-${FFMPEG_VERSION} && \
    patch -p1 < /dist/restreamer/contrib/ffmpeg/bitrate.patch && \
    ./configure \
        --bindir="${SRC}/bin" \
        --extra-cflags="-I${SRC}/include" \
        --extra-ldflags="-L${SRC}/lib" \
        --prefix="${SRC}" \
        --enable-nonfree \
        --enable-gpl \
        --enable-version3 \
        --enable-libmp3lame \
        --enable-libx264 \
        --enable-libx265 \
        --enable-openssl \
        --enable-postproc \
        --enable-small \
        --enable-static \
        --disable-debug \
        --disable-doc \
        --disable-shared && \
    make -j$(nproc) && \
    make install

# nginx-rtmp
RUN mkdir -p /dist && cd /dist && \
    curl -OL "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" && \
    tar -xvz -f "nginx-${NGINX_VERSION}.tar.gz" && \
    curl -OL "https://github.com/arut/nginx-rtmp-module/archive/v${NGINXRTMP_VERSION}.tar.gz" && \
    tar -xvz -f "v${NGINXRTMP_VERSION}.tar.gz" && \
    cd nginx-${NGINX_VERSION} && \
    ./configure --prefix=/usr/local/nginx --with-http_ssl_module --with-http_v2_module --add-module=/dist/nginx-rtmp-module-${NGINXRTMP_VERSION} --with-debug && \
    make -j$(nproc) && \
    make install

# node.js
RUN mkdir -p /dist && cd /dist && \
    curl -OL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" && \
    tar -xvJ -f "node-v${NODE_VERSION}-linux-x64.tar.xz" && \
    cd node-v${NODE_VERSION}-linux-x64 && \
    cp -R bin /usr/local && \
    cp -R lib /usr/local

FROM $IMAGE

COPY --from=builder /usr/local/bin /usr/local/bin
COPY --from=builder /usr/local/nginx /usr/local/nginx
COPY --from=builder /usr/local/lib /usr/local/lib

RUN apt-get update && \
    apt-get install -y \
        ca-certificates \
        git \
        procps \
        libpcre3 \
        openssl \
        libssl1.1 \
        zlib1g \
        v4l-utils \
        libv4l-0 \
        alsa-utils

COPY . /restreamer
WORKDIR /restreamer

RUN cd /restreamer && \
    npm install -g grunt-cli nodemon eslint && \
    npm install && \
    grunt build && \
    npm prune --production && \
    npm cache verify && \
    npm uninstall -g grunt-cli nodemon eslint && \
    npm prune --production && \
    apt-get remove -y \
        git && \
    apt autoremove -y

COPY ./contrib/opencast /opt/opencast

RUN mkdir /var/restreamer && \
    mkdir /var/restreamer/recordings && \
    chown -R nobody:root /var/restreamer && \
    chown -R nobody:nogroup /opt/opencast && \
    chmod -R 755 /opt/opencast/ingest-single-request.sh

RUN apt-get install -y curl

RUN apt-get install -y jq

RUN apt-get update && \
    apt-get install -y \
        python3 \
        python3-pip \
        python3-setuptools \
        groff \
        less \
    && pip3 install --upgrade pip \
    && apt-get clean

RUN pip3 --no-cache-dir install --upgrade awscli

EXPOSE 8080
EXPOSE 8181

VOLUME ["/restreamer/db"]

CMD ["./run.sh"]
