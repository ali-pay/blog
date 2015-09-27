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

