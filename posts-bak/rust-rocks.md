---
title: Rust Rocks
date: '2015-04-25'
description:
permalink: '/rust-rocks'
categories:
- Code
tags:
- Rust
---

近期研究了一下 Rust（1.0.0-beta3 刚出），发现其是一门潜力极大的语言。
针对我很关心的特性，我分别吐槽一下在其他语言中遇到的坑。
至于说 Rust 能否解决这些问题呢，反正我还是信的。

# 错误处理

这点貌似是从 Lisp / Haskell 里面借鉴的（我不懂

```
fn parse_version(header: &[u8]) -> Result<Version, ParseError> {
	if header.len() < 1 {
		return Err(ParseError::InvalidHeaderLength);
	}
	match header[0] {
		1 => Ok(Version::Version1),
		2 => Ok(Version::Version2),
		_ => Err(ParseError::InvalidVersion)
	}
}

let version = parse_version(&[1, 2, 3, 4]);
match version {
	Ok(v) => {
		println!("working with version: {:?}", v);
	}
	Err(e) => {
		println!("error parsing header: {:?}", e);
	}
}
```

这种方法让人感到很优雅，不用像 golang 一样大篇大篇的 `if err != nil`，一个 `try!` 搞定。

# 没有 GC，实时回收

这点比 lua / js 这种根本不知道什么时候回收的做法好多了，虽然加重了语法负担。
之前不是很多人抱怨 golang 做游戏的时候会卡顿。所以带 GC 的语言不适合做底层。Rust 就没这问题了。
分分钟跑在单片机上，毫无压力。

有人说这个特性适合写游戏引擎。我也发现有人吐槽 Unity 的引擎在 GC 任务重的情况下容易导致游戏卡顿，据说是由于 Mono 没有使用分代 GC 的缘故。
如果不用 GC，不知道这个问题是否可以根除？

# 支持递归和重复的宏

Rust 的宏支持递归，重复。光这两点就可以把 C 的宏秒杀了。

每次写 C 的时候遇到诸如

```
#define dbp(...) printf(一坨翔)

#define LongStmt(x) 翔一样的连接符-> \
	漏一个了还不行 \
	终于完了
```
之类的东西就很烦。非常不优雅。

Rust 相比起来好多了

```
let x: Vec<u32> = vec![1, 2, 3];
```

```
macro_rules! vec {
	( $( $x:expr ),* ) => {
		{
			let mut temp_vec = Vec::new();
			$(
					temp_vec.push($x);
			 )*
				temp_vec
		}
	};
}
```

```
let x: Vec<u32> = {
	let mut temp_vec = Vec::new();
	temp_vec.push(1);
	temp_vec.push(2);
	temp_vec.push(3);
	temp_vec
};
```

# 

