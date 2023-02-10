# 为容器增加mac地址校验功能

如果有为容器增加mac地址校验的需求，可以使用此方案;脚本中的mac地址数组要提前写死

### mac校验脚本

```
[root@master ~]# cat > mac_check.sh << "EOF"
#!/bin/bash

#注意: 脚本中多处命令的绝对路径与真机是不同的，如/usr/bin/cat写成/bin/cat
#注意: 路径mount如下 /home/net-->/sys/class/net, /home/$PATH/address-->/sys/$PATH/address

set -e
ALLOW_MAC=("84:65:69:5e:be:11" "84:65:69:5e:be:12" "84:65:69:5e:be:13" "84:65:69:5e:be:14" "84:65:69:5e:be:0f")
FLAG=0

for PATH in $(ls -l /home/net | /bin/grep pci0000 | awk -F '../../' '{print $2}');do
    MAC=$(/bin/cat /home/$PATH/address)
    for ALLOW in ${ALLOW_MAC[*]};do
        if echo "$ALLOW" | /bin/grep -w "$MAC" &>/dev/null; then
            /bin/date "+%Y-%m-%d %H:%M:%S"
            FLAG=1
            break 2
        fi
    done
done

if [ $FLAG = 0 ];then
    /bin/date
    exit 1
else
    /usr/sbin/nginx -g "daemon off;"
fi

/usr/bin/tail -f /dev/null
EOF
```

### 执行步骤

##### 1.启动一个默认nginx容器

```
[root@master ~]# docker run -td --name default-nginx nginx:latest
```

##### 2.向原生nginx传入check脚本文件

```
[root@master ~]# docker cp check.sh default-nginx:/docker-entrypoint.d/
```

##### 3.打包为check-mac-nginx

```
[root@master ~]# docker commit default-nginx check-mac-nginx:v1.0.2
```

##### 4.启动命令

```
[root@master ~]# docker run -dit --name check-mac-nginx -p 809:80 -v /sys/devices:/home/devices:ro  -v  /sys/class/net:/home/net:ro  check-mac-nginx:v1.0.2
```

##### 5.检查

```
[root@master ~]# docker logs check-mac-nginx
```

### 其它命令

> 注意：网卡按虚拟网卡和物理网卡这两个种类，需要区分不同的地址进行查询

##### 获取默认网卡

```
[root@master ~]# ip route show default | awk '/default/ {print $5}'
eth0
[root@k8s-node01 ~]# ip route show default | awk '/default/ {print $5}'
team0
```

##### 获取默认网卡地址

```
[root@master ~]# ls -l /sys/class/net/$(ip route show default | awk '/default/ {print $5}')
lrwxrwxrwx 1 root root 0 Feb  7 11:18 /sys/class/net/eth0 -> ../../devices/pci0000:00/0000:00:03.0/virtio0/net/eth0
```

```
[root@k8s-node01 ~]# ls -l /sys/class/net/$(ip route show default | awk '/default/ {print $5}')
lrwxrwxrwx 1 root root 0 Feb 10 09:14 /sys/class/net/team0 -> ../../devices/virtual/net/team0
```

##### 截取默认网卡地址

```
[root@master ~]# ls -l /sys/class/net/$(ip route show default | awk '/default/ {print $5}') | awk -F '../../' '{print $2}'
devices/pci0000:00/0000:00:03.0/virtio0/net/eth0
```

```
[root@k8s-node01 ~]# ls -l /sys/class/net/$(ip route show default | awk '/default/ {print $5}') | awk -F '../../' '{print $2}'
devices/virtual/net/team0
```

##### 查询mac地址（查询cat /sys/$CARD_ADDRESS/address）

```
[root@master ~]# cat /sys/$(ls -l /sys/class/net/$(ip route show default | awk '/default/ {print $5}') | awk -F '../../' '{print $2}')/address
0c:da:41:1d:8c:58
```

```
[root@k8s-node01 ~]# cat /sys/$(ls -l /sys/class/net/$(ip route show default | awk '/default/ {print $5}') | awk -F '../../' '{print $2}')/address
84:65:69:5e:be:0f
```

##### 如果没有ip和其它命令

```
[root@master ~]# ls -l /home/net | /bin/grep pci0000 | awk -F '../../' '{print $2}'
```

