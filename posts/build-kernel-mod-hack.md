---
title: 插入和当前 vermagic 不一致的内核模块
date: '2012-01-12'
description:
categories:
- Code
tags:
- Linux
- Kernel
---

嵌入式开发的时候，经常会有这种情况：

能找到 ROM，但是找不到这个 ROM 编译时候使用的内核源码和 arm-linux-gcc 工具链。但是我想自己写一个驱动，怎么办？

插入驱动模块的时候，insmod 系统会检查模块的 vermagic，vermagic 不对的话就插不进去。其实如果版本相近，这个限制是可有可无的。

内核模块是 elf 文件：

``` 
mod.ko: ELF 32-bit LSB relocatable, ARM, version 1 (SYSV), not stripped
```

模块中调用内核中 EXPORT_SYMBOL 的函数，在内核加载前，这些函数的地址都会被重定位。在 `cat /proc/kallsyms` 里面，能看到所有 EXPORT_SYMBOL 的函数。

``` 
root@WillSky:/lib/modules/3.4.43+# cat /proc/kallsyms
...
c0066688 t futex_wait_restart
c00666d4 t futex_wake
c006680c t free_pi_state
c00668d0 t futex_requeue
c0067748 T exit_pi_state_list
...
```

只要这个函数是存在的，就可以调用。甚至都可以自己写一个 .h 文件来声明这个函数，只要使用的数据结构和运行中的内核对得上就行。

可以先看一下 ROM 中正常的内核模块的 vermagic：

``` 
root@WillSky:/lib/modules/3.4.43+# modinfo gpio_sunxi
filename:       /lib/modules/3.4.43+/kernel/drivers/gpio/gpio-sunxi.ko
license:        GPL
description:    GPIO interface for Allwinner A1X SOCs
author:         Alexandr Shutko <alex@shutko.ru>
srcversion:     FAF074F47499E5A9DEFF530
depends:
intree:         Y
vermagic:       3.4.43+ preempt mod_unload modversions ARMv7 p2v8
```

然后弄一个版本相近的内核。ROM 中的内核是 3.4.43，我下载的是 3.2.18

然后修改 `include/linux/vermagic.h` 直接改成

``` 
#define VERMAGIC_STRING "3.4.43+ preempt mod_unload modversions ARMv7 p2v8 "
```

然后

``` 
make defconfig
make prepare
make scripts
```

再 make 自己的模块。

拷贝一个正常的模块，和 make 出来的模块，用 readelf 看一下。

``` 
arm-linux-readelf -a 正常模块.ko | head
arm-linux-readelf -a make出来的模块.ko | head
```

比较一下

``` 
# arm-linux-readelf -a mod.ko | head -50
ELF Header:
	Magic:   7f 45 4c 46 01 01 01 00 00 00 00 00 00 00 00 00
	Class:                             ELF32
	Data:                              2's complement, little endian
	Version:                           1 (current)
OS/ABI:                            UNIX - System V  << 保持一致
	ABI Version:                       0
	Type:                              REL (Relocatable file)
	Machine:                           ARM   << 保持一致
	Version:                           0x1		
	Entry point address:               0x0
	Start of program headers:          0 (bytes into file)
	Start of section headers:          53384 (bytes into file)
	Flags:                             0x5000000, Version5 EABI  << 保持一致
	Size of this header:               52 (bytes)
	Size of program headers:           0 (bytes)
…
```

如果 ABI 不一致的话，函数调用的时候会出问题。

说明编译模块的时候给 gcc 的选项不同。方法是，在 arch/arm/configs 里面找到型号相近的板子。然后 make xxxx_defconfig。也可以从 `/proc/config.gz` 复制一份。

``` 
cp /proc/config.gz .
gunzip config.gz
```

另外 CONFIG_MODVERSION 要设置为 n。

如果某些配置不匹配的话，会导致诡异的问题。比如我就在调用 `__wake_up` 函数的时候，会因为 NULL Pointer 而导致 kernel panic。我跟踪了一下代码发现，`spin_lock_t` 这个结构体中，如果开启 spin_lock 的 debug，就会多几个字段。而目标内核没有这几个字段，就出错了。如果遇到问题，多跟踪下代码，观察下 `CONFIG_xx` 的宏有哪些不一样。

# 参考

[解析 Linux 内核可装载模块的版本检查机制](http://www.ibm.com/developerworks/cn/linux/l-cn-kernelmodules/)

[insmod 源码分析](http://blog.chinaunix.net/uid-24734229-id-3393925.html)

[应用二进制接口](http://zh.wikipedia.org/zh-cn/应用二进制接口)