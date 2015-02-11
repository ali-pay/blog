---
title: lua + libuv 的体验（续）
date: '2014-11-28'
description:
categories:
- Code
tags:
- Lua
- Libuv
---

近期重构了代码，同时看了一下 libuv 的底层实现。发现了一些更好的结合方式。

# libuv 的 loop

代码总是运行在某个操作完成后调用里，如果没有操作要完成，uv 的 loop 就结束了。我在 uv_run_loop 执行前，指定了一个 read，和两个 write。然后 uv 在 loop 中对这三个操作 epoll，然后分别执行他们的回调。

在这些回调中，如果没有另外的操作了，没有定时器、读写，loop 就结束了。

	uv__run_idle
	uv__run_prepare
	uv__run_io_polling
	uv__run_check
	uv__run_closing_handle

这是 uv 源码中的执行顺序。其中 check 的定义是 “在 io 操作完成后检查有没有其他要做的东西”。几乎所有代码都是在 io polling 中被执行的。即 “程序的本质就是输入和输出”，这种设计很直观，和 OS 内核中的最底层中断处理类似。

# 关于 setImmediate

直到真正需要用到的时候，才感受到这个东西的用处。在前端浏览器中，这个就是 setTimeout(fn, 0)。在 nodejs 中就是 process.nextTick（setImmediate 近期也支持了）。

它的作用是：把闭包放到下一次调用中执行。

异步编程中不能大量的递归调用（不光是异步编程中）。一般的函数也不会设计成可以重入的，就是不会出现 `A() -> B() -> C() -> A()` 这种情况。异步编程本身就是为了无锁，减轻大脑负担，不能把事情变得复杂。

可能遇到的情况就是：

	fetch_song(function (song)
		...
	end)

这个函数有几种实现，有可能是从 HTTP 下载，也有可能是直接取现有的。如果是后者，我直接在 fetch_song 函数里面执行了回调。就由可能在后续的调用中出现 `A() -> B() -> C() -> A()` 的问题。因为实际情况很有可能是这样：

	fetch_song(function (song)
		...
		if song == nil then
			fetch_song(...)
		end
	end)

很可能就一直递归下去了。如果不马上回调，仿佛是经过了一次飞速的 IO 以后再回调，就没事儿了。

setImmediate 就是做这个事情的。它实现非常简单，就是把函数挂在一个链表上，在 IO 完成的前后顺序执行就可以了。只是把函数挪了一个位置执行，没有性能上的问题。

经过研究发现，在 io polling 之后的 check 中和之前的 prepare 中执行 immediate 的调用是很合适的。我不清楚 nodejs 怎么实现的，不过应该方式是一样的。

# REGISTRYINDEX

lua 内置了一个表 REGISTRYINDEX。这个表叫做 “注册表”（倒是跟 Windows 的注册表有点像的说）。

云风的 blog 里面说了一种方法。以 C 的指针的 lightuserdata 为 key，在 REGISTRYINDEX 表中反查 lua 中的变量。这种方法很不错。

# 在 uv_thread 中 xmove

lua 并不原生支持多线程。它的 coroutine 是单线程的。`lua_newthread` 和 `lua_xmove` 是不能用在 uv_thread 中的，实测过，运行中出错。

解决办法是自己封装一层，逐个复制，如果遇到 table 则遍历 table 复制。略过 function 和 userdata。
