FROM ubuntu:20.04

RUN apt update \
&& DEBIAN_FRONTEND="noninteractive" apt install --no-install-recommends \
curl \
default-mysql-client \
dnsutils \
git \
htop \
iftop \
iproute2 \
iputils-ping \
jq \
lsof \
net-tools \
netcat \
postgresql-client \
socat \
tcpdump \
telnet \
vim \
wget -y \
&& apt clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN git clone --depth=1 https://github.com/Bash-it/bash-it.git ~/.bash_it \
&& bash ~/.bash_it/install.sh -s

COPY socat_server.sh ./
ENTRYPOINT ["/bin/bash", "socat_server.sh"]
CMD ["80"]