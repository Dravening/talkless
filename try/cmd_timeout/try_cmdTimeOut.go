package cmd_timeout

import (
	"context"
	"errors"
	"log"
	"os/exec"
	"time"
)

//设置超时时间为 5秒
var Timeout = 5 * time.Second

//执行命令并添加超时检测
func Command(name string, arg ...string) (string, error) {
	ctxt, cancel := context.WithTimeout(context.Background(), Timeout)
	defer cancel() //releases resources if slowOperation completes before timeout elapses
	cmd := exec.CommandContext(ctxt, name, arg...)
	//当经过Timeout时间后，程序依然没有运行完，则会杀掉进程，ctxt也会有err信息
	if out, err := cmd.Output(); err != nil {
		//检测报错是否是因为超时引起的
		if ctxt.Err() != nil && ctxt.Err() == context.DeadlineExceeded {
			return "", errors.New("command timeout")
		}
		return string(out), err
	} else {
		return string(out), nil
	}
}
func CheckCmdTimeout() {
	//设置超时为5秒 sleep 6秒肯定会超时
	out, err := Command("sleep", "6")
	if err != nil {
		//经验证，没毛病
		log.Println("错误返回:", err.Error())
	} else {
		log.Println("正常返回:", out)
	}
}
