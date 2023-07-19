# keepalived部署文档

本文参考https://zhuanlan.zhihu.com/p/566166393

原理详解https://blog.csdn.net/Little_fxc/article/details/118575772

LVS：https://www.cnblogs.com/llhua/p/4195330.html

### 一、前言

Keepalived 软件起初是专为 LVS 负载均衡软件设计的，用来管理并监控 LVS 集群系统中各个服务节点的状态，后来又加入了可以实现高可用的 VRRP 功能。因此，Keepalived除了能够管理 LVS 软件外，还可以作为其他服务（例如：Nginx、Haproxy、MySQL等）的高可用解决方案软件。

本次示例使用`VRRP Instance`，没有使用`synchroization group`（适合用在多个服务有"一损俱损"概念的时候）；



### 一、环境说明

| 主机名      | 系统       | 部署内容            | 备注                |
| ----------- | ---------- | ------------------- | ------------------- |
| tcosmo-sh05 | CentOS 7.9 | 部署test-nginx:68-5 | 内网ip：10.206.68.5 |
| tcosmo-sh06 | CentOS 7.9 | 部署test-nginx:68-6 | 内网ip：10.206.68.6 |

有10.206.68.5和10.206.68.6两台机器，两台机器分别使用docker启动了nginx

```
docker run -dit --name mynginx -p 8071:8071 test-nginx:68-5
docker run -dit --name mynginx -p 8071:8071 test-nginx:68-6
```

> test-nginx基于官方nginx镜像，其中/usr/share/nginx/html/目录下增加了如下内容，并且调整了默认端口
>
> ```
> root@b337a829bba4: cat > /etc/nginx/conf.d/web.conf <<EOF
> server{
>         listen 8071;
>         root         /usr/share/nginx/html;
>         index 8071.html;
> }
> EOF
> ```
>
> ```
> root@b337a829bba4: echo "<h1>This is 68.5, port 8071</h1>"  > /usr/share/nginx/html/8071.html
> ```

### 二、安装keepalived

更新yum源

```
wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo
```

```
yum clean all
yum makecache
```

安装keepalived

```
yum install keepalived
```

### 三、修改keepalived配置文件

```
[root@tcosmo-sh05 keepalived]# cat /etc/keepalived/keepalived.conf 
! Configuration File for keepalived
global_defs {
   notification_email {
     acassen@firewall.loc
     failover@firewall.loc
     sysadmin@firewall.loc
   }
   notification_email_from Alexandre.Cassen@firewall.loc
   smtp_server 192.168.200.1
   smtp_connect_timeout 30
   router_id LVS_DEVEL
   vrrp_skip_check_adv_addr
   vrrp_garp_interval 0
   vrrp_gna_interval 0
}
vrrp_script nginx_check {
  script "/root/keepalived-tools/nginx_check.sh"
  interval 1
}
vrrp_instance VI_1 {
  state MASTER
  interface team0
  virtual_router_id 52
  priority 100
  advert_int 1
  nopreempt
  authentication {
    auth_type PASS
    auth_pass test
  }
  virtual_ipaddress {
    10.206.68.50
  }
  track_script {
    nginx_check
  }
  notify_master /root/keepalived-tools/master.sh
  notify_backup /root/keepalived-tools/backup.sh
  notify_fault /root/keepalived-tools/fault.sh
  notify_stop /root/keepalived-tools/stop.sh
}
```

```
[root@tcosmo-sh06 keepalived-tools]# cat /etc/keepalived/keepalived.conf 
! Configuration File for keepalived
global_defs {
   notification_email {
     acassen@firewall.loc
     failover@firewall.loc
     sysadmin@firewall.loc
   }
   notification_email_from Alexandre.Cassen@firewall.loc
   smtp_server 192.168.200.1
   smtp_connect_timeout 30
   router_id LVS_DEVEL
   vrrp_skip_check_adv_addr
   vrrp_garp_interval 0
   vrrp_gna_interval 0
}
vrrp_script nginx_check {
  script "/root/keepalived-tools/nginx_check.sh"
  interval 1
}
vrrp_instance VI_1 {
  state BACKUP
  interface team0
  virtual_router_id 52
  priority 99
  advert_int 1
  nopreempt
  authentication {
    auth_type PASS
    auth_pass test
  }
  virtual_ipaddress {
    10.206.68.50
  }
  track_script {
    nginx_check
  }
  notify_master /root/keepalived-tools/master.sh
  notify_backup /root/keepalived-tools/backup.sh
  notify_fault /root/keepalived-tools/fault.sh
  notify_stop /root/keepalived-tools/stop.sh
}
```

```
cat >> /root/keepalived-tools/master.sh << EOF
ip=$(hostname -I | awk '{print $1}')
dt=$(date+'%Y%m%d %H:%M:%S')
echo "$0--${ip}--${dt}" >> /tmp/kp.log
EOF

cat >> /root/keepalived-tools/backup.sh << EOF
ip=$(hostname -I | awk '{print $1}')
dt=$(date+'%Y%m%d %H:%M:%S')
echo "$0--${ip}--${dt}" >> /tmp/kp.log
EOF

cat >> /root/keepalived-tools/fault.sh << EOF
ip=$(ip addr | grep inet | grep 10.206 | awk '{print $2}')
dt=$(date +'%Y%m%d %H:%M:%S')
echo "$0--${ip}--${dt}" >> /tmp/kp.log
EOF

cat >> /root/keepalived-tools/stop.sh << EOF
ip=$(ip addr | grep inet | grep 10.206 | awk '{print $2}')
dt=$(date +'%Y%m%d %H:%M:%S')
echo "$0--${ip}--${dt}" >> /tmp/kp.log
EOF
```

接下来需要编写健康检查脚本

```shell
[root@tcosmo-sh06 keepalived-tools]# cat /root/keepalived-tools/nginx_check.sh
#!/bin/bash
result=`docker ps -f status=running | grep test-nginx`
if [ ! -z "${result}" ];
then
  exit 0
else
  exit 1
fi
```

启动keepalived

```
systemctl restart keepalived
```

检查启动情况

```
ip addr | grep 10.206.68.50
```

### 四、测试切换情况

访问`http://10.206.68.50:8071/`，发现得到`This is 68.5`，说明目前68.5是主；

此时我们停掉68.5的docker

```
docker stop e5f238bc1ff5
```

再次查看`http://10.206.68.50:8071/`，发现得到`This is 68.6`，与预期相符

再次启动68.5的docker

```
docker start e5f238bc1ff5
```

再次查看`http://10.206.68.50:8071/`，发现得到`This is 68.5`，又切换回来了，与预期相符。

### 五、可能遇到的问题

1.启动`systemctl restart keepalived`时，可能启动失败。

```
systemctl status keepalived
```

如果状态不是running，则是启动失败，这种情况请关注`/etc/keepalived/keepalived.conf` 中的`interface team0`配置，

请将team0换为这台机器的网卡（一般为eth0）

2.即使`systemctl status keepalived`启动成功，但未能正确创建VIP，这时候要确定如下问题。

```
ip addr | grep 10.206.68.50
```

健康检查脚本`nginx_check.sh`是否正确，如果此脚本一直返回false，则VIP无法创建。

> 另外也要注意：不要创建非同一个内网的ip，比如10.207.1.50

