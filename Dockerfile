FROM ubuntu:20.04

RUN apt-get update && apt-get upgrade -y
RUN apt-get update --fix-missing
RUN DEBIAN_FRONTEND="noninteractive" apt-get install -y \
    bc binfmt-support bzip2 fakeroot gcc gcc-arm-linux-gnueabihf \
    git gnupg make parted rsync qemu-user-static wget xz-utils zip \
    debootstrap sudo dirmngr bison flex libssl-dev kmod udev cpio \
    u-boot-tools cryptsetup kpartx

# import U-Boot signing keys
RUN gpg --batch --keyserver hkp://ha.pool.sks-keyservers.net --recv-keys 38DBBDC86092693E && \
    gpg --batch --keyserver hkp://ha.pool.sks-keyservers.net --recv-keys 147C39FF9634B72C && \
    # import golang signing keys
    gpg --batch --keyserver hkp://ha.pool.sks-keyservers.net --recv-keys 7721F63BD38B4796 && \
    # import busybox signing keys
    gpg --batch --keyserver hkp://ha.pool.sks-keyservers.net --recv-keys C9E9416F76E610DBD09D040F47B70C55ACC9965B

# install golang
ENV GOLANG_VERSION="1.16.1"
RUN wget -O go.tgz https://storage.googleapis.com/golang/go${GOLANG_VERSION}.linux-amd64.tar.gz --progress=dot:giga
RUN wget -O go.tgz.asc https://storage.googleapis.com/golang/go${GOLANG_VERSION}.linux-amd64.tar.gz.asc --progress=dot:giga
RUN echo "3edc22f8332231c3ba8be246f184b736b8d28f06ce24f08168d8ecf052549769 *go.tgz" | sha256sum --strict --check -
RUN gpg --batch --verify go.tgz.asc go.tgz
RUN tar -C /usr/local -xzf go.tgz && rm go.tgz

ENV PATH "$PATH:/usr/local/go/bin"
ENV GOPATH /go

RUN git clone https://github.com/f-secure-foundry/tamago-go -b latest /opt/tamago-go
RUN cd /opt/tamago-go/src && ./all.bash

ENV TAMAGO /opt/tamago-go/bin/go

WORKDIR /opt/armory
