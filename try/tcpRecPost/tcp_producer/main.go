package main

import (
	"fmt"
	"io"
	"net"
	"os"
)

func main() {
	//获取命令行参数,用命令传递文件go run send.go D:\1.mp3,参数为1:send.go,2:D:\1.mp3
	list := os.Args
	//文件路径
	filepath := list[1]
	//文件属性
	fileInfo, err := os.Stat(filepath)
	if err != nil {
		fmt.Println("os.Stat err", err)
		return
	}
	filename := fileInfo.Name()
	/**
	  建立连接
	*/
	conn, err := net.Dial("tcp", "127.0.0.1:8003")
	if err != nil {
		fmt.Println("net.Dialt err", err)
		return
	}
	//发送文件名到接收端
	_, err = conn.Write([]byte(filename))
	if err != nil {
		fmt.Println("conn.Write err", err)
		return
	}
	buf := make([]byte, 4096)
	//接收服务器返还的指令
	n, err := conn.Read(buf)
	if err != nil {
		fmt.Println("conn.Read err", err)
		return
	}
	//返回ok，可以传输文件
	if string(buf[:n]) == "ok" {
		sendFile(conn, filepath)
	}

}
func sendFile(conn net.Conn, filepath string) {
	//打开要传输的文件
	file, err := os.Open(filepath)
	if err != nil {
		fmt.Println("os.Open err", err)
		return
	}
	buf := make([]byte, 4096)
	//循环读取文件内容，写入远程连接
	for {
		n, err := file.Read(buf)
		if err == io.EOF {
			fmt.Println("文件读取完毕")
			return
		}
		if err != nil {
			fmt.Println("file.Read err:", err)
			return
		}
		_, err = conn.Write(buf[:n])
		if err != nil {
			fmt.Println("conn.Write err:", err)
			return
		}
	}
}
