package LeetCode

import "fmt"

func checkHalf() {
	intList := []int{2, 4, 5, 8, 11, 24, 36, 68, 122, 244}
	a := half(intList, 0, len(intList)-1, 4)
	fmt.Println(a)
}

// 二分法查找目标数在列表中的位置
func half(intList []int, first, last, target int) int {
	//first := 0
	//last := len(intList) - 1

	// 1,4 的中间为2    1，5的中间为3
	midFunc := func(first, last int) int {
		return (last-first)/2 + first
	}

	mid := midFunc(first, last)
	var a int
	switch {
	case intList[mid] > target:
		a = half(intList, first, mid-1, target)
	case intList[mid] < target:
		a = half(intList, mid+1, last, target)
	case intList[mid] == target:
		return mid
	}
	return a
}
