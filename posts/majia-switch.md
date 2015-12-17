---
title: 马甲切换器
date: '2015-11-27'
description:
categories:
- Code
tags:
- Javascript
---

今天做了一个马甲切换器，点一下就能切换 Facebook/Twitter/豆瓣/微博 的账号。
原理是 Chrome 插件有操作 Cookie 的权限，这个权限比 browser 里的大，可以设置 Cookie 的 HTTP-only 属性。
所以只要把某个网站的所有 Cookie 全替换掉就相当于切换账号了。

![](/img/majia-show.png)

# 安装方法

右键点击[这里](/img/majia.crx)选择另存为保存到本地

在 Chrome 的设置里找到『扩展程序』然后把 majia.crx 拖拽进去即可

如果能翻墙，请在官方 Chrome Store 安装，点[这里](https://chrome.google.com/webstore/detail/%E9%A9%AC%E7%94%B2/mbagihlilbaofbfpmnicoonnebmhohmm)

