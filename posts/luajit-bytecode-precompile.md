---
title: 使用 Luajit 将 lua 源文件预编译为 bytecode
date: '2015-03-18'
description:
categories:
- Code
tags:
- Luajit
---

在 Stackoverflow 上面有 [一个问题](http://stackoverflow.com/questions/11317269/how-to-compile-lua-scripts-into-a-single-executable-while-still-gaining-the-fas)
怎样把 lua 脚本编译为一个可执行文件？

然后 Luajit 的作者 Mike Pall 回答了这个问题：

先把 lua 文件编译成 .o 文件

```
for f in *.lua; do
	luajit -b $f `basename $f .lua`.o
done
ar rcus libmyluafiles.a *.o
```

然后做成一个大的静态库再链接，ld 选项为

```
-Wl,--whole-archive -lmyluafiles -Wl,--no-whole-archive -Wl,-E`
```

然后在 lua 里这样使用

```
local foo = require("foo")
```

昨天我测试了一下，发现它的原理是把 lua 编译成字节码，*但不是机器码*，字节码在 `.o` 文件里以一个全局变量的形式存在。

```
$ readelf -s a.obj
Symbol table '.symtab' contains 2 entries:
 Num:    Value          Size Type    Bind   Vis      Ndx Name
0: 0000000000000000     0 NOTYPE  LOCAL  DEFAULT  UND
1: 0000000000000000    39 OBJECT  GLOBAL DEFAULT    4 luaJIT_BC_a
```

`luaJIT_BC_a` 变量里面存放着 a.lua 的字节码。

但这样会带来一个问题，不能用 `require('./a.lua')` 这样的方式使用脚本了，如果使用和 nodejs 类似的方式放置源文件，可能会不方便。

同时，luajit 支持输出成各种格式的 .o

```
$ luajit -b a.lua -a mips a.o && file a.o
a.o: ELF 32-bit MSB  relocatable, MIPS, MIPS-I version 1 (SYSV), not stripped

$ luajit -b a.lua -a arm a.o && file a.o
a.o: ELF 32-bit LSB  relocatable, ARM, version 1 (SYSV), not stripped

$ luajit -b a.lua -a x64 a.o && file a.o
a.o: ELF 64-bit LSB  relocatable, x86-64, version 1 (SYSV), not stripped
```

还是非常强大地。

