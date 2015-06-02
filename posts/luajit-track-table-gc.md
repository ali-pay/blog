---
title: 在 Luajit 2.0 中跟踪 table 的 gc
date: '2015-03-18'
description:
permalink: '/luajit-track-table-gc'
categories:
- Code
tags:
- Luajit
---

Luajit 2.0 相当于 lua 的 5.1 版本，默认是没有 lua 5.2 以上支持的 `metatable` 中的 `__gc` 方法。默认是不能跟踪 table 的 gc 的。

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

只需要把一个 FFI 对象置于 table 中即可。

