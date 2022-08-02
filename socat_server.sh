#!/bin/bash

PORT=80

cleanup() {
    echo "Cleaning up..."
    exit
}

trap cleanup INT TERM


web() {
local port="${PORT}"
socat \
    -v -d -d \
    TCP-LISTEN:${port},crlf,reuseaddr,fork \
    SYSTEM:"
        echo HTTP/1.1 200 OK; 
        echo Content-Type\: text/plain; 
        echo; 
        echo \"Date: \$(date)\";
        echo \"HostName: \$(uname -n)\";
        echo \"Server: \$SOCAT_SOCKADDR:\$SOCAT_SOCKPORT\";
        echo \"Client: \$SOCAT_PEERADDR:\$SOCAT_PEERPORT\";
    "
}

case ${1} in
  start)
    web
    ;;
  *)
    exec "$@"
    ;;
esac
