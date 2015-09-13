---
title: 关于异步
date: 2015-09-11
description:
permalink: '/about-async'
categories:
- Code
tags:
- DesignPattern
---

去年，在做一个智能硬件项目，CPU 是低功耗的 MIPS，将来换了低成本方案后 CPU 可能降为 300-500Mhz，内存可能降为 32M。

这个条件限制很大，最终决定用 lua + libuv 照着 node.js 撸了一个小框架（做了一半才知道有 luvit），同时用 node.js 完成服务端。

这是一个折腾的开始，这种单线程异步模型有优点也有缺点。

# LV0: Callback hell

这种多层嵌套的 callback 代码就是 callback hell：

``` js
openFile(xx, function () {
	readFile(xx, function () {
		writeFile(xx, function () {
			anotherWrite(xx, function () {
			});
		});
	});
})
```

这个是 node.js 的最大问题，写 50 行以下的代码可能没啥感觉，业务逻辑复杂就坑爹了。

Express.js 的作者 TJ（同是 co 的作者）也表示 node.js 有时候会 callback 两次或者压根没有 callback，哥不干了，哥玩 Golang 去了。

node.js 社区也有很多人讨论过了，比较好的解决办法是 Promise。

# LV1: Promise

Promise 能解决一部分问题，可还是有不少局限性的。

首先就是不直观：

``` js
promise.then(function(value) {
	return anotherPromise();
}).then(function (value) {
  // success
}, function(err) {
  // failure
});
```

在实际写的过程中，如果有这样的操作：

``` js
var user1 = getUserFromDB(1);
var user2 = getUserFromDB(2);
var user3 = getUserFromDB(3);
doSomethingWith(user1, user2, user3);
```

转换成 Promise 是这样：

``` js
var user1, user2, user3;
getUserFromDB(1).then(function (u) {
	user1 = u;
  	return getUserFromDB(2);
}).then(function (u) {
	user2 = u;
    return getUserFromDB(3);
}).then(function (u) {
	user3 = u;
	return doSomethingWith(user1, user2, user3);
});
```

原来只有四行的。

另外，如果有这样的函数。

``` 
function operation() {
	var person = getPersonFromDB();
	if (!person)
		return;

	var book = person.getBook();
	if (!book)
		return;

	return book.getPage(13);
}
```

转换成 Promise 就是：

``` 
function operation() {
	return getPersonFromDB().then(function (person) {
		if (person == null)
			return Promise.resolve(null);

		return person.getBook().then(function (book) {
			if (book == null)
				return Promise.resolve(null);

			return book.getPage(13);
		});
	});
}
```

同样有嵌套 callback 的问题。

代码里面有循环的话，Promise 也很难办。比如 Stackoverflow 上的 [这个问题](http://stackoverflow.com/questions/17217736/while-loop-with-promises)，几个答案给出的写法都是差强人意的。比如这个：

``` js
function loop(promise, fn) {
	return promise.then(fn).then(function (wrapper) {
		return !wrapper.done ? loop(Q(wrapper.value), fn) : wrapper.value;
	});
}

loop(Q.resolve(1), function (i) {
	console.log(i);
	return {
		done: i > 10,
		value: i++
	};
}).done(function () {
	console.log('done');
});
```

一个 `while (i <= 10)` 写成这样真的大丈夫？

但归根到底 Promise 还是比纯回调强一点的。

# LV2: yield, async/await

Javascript ES6 和 ES7 标准中有更好的解决办法。

关于 ES6 的 yield，最好的中文入门教程是阮一峰的 [这篇](http://es6.ruanyifeng.com/)。在这篇文章中还不能 100% 体会到 yield 好处，因为 yield 和 Promise 要配合使用，推荐 TJ 的 [co](https://www.npmjs.com/package/co) 库。 

上面的代码用 co 重写一遍就好看多了：

代码1

``` js
var user1 = getUserFromDB(1);
var user2 = getUserFromDB(2);
var user3 = getUserFromDB(3);
doSomethingWith(user1, user2, user3);
```

``` js
co(function *() {
	var user1 = yield getUserFromDB(1);
	var user2 = yield getUserFromDB(2);
	var user3 = yield getUserFromDB(3);
	yield doSomethingWith(user1, user2, user3);
});
```

代码2

``` js
function operation() {
	var person = getPersonFromDB();
	if (person == null)
		return;

	var book = person.getBook();
	if (book == null)
		return;

	return book.getPage(13);
}
```

``` js
function operation() {
	return co(function *() {
		var person = yield getPersonFromDB();
		if (!person)
			return;

		var book = person.getBook();
		if (book == null)
			return;

		return book.getPage(13);
	});
}
```

比 Promise 的简单了，基本和同步的代码一样了。

co 的核心就是两个：

- 在 `function *` 里面 yield Promise
- 把 `function *` 包装成 Promise 返回

很多 node.js 的库默认返回的都是 Promise，可以直接被 co 使用。

ES7 的 `async/await` 等于把 `co.wrap(function *)` 和 `yield` 替换成 `async` 和 `await`，本质还是一样的。

可惜这种方式也是有缺点的：实际写代码的时候，经常会忘记写 `await/yield`，漏写一个就坑爹了，同步变异步了，返回类型变成 Promise 了，后续全乱了。我觉得这不怪我，毕竟人的思路是**同步**的，90% 的业务逻辑的也是**同步**的。

另外，如果想在 foreach 里面做点东西，就只能写成这样子：

``` 
yield arr.map(co.wrap(function *(node) {
	yield node.xxxoo();
}));
```

# LV3: gevent, fibjs, libtask

node.js 有个根本限制就是 `yield` 只能放在 `function *` 里面，这就决定了 node.js 只可能做出 `async/await` 这样的机制（如果不改底层的话），必须声明哪个函数是 async 的。

而 Python 的 `yield` 没这个问题，lua 的 coroutine 也没有。

所以 Python 的 gevent 实现了挺好的设计，完全摆脱了 Promise，代码能按照同步的方式写，和日常使用 Python 的姿势没什么区别，而同时具备异步的好处：

``` python
address = ('localhost', 9000)
message = ' '.join(sys.argv[1:])
sock = socket.socket(type=socket.SOCK_DGRAM)
sock.connect(address)
print('Sending %s bytes to %s:%s' % ((len(message), ) + address))
sock.send(message.encode())
data, address = sock.recvfrom(8192)
print('%s:%s: got %r' % (address + (data, )))
```

fibjs 通过重新封装 v8 也达到了同样的目的：

``` js
var coroutine = require("coroutine");
function dang(n){
  while(true) {
    console.log('DANG %d...', n);
    coroutine.sleep(1000);
  }
}
for(var i = 0; i < 5; i ++)
  coroutine.start(dang,i);
while(true)
  coroutine.sleep(1000);
```

其实 fibjs 挺牛逼的，benchmark 已经超过 node.js 数倍了，可惜由于生态问题很多人不敢用。

除了脚本以外 C 也是可以的。保存寄存器状态切换堆栈即可，和 OS 调度时候切换进程一个做法，glibc 已经有了封装好的 `makecontext/swapcontext`，纯用户态的。

libtask 是 Golang 的作者之一设计的 C coroutine 库，在 C 中实现了 gevent 类似的效果，基于  `makecontext/swapcontext`。

还有一个企鹅开源的 libco 库，也是类似的思路，还支持 hook read/write syscall 把它们改变成异步模式。

# LV4: Yield across c-call boundary

项目中有不少 IO 相关的 C 代码，一直在思考如何把这部分代码和 lua 结合的好一些。一般做法是新开一个线程，里面进行各种 C 的 IO 操作，然后和 lua 的线程用  `uv_send_async`  通信，但理想的办法应该是一个 C 和 lua 在同一个线程中，没有必要开两个线程。

关键就是如何把 lua 中的 coroutine 和 C 中的 coroutine 比较好的融合在一起。现有的方案是：

- lua 5.2 开始支持的 `lua_callk`，云风大大的 [这篇文章](http://blog.codingnow.com/2012/06/continuation_in_lua_52.html) 有详细描述。大体就是让你能在 C 中 lua_call 完 lua 后然后又在 lua 中被 yield 后再 resume 的时候能返回 lua_call 后的位置继续
- Coro，那篇文章里也有讲。给每个 lua 的 coroutine 分配了 C stack，彻底解决了在 C 里面 yield 的问题

但我觉得这两种方式都有点问题：

- lua_callk 并不是真正的 coroutine，适用范围有限，无法支持在 C 里面 lua_yield 不立即返回这种情况
- Coro 解决得彻底，但理论上并非每一个 lua coroutine 都需要 C stack，因为不是每个 coroutine 都会在 C 里面 yield。另外 C 里面的频繁 IO 操作最好不要每次都到 lua 里 yield 一圈再回来

最终，在被坑成爹之后，我想做一个更好的库：

# LCL (Lightweight Concurrency Library)

大概的设计如下：

- C 部分和 libtask 类似，使用 makecontext/swapcontext 配合 libuv 实现

``` C
void loop1() {
	void *fp = ioOpen("/dev/gsensor"); // uv_fs_open(); swapcontext();
	char buf[512];
	for (;;) {
		ioRead(fp, buf, sizeof(buf)); // uv_read(); swapcontext();
		...
	}
	ioClose(fp); // uv_close(); swapcontext();
}
coStart(loop1); // makecontext(); swapcontext();
```

- lua 中能任意调用存在 yield 操作的 C 函数，反过来也一样，都不会阻塞线程
- C 中的执行流程和效率与 lua 没有任何关系

``` C
// in C
int readAndCalc(char (*cb)(int i)) {
	char a, b, c;
	ioRead(stdin, &a, sizeof(a));
	ioRead(stdin, &b, sizeof(b));
  	c = cb();
	return a+b+c;
}
// in Lua
local ret = ffi.C.readAndCalc(function ()
  co.sleep(1)
  return 42
end)
print('sum=', ret)
```

- 实现 chan / worker / select：worker 类似 [WebWoker](https://developer.mozilla.org/en-US/docs/Web/API/Web_Workers_API/Using_web_workers) 有独立的 OS thread，chan 模仿 Golang，是跨 worker 通信的唯一方式
- 尽量不改动 luajit 代码
- 名字缩写为 LCL（就是 EVA 里的 LCL！

从 lua 到 C 的过程是：

- 在 ffi.C 调用 fn 的时候 `makecontext(fn)` 然后 `swapcontext` 进入 fn，等它再 `swapcontext` 回来的时候返回 lua， 这一步是非阻塞的
- 返回 lua 中就立即 `coroutine.yield()` 等待 fn 结束
- 然后 fn 在 libuv 中各种 IO：这一步和 lua 没有任何关系
- fn 结束的时候，在 lua 中 `coroutine.resume()` 刚刚 fn 的返回值

其中 `makecontext` 的 C stack 可以重用，而且只有调用了 C 而且在里面 yield 了的 lua coroutine 才给分配 C stack。

这种方式比起原生的 ffi.C 调用，多了在 C 和 luajit 中各两次 context switch 的开销，如果只是单纯调用 libuv 的某个函数，C 的切换可以省掉；如果 C 中没有 yield，lua 的切换可以省掉

从 C callback 到 lua 的过程比较复杂。luajit 的做法大概是实时生成一个 callback 函数的 machine code，内容是把 C 的参数转换成 lua 的 push 到栈上，再 call。如果在 callback 中有 `coroutine.yield`  操作，会导致 `attempt to yield across C-call boundary` 错误。如果要绕过它，必须等 ffi 调用完成后再 callback。如果要绕过这个限制，解决办法是：

- ffi.C 调用的时候把 cb 替换成 fakeCb
- fakeCb 在被调用的时候先 yield。在 next tick 里把 cb 和参数 `coroutine.resume()` 传给等待着的 lua coroutine，然后原 cb 在 lua 里被调用

需要修改 luajit 的代码，暂时没法支持。

另外 luajit 和 C 里 context switch 的开销都有人测过：

`makecontext/swapcontext` 的开销是 [每秒百万次的级别](http://1234n.com/?post/aukxju)。另外 [这篇文章](http://rethinkdb.com/blog/making-coroutines-fast/) 表明 glibc 自带的 `swapcontext` 过程中调用了 syscall `sigprocmask()`，这个完全没必要，显著拉低性能，省掉以后目测性能提高几倍。

luajit 的性能相当感人，[每秒能到千万级](http://www.blogjava.net/killme2008/archive/2010/03/02/314264.html)（而且这篇文章中的测试机比上一篇还慢点）。

不负责任的猜测，C context switch 的速度或许比不上 luajit，保存一堆寄存器和浮点处理器状态的速度比不上 luajit 可能只改几个指针，也许直接在 luajit 里面 IO 会比在 C 里快。但这个库的意义肯定不光是为了效率，单论效率 libuv 这种纯 callback 肯定是最快的，运行效率和开发效率之间是需要折衷的。

LCL 正在努力开发中。
