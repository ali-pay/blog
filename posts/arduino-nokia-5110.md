---
title: Arduino 驱动 Nokia 5110 LCD 实战
date: '2013-12-10'
description:
categories:
- arduino
tags:
- arduino
---

![](/img/nokia-5110-brios.png)

#### Nokia 5110 LCD 控制协议

Nokia 5110 是一部很老的手机了，但它的液晶屏在淘宝上居然还买得到哇。84 x 48 的尺寸，用来嵌入在机箱前面显示信息挺好。

LCD 的接线如下：

![](/img/arduino-5110.jpg)

6 7 8 端口是用来传数据的。DN = DIN。

RST 端口是重启。LED 端口是控制背光。

传输协议为：

	void LcdWrite(byte dc, byte data) {
	  digitalWrite(PIN_DC, dc);
	  digitalWrite(PIN_SCE, LOW);
	  shiftOut(PIN_SDIN, PIN_SCLK, MSBFIRST, data);
	  digitalWrite(PIN_SCE, HIGH);
	}

shiftOut 函数为 Arduino 特有的函数。这个函数特方便，就是一个时钟周期输出一个 bit，同时控制时钟线和数据线。

5110 内部有寄存器控制当前光标位置。控制光标位置的函数为：

	void gotoXY(int x, int y) {
	  LcdWrite( 0, 0x80 | x);  // Column.
	  LcdWrite( 0, 0x40 | y);  // Row.
	}

液晶屏左上角 (x,y) 为 (0,0)。

控制完光标位置后，可以从左到右写入像素。像素用 bit 表示，一列为一个 byte，有 8 行分别对应 8 个 bit。如图所示：

![](/img/arduino-5110-2.jpg)

0x5f 表示的感叹号中，f 为上面四个像素，5 为下面四个像素。

在常用的代码中，字库保存为一个数组：

	static const byte ASCII[][5] =
	{
	 {0x00, 0x00, 0x00, 0x00, 0x00} // 20
	,{0x00, 0x00, 0x5f, 0x00, 0x00} // 21 !
	,{0x00, 0x07, 0x00, 0x07, 0x00} // 22 "
	,{0x14, 0x7f, 0x14, 0x7f, 0x14} // 23 #
	,{0x24, 0x2a, 0x7f, 0x2a, 0x12} // 24 $
	...


启动的时候初始化代码如下：

	void LcdInitialise(void) {
	  pinMode(PIN_SCE,   OUTPUT);
	  pinMode(PIN_RESET, OUTPUT);
	  pinMode(PIN_DC,    OUTPUT);
	  pinMode(PIN_SDIN,  OUTPUT);
	  pinMode(PIN_SCLK,  OUTPUT);
	 
	  digitalWrite(PIN_RESET, LOW);
	  digitalWrite(PIN_RESET, HIGH);
	 
	  LcdWrite(LCD_CMD, 0x21);  // LCD Extended Commands.
	  LcdWrite(LCD_CMD, 0xBf);  // Set LCD Vop (Contrast). //B1
	  LcdWrite(LCD_CMD, 0x04);  // Set Temp coefficent. //0x04
	  LcdWrite(LCD_CMD, 0x14);  // LCD bias mode 1:48. //0x13
	  LcdWrite(LCD_CMD, 0x0C);  // LCD in normal mode. 0x0d for inverse
	  LcdWrite(LCD_C, 0x20);
	  LcdWrite(LCD_C, 0x0C);
	}

打印字符串代码如下：

	void LcdCharacter(char character)
	{
	  LcdWrite(LCD_D, 0x00);
	  for (int index = 0; index < 5; index++)
	  {
	    LcdWrite(LCD_D, ASCII[character - 0x20][index]);
	  }
	  LcdWrite(LCD_D, 0x00);
	}

	void LcdString(char *characters) {
	  while (*characters) {
	    LcdCharacter(*characters++);
	  }
	}

在坐标（7,1）打印字符串的代码如下：
	
	gotoXY(7,1);
	LcdString("Nokia 5110");

#### 转换与显示图片

图片需要转换为字符数组，Golang 实现如下：
	
	func pic2byte(file string) (seq []byte) {
		f, err := os.Open(file)
		if err != nil {
			log.Fatal(err)
		}
		img, e := jpeg.Decode(f)
		if e != nil {
			log.Fatal(err)
		}
		rect := img.Bounds().Max
	
		for i := 0; i < rect.Y/8; i++ {
			for j := 0; j < rect.X; j++ {
				by := uint32(0)
				for k := 0; k < 8; k++ {
					c := img.At(j, i*8+k)
					r,g,b,_ := c.RGBA()
					y := (r+g+b)/3
					if y < 65536/2 {
						by |= 1<<uint32(k)
					}
				}
				seq = append(seq, byte(by))
			}
		}
	
		return
	}

然后打印出来，粘贴到 Arduino 的代码里：

	func dumppic(file string) {
		a := pic2byte(file)
		for _, b := range a {
			fmt.Printf("0x%x,", b)
		}
		fmt.Println()
	}


Arduino 显示图片的代码如下：
	
	byte pic[504] = {
		... // 刚刚打印出来的数组( 504 = 84 x 48 / 8 )
	};
	void logo() {
	  gotoXY(0, 0);
	  for (int i = 0; i < sizeof(pic); i++) {
	    LcdWrite(LCD_D, pic[i]);
	  }
	}


#### 通过串口显示字符与图片

经过实测发现。**波特率不能大于 9600**，否则会出现丢数据的问题。

	void setup() {
		Serial.begin(9600);
		while (1) {
	    	while (Serial.available()) {
	   		   byte b = Serial.read();
				
			   ....
			}
		}
	}

需要制定一个简单的协议，来显示图片和文字：

 * "l" + "123\n456" + "\x0" 表示从左上角开始打印文字 "123\n456"
 * "b" +  图片数据504字节 表示显示图片
 * "w" 表示把图片写入 EEPROM，开机读取

Arduino 代码如下：

	while (1) {
	    while (Serial.available()) {
	      byte b = Serial.read();
	      if (st == 'l') {
	        if (!b)
	          st = 0;
	        else if (b == '\n') {
	          for (; x < LCD_X; x++) LcdWrite(LCD_D, 0);
	          x = 0; y += 9;
	        } else if (x < LCD_X && y < LCD_Y) {
	          gotoXY(x, y);
	          x += lcd_ch(b);
	        }
	      } else if (st == 'b') {
	        pic[pp++] = b;
	        if (pp >= sizeof(pic)) {
	          logo();
	          st = 0; pp = 0;
	        }
	      } else {
	        if (b == 'l') {
	          st = b; x = 0; y = 0;
	        } else if (b == 'b') {
	          st = b; pp = 0;
	        } else if (b == 'w') {
	          for (int i = 0; i < sizeof(pic); i++)
	            EEPROM.write(i, pic[i]);
	          Serial.write('w');
	        }
	      }
	    }
  	}

控制端代码，使用 "github.com/tarm/goserial" 库来控制串口（Windows）：

	c := &serial.Config{Name: "COM5", Baud: 9600}
	s, err := serial.OpenPort(c)

	logo := pic2byte("logo.jpg")

	for {
		fmt.Fprint(s, "l")
		fmt.Fprintln(s, "SystemInfo")
		fmt.Fprintf(s,  "CPU %.2f\n", 33.12)
		fmt.Fprintf(s,  "Mem %.2f\n", 11.33)
		fmt.Fprintln(s, "Tx", "12Gbps")
		fmt.Fprintln(s, "Rx", "19Gbps")
		s.Write([]byte{0})
		time.Sleep(time.Second)

		fmt.Fprint(s, "b")
		s.Write(logo)
		time.Sleep(time.Second)
	}

#### 参考资料

[Nokia 5110](http://en.wikipedia.org/wiki/Nokia_5110)

[arduino学习笔记32](http://www.geek-workshop.com/thread-713-1-1.html)

[ShiftOut](http://arduino.cc/en/Reference/shiftOut)