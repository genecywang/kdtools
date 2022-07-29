#!/bin/bash

port=${1}

socat \
    -v -d -d \
    TCP-LISTEN:${port},crlf,reuseaddr,fork \
    SYSTEM:"
        echo HTTP/1.1 200 OK; 
        echo Content-Type\: text/plain; 
        echo; 
        echo \"Date: \$(date)\";
        echo \"Server: \$SOCAT_SOCKADDR:\$SOCAT_SOCKPORT\";
        echo \"Client: \$SOCAT_PEERADDR:\$SOCAT_PEERPORT\";
    "