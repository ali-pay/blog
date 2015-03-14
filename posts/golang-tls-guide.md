---
title: Golang TLS 简要指南 
date: '2013-11-25'
description:
categories:
- Code
tags:
- Golang
---

# TLS 的作用

用于加密传输。但相对于自己实现的简单的加密传输，TLS 有握手协议，有验证证书的协议。并且支持多个证书，很方便。

网上关于 Golang TLS 库的说明极少，官方文档讲得也比较含糊。

# 数字证书的背景知识

简单的说，证书就是公钥，另外还包含我的身份信息，来证明“这是我的公钥”。问题是，你这么说，谁会相信你呢？

所以你要找一个权威组织。用它的私钥给你的证书加密。权威组织的公钥是公开的。

因此大家拿到你的证书以后，尝试用各个权威组织的公钥来解密，如果解密成功，就说明这的确是你的公钥。

各个权威组织的公钥叫做“根证书”。在浏览器设置里面的证书管理，可以找到一堆权威组织。

让权威组织给你证书加密，是要给钱的。。而且如果你的程序没联网，可能也获取不到那“一堆权威组织”，因为那是操作系统管理的。

所以这个时候，就要自己给自己建立一个“权威组织”，叫做“自签名”。权威组织用的证书，叫做“根证书”。

# 创建根证书（ca.pem, ca.key）

	ca := &x509.Certificate{
		SerialNumber: big.NewInt(1653),
		Subject: pkix.Name{
			Country: []string{"China"},
			Organization: []string{"Shit company"},
			OrganizationalUnit: []string{"Shit company Unit"},
		},
		NotBefore: time.Now(),
		NotAfter: time.Now().AddDate(10,0,0),
		SubjectKeyId: []byte{1,2,3,4,5},
		BasicConstraintsValid: true,
		IsCA: true,
		ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth, x509.ExtKeyUsageServerAuth},
		KeyUsage: x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign,
	}

	priv, _ := rsa.GenerateKey(rand.Reader, 1024)
	pub := &priv.PublicKey
	ca_b, err := x509.CreateCertificate(rand.Reader, ca, ca, pub, priv)
	if err != nil {
		log.Println("create ca failed", err)
		return
	}
	ca_f := "ca.pem"
	log.Println("write to", ca_f)
	ioutil.WriteFile(ca_f, ca_b, 0777)

	priv_f := "ca.key"
	priv_b := x509.MarshalPKCS1PrivateKey(priv)
	log.Println("write to", priv_f)
	ioutil.WriteFile(priv_f, priv_b, 0777)

创建证书使用的是 x509.CreateCertificate 函数，该函数说明如下：
	
	The certificate is signed by parent. If parent is equal to template then the certificate is self-signed. The parameter pub is the public key of the signee and priv is the private key of the signer.
	如果 parent 和 template 一样，则证书是自签名的。public 为要创建的证书的公钥，priv 为用来签名的证书的私钥。
	
	The only supported key types are RSA and ECDSA (*rsa.PublicKey or *ecdsa.PublicKey for pub, *rsa.PrivateKey or *ecdsa.PublicKey for priv).
	目前支持 RSA 和 ECDSA。传入的公私钥必须一致。 

x509.MarshalPKCS1PrivateKey 函数可以把 rsa 私钥写到文件中。

经测试，代码中 x509.Certificate 里面的项是必填的，不然就出问题了。

# 创建我的证书（cert2.pem, cert2.key）

	cert2 := &x509.Certificate{
		SerialNumber: big.NewInt(1658),
		Subject: pkix.Name{
			Country: []string{"China"},
			Organization: []string{"Fuck"},
			OrganizationalUnit: []string{"FuckU"},
		},
		NotBefore: time.Now(),
		NotAfter: time.Now().AddDate(10,0,0),
		SubjectKeyId: []byte{1,2,3,4,6},
		ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth, x509.ExtKeyUsageServerAuth},
		KeyUsage: x509.KeyUsageDigitalSignature|x509.KeyUsageCertSign,
	}
	priv2, _ := rsa.GenerateKey(rand.Reader, 1024)
	pub2 := &priv2.PublicKey
	cert2_b, err2 := x509.CreateCertificate(rand.Reader, cert2, ca, pub2, priv)
	if err2 != nil {
		log.Println("create cert2 failed", err2)
		return
	}

	cert2_f := "cert2.pem"
	log.Println("write to", cert2_f)
	ioutil.WriteFile(cert2_f, cert2_b, 0777)

	priv2_f := "cert2.key"
	priv2_b := x509.MarshalPKCS1PrivateKey(priv2)
	log.Println("write to", priv2_f)
	ioutil.WriteFile(priv2_f, priv2_b, 0777)

注意 x509.CreateCertificate 的参数。

# 证书格式的说明

在浏览器中选择 https/ssl 证书管理。然后选择导出，可以看到两种类型的证书：

# Base64 编码 X509 

这种类型的证书格式如下。

	-----BEGIN CERTIFICATE-----
	MIIDkzCCAnugAwIBAgIQQb40Q4rF+ATQFBEUMJwlaDANBgkqhkiG9w0BAQUFADBp
	MR8wHQYDVQQKDBZBbGlwYXkuY29tIENvcnBvcmF0aW9uMRowGAYDVQQLDBFNYWNo
	aW5lIENBIENlbnRlcjEqMCgGA1UEAwwhQWxpcGF5LmNvbSBDb3Jwb3JhdGlvbiBN
	YWNoaW5lIENBMB4XDTEzMDUzMDA0MzEzMVoXDTE1MDUzMDA0MzEzMVowgYExKTAn
	BgNVBAMMIDNiZGQ3N2Y1ZGI5M2QxMmU2NDY3MTY4MTA0ZGJkZDQ2MRIwEAYDVQQL
	DAlDQSBDZW50ZXIxHzAdBgNVBAoMFkFsaXBheS5jb20gQ29ycG9yYXRpb24xETAP
	BgNVBAwMCG0tYWxpcGF5MQwwCgYDVQQHDANUUFcwgZ8wDQYJKoZIhvcNAQEBBQAD
	gY0AMIGJAoGBALXNWBcgbBSvhTOmQ4ofk5O0vbcPVR+nZGdjVMGtbFPBsOFM1fGy
	5azkQq09LVDFU9CNDOY9F0qvdEbz12AoFYriDK/DNR4zirhkIBbm51WVVnm6Clu8
	OaM9uSY/BltnAjsFF3Ytn1hgZx+bwFHAyaywCOocfvA5zenvL4XCjOb7AgMBAAGj
	gaEwgZ4wgYMGA1UdIwR8MHqAFMi6TxpLDcUfw0pIJ1jpLbjLozL3oV2kWzBZMR0w
	GwYDVQQDDBRBbGlwYXkgVHJ1c3QgTmV0V29yazEXMBUGA1UECwwOU2VjdXJpdHlD
	ZW50ZXIxHzAdBgNVBAoMFkFsaXBheS5jb20gQ29ycG9yYXRpb26CAwFogTAJBgNV
	HRMEAjAAMAsGA1UdDwQEAwIEkDANBgkqhkiG9w0BAQUFAAOCAQEAqBvC4fFcpRDc
	Jc+XFJHng/qA4lOs5/rr0N2fs1yaqQHR9Js0zDOVtmHgymOuNo9cUXUJLpLsNmb1
	sPeWzKI4z9M2va9yL/OVWan7l041KBCENlda5px03fON+CSZbAxwqPi2H7nFYWYx
	wvu47LK/smlPpiudhTFC1kb7wAftYKpcifcINfTX1Wl+ZQaIesdmJxtMvVuGM+fP
	mAyYQ0/XxS+YbwPydD7y5wSuLT29aFvK8/Go0lq4MjIkgWlKzEk6eMz2wWFQldca
	fNsYplGbNsUnF/XiR/34/XO2OEKSJa9qIFSjfBSGUIT0Av54LrvV2LKTIMs7e1Pe
	Kh2JXSY9pw==
	-----END CERTIFICATE-----

在 Golang 中可以调用 encoding/pem 的 pem.Decode 来解码成 DER 编码。

也可以调用 tls.LoadX509KeyPair 来加载。

## Der 编码 X509

这种编码可以直接读取然后用 x509.ParseCertificate 来解码。

# 服务端监听

	ca_b, _ := ioutil.ReadFile("ca.pem")
	ca, _ := x509.ParseCertificate(ca_b)
	priv_b, _ := ioutil.ReadFile("ca.key")
	priv, _ := x509.ParsePKCS1PrivateKey(priv_b)

	pool := x509.NewCertPool()
	pool.AddCert(ca)

	cert := tls.Certificate{
		Certificate: [][]byte{ ca_b },
		PrivateKey: priv,
	}

	config := tls.Config{
		ClientAuth: tls.RequireAndVerifyClientCert,
		Certificates: []tls.Certificate{cert},
		ClientCAs: pool,
	}
	config.Rand = rand.Reader
	service := "0.0.0.0:443"
	listener, err := tls.Listen("tcp", service, &config)
	if err != nil {
		log.Fatalf("server: listen: %s", err)
	}
	log.Print("server: listening")

	for {
		conn, err := listener.Accept()
		if err != nil {
			log.Printf("server: accept: %s", err)
			break
		}
		defer conn.Close()
		log.Printf("server: accepted from %s", conn.RemoteAddr())
		tlscon, ok := conn.(*tls.Conn)
		if ok {
			log.Print("ok=true")
			state := tlscon.ConnectionState()
			for _, v := range state.PeerCertificates {
				log.Print(x509.MarshalPKIXPublicKey(v.PublicKey))
			}
		}
		go handleClient(conn)
	}

tls.Config 中 ClientAuth 的选项有

        NoClientCert ClientAuthType = iota
        RequestClientCert
        RequireAnyClientCert
        VerifyClientCertIfGiven
        RequireAndVerifyClientCert

级别从低到高。

ClientCAs 参数是服务端拥有的“权威组织”的列表。

# 客户端连接

	cert2_b, _ := ioutil.ReadFile("cert2.pem")
	priv2_b, _ := ioutil.ReadFile("cert2.key")
	priv2, _ := x509.ParsePKCS1PrivateKey(priv2_b)

	cert := tls.Certificate{
		Certificate: [][]byte{ cert2_b },
		PrivateKey: priv2,
	}

	config := tls.Config{Certificates: []tls.Certificate{cert}, InsecureSkipVerify: true}
	conn, err := tls.Dial("tcp", "127.0.0.1:443", &config)
	if err != nil {
		log.Fatalf("client: dial: %s", err)
	}
	defer conn.Close()
	log.Println("client: connected to: ", conn.RemoteAddr())

	message := "Hello\n"
	n, err := io.WriteString(conn, message)
	if err != nil {
		log.Fatalf("client: write: %s", err)
	}
	log.Printf("client: wrote %q (%d bytes)", message, n)

	reply := make([]byte, 256)
	n, err = conn.Read(reply)
	log.Printf("client: read %q (%d bytes)", string(reply[:n]), n)
	log.Print("client: exiting")

其中 tls.Config 的 InsecureSkipVerify 参数的意思是：客户端不验证服务端的证书。

# 获取对端证书

	tlscon, ok := conn.(*tls.Conn)
	if ok {
		state := tlscon.ConnectionState()
		sub := state.PeerCertificates[0].Subject
		log.Println(sub)
	}

在传输过程中。可以把 net.Conn 强制转换为 tls.Conn 然后获取连接状态。
服务端执行结果如下：

	2013/11/25 14:13:05 {[China] [Fuck] [FuckU] [] [] [] []   [{[2 5 4 6] China} {[2 5 4 10] Fuck} {[2 5 4 11] FuckU}]}

完整代码在 [这里](https://github.com/go-av/tls-example)

# 参考资料

[Golang tls](golang.org/pkg/crypto/tls)

[Journey of Life: GOLANG SSL Server and Client example](http://tiebing.blogspot.com/2013/06/golang-ssl-server-and-client-example.html)

[Upgrade a connection to TLS in Go](http://stackoverflow.com/questions/13110713/upgrade-a-connection-to-tls-in-go)
