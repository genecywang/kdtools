FROM ubuntu:20.04

RUN apt update \
&& DEBIAN_FRONTEND="noninteractive" apt install --no-install-recommends \
awscli \
curl \
ca-certificates \
default-mysql-client \
dnsutils \
git \
htop \
iftop \
iproute2 \
iputils-ping \
jq \
lsof \
locales \
net-tools \
netcat \
postgresql-client \
socat \
tcpdump \
telnet \
vim \
wget -y \
&& apt clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN localedef -c -f UTF-8 -i en_US en_US.UTF-8

RUN git clone --depth=1 https://github.com/Bash-it/bash-it.git ~/.bash_it \
&& bash ~/.bash_it/install.sh -s

COPY socat_server.sh ./
ENTRYPOINT ["/bin/bash", "socat_server.sh"]
CMD ["start"]
