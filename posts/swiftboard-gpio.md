---
title: 在 userspace 操作 A10 的 GPIO
date: '2014-01-14'
description:
categories:
- Code
tags:
- Maker
- Linux
---

GPIO 就是直接操作管脚的高低电平，用最原始的方式驱动其他硬件。

A10 芯片的管脚编号如下：

PA0, PA1, PA2 ... PB0, PB1, PB2, .... PS0, PS1 ...

修改 script.bin 文件

``` 
# 在板子上拷贝出 script.bin
$ mount /dev/nanda /media/nanda
$ ls /media/nanda/script.bin

# 安装 sunxi-tools
$ git clone https://github.com/linux-sunxi/sunxi-tools.git
$ cd sunxi-tools
$ make 
$ ./bin2fex script.bin > script.fex
$ vi script.fex
```

这个文件描述了芯片的哪些管脚被分配为做什么。如果你要用哪个管脚，必须先关闭对应的功能模块，然后这个管脚才能作为 GPIO 使用。

比如说，我要使用 PI10 管脚。发现它属于 SPI 模块的 cs0 管脚。所以要关闭 SPI 模块，把 spi_used 要设置为 0。

``` 
198 [spi0_para]
199 spi_used = 0
200 spi_cs_bitmap = 1
201 spi_cs0 = port:PI10<3><default><default><default>
202 spi_sclk = port:PI11<3><default><default><default>
203 spi_mosi = port:PI12<3><default><default><default>
204 spi_miso = port:PI13<3><default><default><default>
```

然后 

``` 
$ ./fex2bin script.fex > script.bin
再把 script.bin 拷贝到板子的 nanda 分区，并且重启生效
```

# 上拉电阻与下拉电阻

一开始我设置管脚为输入，但读取到的值飘忽不定，时而0时而1。后来查阅资料，发现还有“上拉”和“下拉”这回事儿。

如果把管脚和地线连起来，那肯定就是0了。和电源连起来，肯定就是1。但是悬空的话，就是飘忽不定。如果拿GPIO来做按钮要咋整呢？

![](/img/swiftboard-gpio/switch-1.png)

像这样，接通的时候和电源连起来，断开的时候和地线连起来。这种方法看上去可行，但不是每个按钮都是三条线的，而且切换的时候还是会悬空，还是飘忽不定，会产生噪音。

所以某个高手发明了这个屌炸天的方法：

![](/img/swiftboard-gpio/switch-2.png)

这样的话，在断开的时候，输入为1，连通的时候为0。而且不会有噪声。

同理，也可以下拉：

![](/img/swiftboard-gpio/switch-3.png)

# GPIO 寄存器

寄存器通过物理地址访问，基地址是 0x01c20800。在 A10 的 datasheet 里面有详细描述。

寄存器有四种：

- CFG 寄存器，配置管脚用于输入或者输出。每个管脚占三个bit。

	如果要把 PA17 设置成输出。就要修改基地址 0x01c20800 + 0x08 往后的四个字节里的 [6:4] bit 为 001。

- DAT 寄存器，读取设置管脚高低电平。每个管脚占一个bit。

	![](/img/swiftboard-gpio/pa-dat.jpg)

- PUL 寄存器，设置上拉电阻或下拉电阻。每个管脚占两个bit。

	![](/img/swiftboard-gpio/pa-pul.jpg)

01是上拉电阻，10是下拉电阻。

- INT_CFG 寄存器，设置管脚的中断触发方式。

	![](/img/swiftboard-gpio/pa-int.jpg)

Positive Edge 为上升沿触发，即高电平转换到低电平的时候触发。Negative Edge 则相反。Low Level 和 High Level 我没试过。

注意，不是所有的 GPIO 引脚都有中断，只有 PH0 - PH21, PI10 - PI19 这 32 个引脚能关联中断。

- INT_CTL 寄存器，开启和关闭中断。

	![](/img/swiftboard-gpio/int-ctl.jpg)

- INT_STATUS 寄存器，中断发生的时候对应的bit会变成 1，写入1清除中断位。

	![](/img/swiftboard-gpio/int-stat.jpg)


# 在内核模块访问寄存器

A10 的 GPIO 驱动是一个老外写的，并不完整，直接忽略掉了上下拉电阻的设置部分。

我打算用 /dev/mem 设备读写物理内存，但发现这个设备也被编译选项禁用了。

所以需要写一个内核模块了。

在内核里面访问物理内存很简单。使用 ioremap 映射即可。

``` 
void *gpio_base = ioremap(0x01c20800, 0x400);
```

然后新建一个字符设备，方便用户态访问：

``` 
#define MAJOR_NUM 232

if (register_chrdev(MAJOR_NUM, "hello", &hello_fops)) {
	printk(KERN_ALERT "init: failed register %d, %d\n", MAJOR_NUM, 0);
	return -EINVAL;
}
```

# 在内核模块设置中断

A10 中的平台驱动已经预先设置好了 GPIO 专属的中断号，直接使用 request_irq 绑定中断处理函数即可。

``` 
static __u32 irqstat;
static int hello_read(struct file *filp, char __user *buf, size_t count, loff_t *f_pos) {
    int r;

    // 等待中断发生，然后返回中断的状态
    interruptible_sleep_on(&irq_queue);
    if (count >= 4)
        r = copy_to_user(buf, &irqstat, 4);
    return count;
}

static irqreturn_t irq_handler(int irq, void *devid) {
    __u32 status = 0;
    void *reg = gpio_base + 0x214; // 中断寄存器地址
    int i;

    // 读取中断寄存器
    status = *(__u32 *)(reg);
    for (i = 0; i < 32; i++) {
        if (status & (1<<i)) {
            // 清除中断位，不然就不会继续产生中断了
            *(__u32 *)(reg) = 1<<i;
        }
    }

    irqstat = status;
    // 唤醒读队列
    wake_up_interruptible(&irq_queue);
    return IRQ_HANDLED;
}

...

// SW_INT_IRQNO_PIO = 28 (arch/arm/plat)

err = request_irq(28, irq_handler,
	IRQF_SHARED, "sunxi-gpio", (void *)0x1653);

if (err != 0) {
		printk(KERN_ALERT "hello init: request irq failed: %d\n", err);
		return -EINVAL;
}
```

这段代码达到的效果就是，读取 /dev/gpio 设备的时候会阻塞，直到有中断来的时候，返回 INT_STATUS 寄存器的内容，然后就能知道是哪根引脚发生了中断。

# 参考代码

内核模块代码（[github.com/nareix/a10/mmap-gpio-kern](http://github.com/nareix/a10/tree/master/mmap-gpio-kern)），提供读写寄存器的接口。

```
mknod /dev/gpio c 232 0
insmod gpio.ko
```

用户态代码（[github.com/nareix/a10/mmap-gpio](http://github.com/nareix/a10/tree/master/mmap-gpio)）。

```
cd mmap-gpio
GOARCH=arm go build .
```

# 参考资料

[Fex Guide](http://linux-sunxi.org/Fex_Guide)

[GPIO 入门](https://github.com/cubieplayer/Cubian/wiki/GPIO%E5%85%A5%E9%97%A8)

[上拉与下拉的解释](http://www.thebox.myzen.co.uk/Tutorial/Inputs.html)

[A10 datasheet](http://linux-sunxi.org/A10)

[A10 内核以及工具的开源代码](https://github.com/linux-sunxi)

[Swiftboard 官方 Github，内有原理图，用户手册](https://github.com/swiftboard)
