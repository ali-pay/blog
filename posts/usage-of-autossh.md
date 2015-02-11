---
title: autossh 的正确用法  
date: '2014-11-03'
description:
categories:
- Code
tags:
- autossh
---

以前用 autossh 的时候，只是简单的用了一个 -N 参数。结果遇到一开始没联上网或者中途断网都还是起不到重连的作用。

后来在这儿
http://www.oschina.net/translate/automatically-restart-ssh-sessions-and-tunnels-using-autossh
看了才知道原来要加一些参数的。

    export AUTOSSH_PIDFILE=/var/run/autossh.pid
    export AUTOSSH_POLL=60
    export AUTOSSH_FIRST_POLL=30
    export AUTOSSH_GATETIME=0
    export AUTOSSH_DEBUG=1
    autossh -M 0 -4 -N USER@HOSTNAME -D 7070 -o \
        "ServerAliveInterval 60" -o  
        "ServerAliveCountMax 3" -o BatchMode=yes \
        -o StrictHostKeyChecking=no

`-M 0` 的意思在 man 里面是这样写的：

    

> Setting the monitor port to 0 turns the monitoring function off, and autossh will only restart ssh upon ssh's exit. For example, if you are using a recent version of OpenSSH, you may wish to explore using the ServerAliveInterval and ServerAliveCountMax options to have the SSH client exit if it finds itself no longer connected to the server. In many ways this may be a better solution than the monitoring port.

大概意思是这是一种比较好的用法。。


