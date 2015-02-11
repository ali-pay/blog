---
title: 用 Golang 通过 netlink 监听 udev 事件
date: '2013-11-16'
description:
categories:
- Code
tags:
- Golang
---

想做一个功能，在 Ubuntu 下监视 U 盘插入，然后给 U 盘自动格式化分区然后安装定制系统。

一开始我大概知道这部分是 Udev 负责的。

#### 使用 udevadm monitor 获取 U 盘插拔信息

在命令行输入 `udevadm monitor` 然后拔插 U 盘可以发现以下输出：

	root@lkartpopwcs-GrossePoint:/go-av/usbmon# udevadm monitor
	monitor will print the received events for:
	UDEV - the event which udev sends out after rule processing
	KERNEL - the kernel uevent
	

看了下 Udev 的 C API，发现比较繁琐，于是我想搞明白，Udev 最底层调用的是啥呢？

其中 `KERNEL - the kernel uevent` 一行说明，它是属于内核的 `uevent` 机制。

内核告诉用户“哪些设备插入或者拔出”就是通过 UEVENT 机制。UEVENT 机制在用户和内核之间的传递，使用的是 **netlink** 。

#### Netlink 简介（摘自 Wikipedia）

Netlink是套接字家族中的一员，主要用内核与用户空间的进程间、用户进程间的通讯。然而它并不像网络套接字可以用于主机间通讯，Netlink只能用于同一主机上进程通讯，并通过PID来标识它们。

Netlink被设计为在Linux内核与用户空间进程传送各种网络信息。网络工具iproute2利用 Netlink从用户空间与内核进行通讯。Netlink由一个在用户空间的标准的Socket接口和内核模块 提供的内核API组成。Netlink的设计比ioctl更加灵活，Netlink使用了AF_NETLINK Socket 家族。

现在 netlink 也用来传输 UEVENT 事件。

#### 用 Golang 监听 UEVENT 事件

调用 netlink 的 C 代码比较简单，类似于 UDP Socket。翻译成 Golang 如下：

	package main

	import (
		"log"
		"syscall"
		"os"
	)
	
	const NETLINK_KOBJECT_UEVENT = 15
	const UEVENT_BUFFER_SIZE = 2048
	
	func main() {
		fd, err := syscall.Socket(
			syscall.AF_NETLINK, syscall.SOCK_RAW,
			NETLINK_KOBJECT_UEVENT,
		)
		if err != nil {
			log.Println(err)
			return
		}
	
		nl := syscall.SockaddrNetlink{
			Family: syscall.AF_NETLINK,
			Pid: uint32(os.Getpid()),
			Groups: 1,
		}
		err = syscall.Bind(fd, &nl)
		if err != nil {
			log.Println(err)
			return
		}
	
		b := make([]byte, UEVENT_BUFFER_SIZE*2)
		for {
			n, err2 := syscall.Read(fd, b)
			log.Println(n, err2)
		}
	}

当插拔 U 盘的时候，会有输出。

#### 解析 UEVENT_BUFFER 的格式

格式如下：

![](/img/hexdump-uevent-buffer.png)

它是以 0 结尾的多个字符串。使用下面的代码可以处理：

	func parseUBuffer(arr []byte) (act, dev, subsys string) {
		j := 0
		for i := 0; i < len(arr)+1; i++ {
			if i == len(arr) || arr[i] == 0 {
				str := string(arr[j:i])
				a := strings.Split(str, "=")
				if len(a) == 2 {
					switch a[0] {
					case "DEVNAME":
						dev = a[1]
					case "ACTION":
						act = a[1]
					case "SUBSYSTEM":
						subsys = a[1]
					}
				}
				j = i+1
			}
		}
	
		return
	}


#### 测试

拔插 U 盘后输出：

	2013/11/22 18:10:55 uevent  usb add
	2013/11/22 18:10:55 uevent  usb add
	2013/11/22 18:10:55 uevent  usb add
	2013/11/22 18:10:55 uevent  scsi add
	2013/11/22 18:10:55 uevent  scsi_host add
	2013/11/22 18:10:55 uevent  scsi_host add
	2013/11/22 18:10:56 uevent  scsi add
	2013/11/22 18:10:56 uevent  scsi add
	2013/11/22 18:10:56 uevent  scsi_disk add
	2013/11/22 18:10:56 uevent  scsi_device add
	2013/11/22 18:10:56 uevent sg1 scsi_generic add
	2013/11/22 18:10:56 uevent bsg/6:0:0:0 bsg add
	2013/11/22 18:10:56 uevent bsg/6:0:0:0 bsg add
	2013/11/22 18:10:56 uevent sdb block add
	2013/11/22 18:10:56 uevent sdb1 block add
	2013/11/22 18:10:56 uevent sdb2 block add
	2013/11/22 18:10:56 uevent sdb3 block add
	2013/11/22 18:11:06 uevent bsg/6:0:0:0 bsg remove
	2013/11/22 18:11:06 uevent sg1 scsi_generic remove
	2013/11/22 18:11:06 uevent sg1 scsi_device remove
	2013/11/22 18:11:06 uevent sg1 scsi_disk remove
	2013/11/22 18:11:06 uevent sdb3 block remove
	2013/11/22 18:11:06 uevent sdb2 block remove
	2013/11/22 18:11:06 uevent sdb1 block remove
	2013/11/22 18:11:06 uevent sdb1 block remove
	2013/11/22 18:11:06 uevent sdb block remove
	2013/11/22 18:11:06 uevent  scsi remove
	2013/11/22 18:11:06 uevent  scsi remove
	2013/11/22 18:11:07 uevent  scsi_host remove
	2013/11/22 18:11:07 uevent  scsi remove
	2013/11/22 18:11:07 uevent  usb remove
	2013/11/22 18:11:07 uevent bus/usb/001/003 usb remove

#### 参考资料

[uevent 分析](http://blog.csdn.net/walkingman321/article/details/5917737)

[Netlink 维基百科](http://zh.wikipedia.org/zh-cn/Netlink)

[PF_NETLINK应用实例](http://www.cnblogs.com/hoys/archive/2011/04/09/2010759.html)

[Netlink实现Linux内核与用户空间通信](http://www.cpplive.com/html/1362.html)
