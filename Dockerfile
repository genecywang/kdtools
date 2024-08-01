FROM ubuntu:24.04

RUN apt update \
&& DEBIAN_FRONTEND="noninteractive" apt install --no-install-recommends \
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
netcat-traditional \
postgresql-client \
openssh-client \
python3 \
python3-pip \
socat \
tmux \
tcpdump \
unzip \
vim \
wget -y \
&& apt clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
&& unzip awscliv2.zip && ./aws/install && rm -rf aws awscliv2.zip

RUN localedef -c -f UTF-8 -i en_US en_US.UTF-8

RUN git clone --depth=1 https://github.com/Bash-it/bash-it.git ~/.bash_it \
&& bash ~/.bash_it/install.sh -s

COPY socat_server.sh ./
ENTRYPOINT ["/bin/bash", "socat_server.sh"]
CMD ["start"]
