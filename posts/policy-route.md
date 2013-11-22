---
title: Linux 策略路由 & n2n 初探
date: '2013-11-17'
description:
categories:
- linux
tags:
- linux
---

#### 背景

这几天，我玩战地4的时候发现，经常走到“登入中”那一步的时候，提示“无法连接到 EA 服务器”。

后来我用 Microsoft Network Monitor 抓包发现是登入的过程中连接某一个认证服务器的 IP 段在大陆访问特别慢。因此我想把游戏的流量通过代理走出去。

但是：

 - TCP 和 UDP 包都要走代理，因此光用 ssh 的 TCP 代理是不行的！
 - 我们家 TPLink 路由器不支持 VPN，而且走 VPN 很可能被墙！
 - 我没有三个 VPN 账号让大家一起玩！
 - 三个人都在 Windows 下开代理玩的话，也很不方便！

总之这激发了我折腾的欲望，为了让大家能透明的加速。所以我想了一个方法：从 TP-Link 路由器里面把特别慢的 IP 路由到 192.168.1.90，一台内网跑 Linux 的笔记本。然后在 192.168.1.90 上面让流量通过隧道到 Linode VPS 上面。


#### Step0：结构

结构如下：

![](/img/policy-route.png)

包转发流程以及配置如下：

![](/img/policy-route-4.png)

#### Step1：设置 TPLink 路由器

![](/img/policy-route-2.png)

把这几个速度比较慢的ip地址填上，这样包就全部到 192.168.1.90 了。

#### Step2：配置 n2n 隧道

介绍一个神器 [n2n](http://www.ntop.org/products/n2n/)。它有 VPN 的作用。但是配置比 OpenVPN 轻松太多。它的功能如图所示：

![](/img/policy-route-n2n.png)

supernode 在公网，两个 edgenode 都可以处于内网中。n2n 这两个 edgenode 中虚拟一个叫 edge0 的网络设备（创建tap设备），两个 edgenode 就通过 edge0 设备通信了。相当于在一个内网。

接下来要做的就是，在 VPS 上面启动一个 supernode 和 edgenode，在 192.168.1.90 上面启动一个 edgenode 连接到 VPS。

n2n 在 ubuntu 下面可以很轻松的安装。

	apt-get install n2n

然后在 VPS 上面执行：

	nohup supernode -l 1653 &
	nohup edge -a 10.0.0.2 -c xxx -k xxx -l localhost:1653 -r &

在 192.168.1.90 上面执行这条命令可以连接到 VPS（106.222.99.23） 上的 supernode：

	nohup edge -a 10.0.0.1 -c xxx -k xxx -l 106.222.99.23:1653 -r &

其中 -a 选项指定 edge0 设备的 IP 地址。`-c 和 -k` 用来把 edgenode 放到同一个内网。一个 supernode 可以同时有很多个内网。`-r` 选项用于在 edge0 上面开启包转发功能，后面会用到。一开始我没加这个选项，结果包没转发过去，达不到 VPN 的功能。

这时候分别看一下 VPS 和 192.168.1.90 下 edge0 的 IP 地址，分别为 10.0.0.2 和 10.0.0.1。然后互 ping 一下，验证联通。

#### Step3：在 192.168.1.90 配置策略路由和 SNAT

先说说策略路由这个神器！

平时我们传统的路由表，就是 route -n 看到的那个表：

![](/img/policy-route-3.png)

这个表是基于 IP 地址来做路由的。

如果我要实现：“让eth0把所有不是给自己ip的包转发到edge0”。这个看起来简单的东西单用 route 命令搞不定。

因为传统的路由表没法区分包来自于哪个设备（我不大懂，貌似是这样的）。如果用传统的方法做，需要同时调整三个路由表：TPLink、192.168.1.90、VPS。基本没法搞。

现在，先用策略路由实现“让eth0把所有不是给自己ip的包转发到edge0”！

	echo 1 > /proc/sys/net/ipv4/ip_forward
	echo "100 my_rule" >> /etc/iproute2/rt_tables
	ip rule add iif eth2 table my_rule
	ip route add table my_rule via 10.0.0.2 dev edge0

策略路由比 `route` 命令更底层一点：

	root@bogon:~# ip rule list
	0:	from all lookup local 
	32765:	from all iif eth2 lookup my_rule 
	32766:	from all lookup main 
	32767:	from all lookup default 

用 `ip rule list` 可以看到系统中默认的三张表：local main default。包一进到协议栈，就开始依次与三个表匹配。这是 local 表的内容。它只负责：“如果是我的包，我就给系统处理”。

	root@bogon:~# ip route list table local
	broadcast 10.0.0.0 dev edge0  proto kernel  scope link  src 10.0.0.1 
	local 10.0.0.1 dev edge0  proto kernel  scope host  src 10.0.0.1 
	broadcast 10.0.0.255 dev edge0  proto kernel  scope link  src 10.0.0.1 
	broadcast 127.0.0.0 dev lo  proto kernel  scope link  src 127.0.0.1 
	local 127.0.0.0/8 dev lo  proto kernel  scope host  src 127.0.0.1 
	local 127.0.0.1 dev lo  proto kernel  scope host  src 127.0.0.1 
	broadcast 127.255.255.255 dev lo  proto kernel  scope link  src 127.0.0.1 
	broadcast 192.168.1.0 dev eth2  proto kernel  scope link  src 192.168.1.90 
	local 192.168.1.90 dev eth2  proto kernel  scope host  src 192.168.1.90 
	broadcast 192.168.1.255 dev eth2  proto kernel  scope link  src 192.168.1.90

“如果不是我的，我就不鸟了”，然后到下一张表 main。在 local 和 main 之间可以插入 251 个表。我们插入一个 my_rule 表，位于 100。这个表里面只有一项内容，就是把包转发到 10.0.0.2（VPS 的 edge0 地址）。触发它的条件是“包来自 eth2”。

然后我在 PC 上面 ping 149.20.4.69。在 VPS 上用 `tcpdump -i edge0` 观察，发现 ICMP 包已经到达 VPS 了。

但此时到达的包，IP 地址依然是 TPLink 发过来时候的内网地址，比如 192.168.1.102。如果直接发送给 VPS 的网关，那必定返回包是收不到的。

介绍一下 SNAT，也就是系统内置的“路由器”：

![](/img/policy-route-snat.png)


NAT 的作用，就是建立（源地址，源端口，目的地址）三元组和（目的端口）之间的映射，这样的话返回的包，就可以通过目的端口来查找未修改前的三元组。达到路由的目的。

我们要达到的目的：把来自 192.168.1.* 的所有包，改成一样的 IP源地址，发送给 VPS 的 edge0。因为这样做的话，VPS 那边就知道“来自源地址 10.0.0.1 的流量是需要加速的”，然后把他们都转发出去。这里并没有完全使用到 SNAT 的功能，其作用只是“打标记”而已。

在 192.168.1.90 执行命令：

	iptables -t nat -A POSTROUTING -j SNAT --to 10.0.0.1 -o edge0

#### Step4：在 VPS 配置 NAT

在 VPS 上，执行下面的命令

	echo 1 > /proc/sys/net/ipv4/ip_forward
	iptables -t nat -A POSTROUTING -s 10.0.0.1/32 -j SNAT --to 106.22.99.23

这次 NAT 的作用是真正的路由，把所有来自 10.0.0.1 的包，源地址改为 106.22.99.23。然后通过默认路由发到网关。

everything DONE！

#### 测试

从 VPS ping 日本战地服务器

	root@li476-23:~# ping 173.199.82.241
	PING 173.199.82.241 (173.199.82.241) 56(84) bytes of data.
	64 bytes from 173.199.82.241: icmp_req=1 ttl=118 time=3.09 ms
	64 bytes from 173.199.82.241: icmp_req=2 ttl=118 time=2.93 ms
	64 bytes from 173.199.82.241: icmp_req=3 ttl=118 time=2.99 ms

从本机 ping VPS
	
	PING 106.187.99.23 56(84) bytes of data.
	64 bytes from li476-23.members.linode.com (106.222.99.23): icmp_req=1 ttl=52 time=86.1 ms
	64 bytes from li476-23.members.linode.com (106.222.99.23): icmp_req=2 ttl=52 time=80.8 ms
	64 bytes from li476-23.members.linode.com (106.222.99.23): icmp_req=3 ttl=52 time=81.6 ms
	64 bytes from li476-23.members.linode.com (106.222.99.23): icmp_req=4 ttl=52 time=82.8 ms
	64 bytes from li476-23.members.linode.com (106.222.99.23): icmp_req=5 ttl=52 time=86.5 ms

实际游戏 ping 值

![](/img/policy-route-test.png)


#### 参考资料

[深入理解linux网络技术内幕: 第三十五章 路由](http://www.oreilly.com.cn/index.php?func=book&isbn=978-7-5083-7964-7)

[N2N VPN服务器的搭建](http://www.ipcpu.com/2010/10/n2n-vpn/)

[Linux路由应用-使用策略路由实现访问控制](http://blog.csdn.net/dog250/article/details/6685633)

[IPtables之四：NAT原理和配置](http://lustlost.blog.51cto.com/2600869/943110)

[iptables四个表与五个链间的处理关系](http://blog.sina.com.cn/s/blog_71261a2d0100xaob.html)