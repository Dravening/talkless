package LeetCode

// two sum
// Given an array of integers, return indices of the two numbers such that they add up to a specific target.
// You may assume that each input would have exactly one solution, and you may not use the same element
// twice.

// example -- 在数组中找到两个数之和为给定值的数字，结果返回2个数字在数组中的下标。
// Given nums = [2, 7, 11, 15], target = 9,
// Because nums[0] + nums[1] = 2 + 7 = 9,
// return [0, 1]

func twoSum(nums []int, target int) []int {
	numMap := map[int]int{}
	for i, num := range nums {
		if location, ok := numMap[target-num]; ok {
			return []int{i, location}
		}
		numMap[num] = i
	}
	return nil
}
