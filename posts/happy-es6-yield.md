---
title: Javascript 的 ES6 初体验
date: '2015-03-12'
description:
permalink: '/js-es6-try'
categories:
- Code
tags:
- Javascript
---

关于 ES6，最好的中文入门教程是阮一峰的 [这篇](http://es6.ruanyifeng.com/)。我感觉在实战中，最有效的一个改动是 `yield`。对比其 `yield`，首先吐槽下现有 Promise 的缺点。

# Promise 的吐槽

Promise 的确是解决回调的有效办法，可还是有局限性的。首先就是 Promise 本身的调用方式就不好看：

```
promise.then(function(value) {
	return anotherPromise();
}).then(function (value) {
  // success
}, function(err) {
  // failure
});
```

`then` 那块儿还算好理解，`return anotherPromise()` 初学者看了只会觉得这是什么鬼，算不上直观。

在实际写的过程中，如果有这样的操作：

```
var user1 = getUserFromDB(1);
var user2 = getUserFromDB(2);
var user3 = getUserFromDB(3);
doSomethingWith(user1, user2, user3);
```

转换成 Promise 是这样：

```
var user1, user2, user3;
getUserFromDB(1).then(function (u) {
	user1 = u;
}).then(function (u) {
	user2 = u;
}).then(function (u) {
	user3 = u;
}).then(function () {
	return doSomethingWith(user1, user2, user3);
});
```

这三个变量莫名其妙的放在外面，让人一眼看过去不知道在做什么。

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

谁看的明白这是啥子？

另外代码里面有循环的话，Promise 就很难办了。比如 Stackoverflow 上的 [这个问题](http://stackoverflow.com/questions/17217736/while-loop-with-promises)，几个答案给出的写法都是差强人意的。比如这个：

```
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

这么大费周章实现一个 `while (i <= 10)` 已经无力吐槽了。

好吧吐槽完毕，归根到底 Promise 还是比纯回调强一点的。

# yield & TJ co

其实单单看阮一峰那篇文章，还不能 100% 体会到 yield 好处。yield 和 Promise 要配合使用，缺一不可。在此强烈推荐 TJ 的 [co](https://www.npmjs.com/package/co)。 

上面的代码用 TJ 的 co 库和 yield 重新写一遍就好看多了：

代码1

```
var user1 = getUserFromDB(1);
var user2 = getUserFromDB(2);
var user3 = getUserFromDB(3);
doSomethingWith(user1, user2, user3);
```

```
co(function *() {
	var user1 = yield getUserFromDB(1);
	var user2 = yield getUserFromDB(2);
	var user3 = yield getUserFromDB(3);
	yield doSomethingWith(user1, user2, user3);
});
```

代码2

```
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

```
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

co 的核心就是两个：

- 在 `function *` 里面 yield Promise
- 把 `function *` 包装成 Promise 返回

短小精干易用。

另外，类似 bookshelf.js 的 ORM 的 API 默认返回的都是 Promise，是可以直接被 co 使用的。

# async/await

在阮一峰的文章里面，提到了 async/await 这个属于 ES7 标准了，其实这种写法是比 yield 更好的。但目前只有 traceur 和 regenerator 这类把 ES6/7 Javascript 编译成 ES5 的框架可以使用。

# 说点题外话

说实话我一开始打算用 nodejs 做后端，刚开始写回调的就已经写到有点崩溃了。

网上的人大多鼓吹一门语言/框架有多好，库有多少，但很少人直面它的问题。即便是在 nodejs 的热门项目中，也是各种回调不断。这些作者真的没有意识到问题吗，还是不愿意吐槽去改正？
用了 Promise 之后我还是觉得有问题，才搜索出 ES6 新标准，才知道原来 Javascript 也有 coroutine，只是一直没放出来而已。。

至今我搞不懂为啥 nodejs 社区放弃了 luajit 而使用 v8 做默认引擎，我能想到的唯一理由是 v8 后台是 Google，够硬。。

有人吐槽 nodejs 的 API 设计，比如 fibjs 的作者，我深表认同。

比如 Socket 库的 API，相比 libuv 底层的 API 来说不太好。我不想用 `on('data')` 这样的接口，我只是希望读几个字节你就返回给几个字节，libuv 给了一个 onalloc 接口来指定返回的字节多少，nodejs 省掉了，搞到实现写二进制网络协议的时候还要再自己封装一个 Socket。

话说大部分人喜欢 nodejs 的原因，估计只是喜欢异步无锁的编程模型而已吧，其实这个也不是 nodejs 的专利，比如 [luvit](https://github.com/luvit/luvit) 就是拿的 luajit 来实现的，底层都是 libuv。反正我一直觉得 luajit 优于 v8。

 * 论性能有 benchmark 表明 luajit 比 v8 快。
 * 论特性 ES6 里面的 yield 和 WeakMap/Set，分别对应 coroutine 和 WeakTable，luajit 早就已经实现了。
 * 论和 native 的交互，luajit FFI 的性能和使用方式，比 v8 那种 C++ 的一坨 Wrapper 要好吧，即便是 lua 原生的 API 也比它强。

终归我也不排斥 Javascript，毕竟 n 多前后端的库在那儿摆着，npm 上的资源比 luajit 多太多了。

# 关于正确的 API 设计

在自己设计的协议中，封装了一个 Socket。其 Read / Write 的接口都是 Promise。如果读取或者写入失败，则 reject，否则 fulfill。
我自己也不清楚这是否为好的方式，但用起来比单纯的 callback 好了很多。

