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

##### docker命令备忘
```
docker run -td --name yyz-iot -v /sys/devices:/home/devices:ro  -v  /sys/class/net:/home/net:ro  10.206.73.155/openiot-yangyuzhe/openiot:v1.0
docker cp docker-entrypoint.sh  yyz-iot:/app/
docker commit yyz-iot  10.206.73.155/openiot-yangyuzhe/openiot:v1.0
docker rm yyz-iot
docker run -td --name yyz-iot -v /sys/devices:/home/devices:ro  -v  /sys/class/net:/home/net:ro  10.206.73.155/openiot-yangyuzhe/openiot:v1.0
docker logs yyz-iot
```

("02:42:4f:13:4b:52" "34:73:79:21:00:1e" "34:73:79:21:00:1f" "34:73:79:21:00:20" "34:73:79:21:00:21" "34:73:79:3d:51:af" "34:73:79:3d:51:b0" "02:42:6d:27:0b:c1" "34:73:79:21:05:ee" "34:73:79:21:05:ef" "34:73:79:21:05:f0" "34:73:79:21:05:f1" "34:73:79:3d:51:69" "34:73:79:3d:51:6a" "34:73:79:20:ff:fa" "34:73:79:20:ff:fb" "34:73:79:20:ff:fc" "34:73:79:20:ff:fd" "34:73:79:3d:51:93" "34:73:79:3d:51:94" "02:42:be:72:69:af" "34:73:79:29:ed:9f" "34:73:79:29:ed:a0" "34:73:79:29:ed:a1" "34:73:79:29:ed:a2" "34:73:79:3c:76:99" "34:73:79:3c:76:9a" "02:42:27:17:e2:4f" "00:50:56:bf:b3:91" "52:54:00:ad:a2:bc" "02:42:be:ab:8b:fd" "00:50:56:bf:c3:c9" "52:54:00:ad:a2:bc" "02:42:86:1d:27:76" "00:50:56:bf:22:84" "52:54:00:ad:a2:bc" "02:42:71:0d:9a:a7" "00:50:56:bf:67:79" "52:54:00:ad:a2:bc" "02:42:f3:05:dc:8e" "34:73:79:16:10:08" "34:73:79:16:10:09" "a0:36:9f:89:60:ea" "a0:36:9f:89:60:eb" "a0:36:9f:89:60:e8" "a0:36:9f:89:60:e9" "c8:e6:00:28:a7:fa" "c8:e6:00:28:a7:fb" "52:54:00:4b:cb:7c" "02:42:da:b7:a4:0f" "34:73:79:15:fd:48" "34:73:79:15:fd:49" "c8:e6:00:28:a9:64" "c8:e6:00:28:a9:65" "8e:4c:83:1d:3d:cc" "aa:43:83:e6:75:e9" "52:54:00:d0:39:8f" "02:42:fb:e2:fb:3c" "34:73:79:16:0e:28" "34:73:79:16:0e:29" "c8:e6:00:28:a7:ba" "c8:e6:00:28:a7:bb" "52:54:00:c5:8a:22" "02:42:35:84:64:27" "28:6e:d4:88:c6:5e" "02:42:83:46:c1:cc" "28:6e:d4:89:dc:c8" "c2:11:4a:6d:43:ec" "1a:7a:de:4c:05:61" "d6:a3:6e:97:1a:38" "8a:2f:e2:ab:98:c3" "1a:6f:8d:45:5b:d8")