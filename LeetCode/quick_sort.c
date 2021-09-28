#include <stdio.h>

void swap(int *a, int *b) {
    int cache = *a;
    *a = *b;
    *b = cache;
}

void quickSort(int arr[], int start, int end) {
    if (start >= end) {
        return;
    }
    int left = start;
    int right = end-1;
    int mid = arr[end];

    while (left < right) {
        while (arr[left] < mid && left < right) {
            left++;
        }
        while (arr[right] > mid && left < right) {
            right--;
        }
        swap(&arr[left], &arr[right]);
    }

    if (arr[left] > mid) {
        swap(&arr[left], &arr[end]);
    }
    right ++;

    quickSort(arr, start, left);
    quickSort(arr, right, end);
}

void main() {
    int array[] = {3,52,6,2,13,6,54,70,34,5,74,3};
    int len = sizeof(array) / sizeof(int);
    quickSort(array, 0, len);
    for (int i = 0; i<len; i++) {
        printf("%d ", array[i]);
    }
    printf("\n");
    return;
}