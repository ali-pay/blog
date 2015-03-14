---
title: ld.so 内部 segfault
date: '2015-03-01'
description:
permalink: '/wired-libso-segfault'
categories:
- Code
tags:
- Linux
---

链接了某个动态库。然后程序一启动就崩溃了，gdb 给出的 Traceback 是：

```
Program received signal SIGSEGV, Segmentation fault.
0x0000000000005496 in ?? ()
	(gdb) bt
#0  0x0000000000005496 in ?? ()
#1  0x00007ffff7af3ec9 in ?? ()
#2  0x00007fffffffe310 in ?? ()
#3  0x00007ffff7de7072 in elf_machine_rela (reloc=0x7ffff6adc5f8, reloc=0x7ffff6adc5f8, skip_ifunc=<optimized out>, reloc_addr_arg=<optimized out>,
		    version=<optimized out>, sym=0x7ffff6a8cb20, map=0x7ffff7fe9a00) at ../sysdeps/x86_64/dl-machine.h:285
#4  elf_dynamic_do_Rela (skip_ifunc=<optimized out>, lazy=<optimized out>, nrelative=<optimized out>, relsize=<optimized out>, reladdr=<optimized out>,
		    map=0x7ffff7fe9a00) at do-rel.h:137
#5  _dl_relocate_object (scope=<optimized out>, reloc_mode=<optimized out>, consider_profiling=<optimized out>, consider_profiling@entry=0) at dl-reloc.c:264
#6  0x00007ffff7dddafa in dl_main (phdr=<optimized out>, phdr@entry=0x400040, phnum=<optimized out>, phnum@entry=9, user_entry=user_entry@entry=0x7fffffffe448,
		    auxv=<optimized out>) at rtld.c:2204
#7  0x00007ffff7df1565 in _dl_sysdep_start (start_argptr=start_argptr@entry=0x7fffffffe530, dl_main=dl_main@entry=0x7ffff7ddb910 <dl_main>) at ../elf/dl-sysdep.c:249
#8  0x00007ffff7ddecf8 in _dl_start_final (arg=0x7fffffffe530) at rtld.c:332
#9  _dl_start (arg=0x7fffffffe530) at rtld.c:558
#10 0x00007ffff7ddb2d8 in _start () from /lib64/ld-linux-x86-64.so.2
#11 0x0000000000000001 in ?? ()
#12 0x00007fffffffe77d in ?? ()
#13 0x0000000000000000 in ?? ()
```

后来发现问题很无语，在 `ld` 命令链接的时候顺序很重要哦。

有问题的链接顺序：

```
ld -lA -Lxx -lB -lC
```

没问题的链接顺序：

```
ld -Lxx -lB -lA -lC
```

