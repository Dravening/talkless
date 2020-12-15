package reflect

import (
	"fmt"
	"reflect"
)

type sth struct {
	x int
}

func (i sth) Yell(str string) {
	fmt.Println(i.x, str)
}

func Reflect() {
	str := "this is a string"
	tx := sth{8}
	reTx := reflect.ValueOf(tx)
	reFn := reTx.MethodByName("Yell")
	reFn.Call([]reflect.Value{reflect.ValueOf(str)})
}
