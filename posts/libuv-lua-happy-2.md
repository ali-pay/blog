---
title: lua + libuv 的初体验
date: '2014-11-28'
description:
categories:
- Code
tags:
- Lua
- Libuv
---

用了 libuv + lua 后相当于重新封装了一个简单的 node.js，近期重构了代码，同时看了一下 libuv 的底层实现。发现了一些更好的封装方式。

# libuv 的 loop

代码总是运行在某个操作完成后调用里，如果没有操作要完成，uv 的 loop 就结束了。我在 uv_run_loop 执行前，指定了一个 read，和两个 write。然后 uv 在 loop 中对这三个操作 epoll，然后分别执行他们的回调。

在这些回调中，如果没有另外的操作了，没有定时器、读写，loop 就结束了。

``` 
uv__run_idle
uv__run_prepare
uv__run_io_polling
uv__run_check
uv__run_closing_handle
```

这是 uv 源码中的执行顺序。其中 check 的定义是 “在 io 操作完成后检查有没有其他要做的东西”。几乎所有代码都是在 io polling 中被执行的。

# 关于 setImmediate

直到真正需要用到的时候，才感受到这个东西的用处。在前端浏览器中，这个就是 setTimeout(fn, 0)。在 nodejs 中就是 process.nextTick（setImmediate 近期也支持了）。

它的作用是：把闭包放到下一次调用中执行。

异步编程中不能大量的递归调用（不光是异步编程中）。一般的函数也不会设计成可以重入的，就是不会出现 `A() -> B() -> C() -> A()` 这种情况。异步编程本身就是为了无锁，减轻大脑负担，不能把事情变得复杂。

可能遇到的情况就是：

``` 
fetch_song(function (song)
	...
end)
```

这个函数有几种实现，有可能是从 HTTP 下载，也有可能是直接取现有的。如果是后者，我直接在 fetch_song 函数里面执行了回调。就由可能在后续的调用中出现 `A() -> B() -> C() -> A()` 的问题。因为实际情况很有可能是这样：

``` 
fetch_song(function (song)
	...
	if song == nil then
		fetch_song(...)
	end
end)
```

很可能就一直递归下去了。如果不马上回调，仿佛是经过了一次飞速的 IO 以后再回调，就没事儿了。

setImmediate 就是做这个事情的。它实现非常简单，就是把函数挂在一个链表上，在 IO 完成的前后顺序执行就可以了。只是把函数挪了一个位置执行，没有性能上的问题。

经过研究发现，在 io polling 之后的 check 中和之前的 prepare 中执行 immediate 的调用是很合适的。我不清楚 nodejs 怎么实现的，不过应该方式是一样的。

# REGISTRYINDEX

lua 内置了一个表 REGISTRYINDEX。这个表叫做 “注册表”（倒是跟 Windows 的注册表有点像的说）。

云风的 blog 里面说了一种方法。以 C 的指针的 lightuserdata 为 key，在 REGISTRYINDEX 表中反查 lua 中的变量。这种方法很不错。

# 在 uv_thread 中 xmove

lua 并不原生支持多线程。它的 coroutine 是单线程的。`lua_newthread` 和 `lua_xmove` 是不能用在 uv_thread 中的，实测过，运行中出错。

解决办法是自己封装一层，逐个复制，如果遇到 table 则遍历 table 复制。略过 function 和 userdata。

# 在 luajit 中跟踪 table 的 gc

Luajit 2.0 相当于 lua 的 5.1 版本，默认是没有 lua 5.2 以上支持的 `metatable` 中的 `__gc` 方法。默认是不能跟踪 table 的 gc 的。

但是 Luajit 可以跟踪 FFI 创建的对象的 gc，所以用一个小技巧就可以支持 table 对象的 gc 了：

``` 
local ffi = require('ffi')

ffi.cdef [[
typedef struct {} fake;
]]

local t = {}
t.__trackGc = ffi.gc(ffi.new('fake'), function ()
    print(t, 'gc')
end)

t = nil

collectgarbage()
print('end')
```

# 将 luajit 源文件预编译为 bytecode

在 Stackoverflow 上面有 [一个问题](http://stackoverflow.com/questions/11317269/how-to-compile-lua-scripts-into-a-single-executable-while-still-gaining-the-fas) 怎样把 lua 脚本编译为一个可执行文件？

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

昨天我测试了一下，发现它的原理是把 lua 编译成字节码（非机器码），字节码在 `.o` 文件里以一个全局变量的形式存在。

``` 
$ readelf -s a.obj
Symbol table '.symtab' contains 2 entries:
 Num:    Value          Size Type    Bind   Vis      Ndx Name
0: 0000000000000000     0 NOTYPE  LOCAL  DEFAULT  UND
1: 0000000000000000    39 OBJECT  GLOBAL DEFAULT    4 luaJIT_BC_a
```

`luaJIT_BC_a` 变量里面存放着 a.lua 的字节码。

但这样会带来一个问题，不能用 `require('./a.lua')` 这样的方式使用脚本了，如果使用和 nodejs 类似的方式放置源文件，可能会不方便。

同时，luajit 支持输出成各种格式的 .o。也可以用 -n 替换掉默认的名字。

``` 
$ luajit -b a.lua -a mips a.o && file a.o
a.o: ELF 32-bit MSB  relocatable, MIPS, MIPS-I version 1 (SYSV), not stripped

$ luajit -b a.lua -a arm a.o && file a.o
a.o: ELF 32-bit LSB  relocatable, ARM, version 1 (SYSV), not stripped

$ luajit -b a.lua -a x64 a.o && file a.o
a.o: ELF 64-bit LSB  relocatable, x86-64, version 1 (SYSV), not stripped
```