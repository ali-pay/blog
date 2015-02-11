---
title: 关于在 Linux 下多个不相干的进程互斥访问同一片共享内存的问题  
date: '2014-11-04'
description:
categories:
- Code
tags:
- Linux
---

这里的“不相干”，定义为：

 - 这几个进程没有父子关系，也没有 Server/Client 关系
 - 这一片共享内存一开始不存在，第一个要访问它的进程负责新建
 - 也没有额外的 daemon 进程能管理这事情

看上去这是一个很简单的问题，实际上不简单。有两大问题：

## 进程在持有互斥锁的时候异常退出 ##

如果用传统 IPC 的 semget 那套接口，是没法解决的。实测发现，down 了以后进程退出，信号量的数值依然保持不变。

用 pthread （2013年的）新特性可以解决。在创建 pthread mutex 的时候，指定为  ROBUST 模式。

    pthread_mutexattr_t ma;
 
    pthread_mutexattr_init(&ma);
    pthread_mutexattr_setpshared(&ma, PTHREAD_PROCESS_SHARED);
    pthread_mutexattr_setrobust(&ma, PTHREAD_MUTEX_ROBUST);
  
    pthread_mutex_init(&c->lock, &ma);

注意，pthread 是可以用于多进程的。指定 PTHREAD_PROCESS_SHARED 即可。

关于 ROBUST，官方解释在：

http://pubs.opengroup.org/onlinepubs/9699919799/functions/pthread_mutexattr_setrobust.html

需要注意的地方是：

    如果持有 mutex 的线程退出，另外一个线程在 pthread_mutex_lock 的时候会返回 EOWNERDEAD。这时候你需要调用 pthread_mutex_consistent 函数来清除这种状态，否则后果自负。

写成代码就是这样子：

    int r = pthread_mutex_lock(lock);
    if (r == EOWNERDEAD)
      pthread_mutex_consistent(lock);

所以要使用这个新特新的话，需要比较新的 GCC ，要 2013 年以后的版本。

好了第一个问题解决了。我们可以在初始化共享内存的时候，新建一个这样的 pthread mutex。但是问题又来了：

## 怎样用原子操作新建并初始化这一片共享内存？ ##

这个问题看上去简单至极，不过如果用这样子的代码：

    void *p = get_shared_mem();
    if (p == NULL)
        p = create_shared_mem_and_init_mutex();
    lock_shared_mem(p);
    ....

是不严谨的。如果共享内存初始化成全 0，那可能碰巧还可以。但我们的 mutex 也是放到共享内存里面的，是需要 init 的。

想象一下四个进程同时执行这段代码，很可能某两个进程发现共享内存不存在，然后同时新建并初始化信号量。某一个 lock 了 mutex，然后另外一个又 init mutex，就乱了。

可见，在 init mutex 之前，我们就已经需要 mutex 了。问题是，哪来这样的 mutex？前面已经说了传统 IPC 没法解决第一个问题，所以也不能用它。

其实，Linux 的文件系统本身就有这样的功能。

首先 shm_open 那一系列的函数是和文件系统关联上的。

    ~ ll /dev/shm/

其实 /dev/shm 是一个 mount 了的文件系统。这里面放的就是一堆通过 shm_open 新建的共享内存。都是以文件的形式展现出来。可以 rm，rename，link 各种文件操作。

其实 link 函数，也就是硬链接。是完成“原子操作”的关键所在。

搞过汇编的可能知道 CMPXCHG 这类（两个数比较，符合条件则交换）指令，是原子操作内存的最底层指令，最底层的信号量是通过它实现的。

而 link 系统调用，类似的，是系统调用级，原子操作文件的最底层指令。处于 link 操作中的进程即便被 kill 掉，在内核中也会完成最后一次这次系统调用，对文件不会有影响，不存在 “link 了一半” 这种状态，它是“原子”的。

伪代码如下：

    shm_open("ourshm_tmp", ...);
    // ... 初始化 ourshm_tmp 副本 ...

    if (link("/dev/shm/ourshm_tmp", "/dev/shm/ourshm") == 0) {
       // 我成功创建了这片共享内存
    } else {
       // 别人已经创建了
    }
    shm_unlink("ourshm_tmp");

首先新建初始化一份副本。然后用 link 函数。

最后无论如何都要 unlink 掉副本。

## 参考代码 ##

[GitHUB](https://github.com/K-B-Z/kbz-event)

