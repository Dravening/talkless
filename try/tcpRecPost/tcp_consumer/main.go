package main

import (
	"fmt"
	"net"
	"os"
)

func main() {
	//创建监听服务
	listener, err := net.Listen("tcp", "127.0.0.1:8003")
	if err != nil {
		fmt.Println("net.Listen err:", err)
		return
	}
	/**
	  等待接受连接
	*/
	conn, err := listener.Accept()
	if err != nil {
		fmt.Println("listener.Accept err:", err)
		return
	}
	/**
	  读取文件名，向文件发送者返回OK
	*/
	buf := make([]byte, 4096)
	n, err := conn.Read(buf)
	if err != nil {
		fmt.Println("conn.Read err:", err)
		return
	}
	filename := string(buf[:n])
	fmt.Println("filename:", filename)
	if filename != "" {
		_, err = conn.Write([]byte("ok"))
		if err != nil {
			fmt.Println("conn.Write err:", err)
			return
		}
	} else {
		return
	}
	/**
	  创建文件并写入文件内容
	*/
	fmt.Println(filename)
	file, err := os.Create(filename)
	if err != nil {
		fmt.Println("os.Create err:", err)
		return
	}

	for {
		n, err := conn.Read(buf)
		if n == 0 {
			fmt.Println("文件读取完毕")
			break
		}
		if err != nil {
			fmt.Println("conn.Read err:", err)
			return
		}
		_, _ = file.Write(buf[:n])
	}

}
