# 集群网关-开发自己的ingress控制器

### 思路

1.部署使用当前的开源ingress-controller，比如apisix-ingress-controller，重启它，获得启动日志。

2.学习其构造逻辑

3.开发自己的ingress控制器

### 准备工作

```shell
git clone https://github.com/Dravening/apisix-ingress-controller
```

```
go mod tidy
```

