package callBack_closure

import "fmt"

//这是回调函数
func callBack() {
	num2 := 2
	numResult := NewFunc(func(num1 int) (num3 int) {
		return plus(num3, num2)
	})
	fmt.Println(numResult)
}

func plus(int1, int2 int) int {
	return int1 + int2
}

func NewFunc(fn intFn) int {
	k := fn(1)
	fmt.Println("k ==", k)
	return k
}

type intFn func(int) int

//这是闭包
func closure() {
	t1 := add(10)
	fmt.Println(t1(1), t1(2))

	t2 := add(100)
	fmt.Println(t2(1), t2(2))
}

func add(base int) func(int) int {

	fmt.Printf("%p\n", &base) //打印变量地址，可以看出来 内部函数时对外部传入参数的引用

	f := func(i int) int {
		fmt.Printf("%p\n", &base)
		base += i
		return base
	}

	return f
}
