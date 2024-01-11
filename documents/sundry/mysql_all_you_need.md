# mysql运维小全

## 一、安装

### 本地安装mysql

`rpm -qa | grep maria* && yum -y remove maria*`

`yum install ~/software/7.mysql/centos/5.x/*.rpm`

### docker安装mysql

```docker run \
--name mysql5.7 -p 3306:3306 -d \
--add-host='<HOSTNAME>:127.0.0.1' \
-e MYSQL_ROOT_PASSWORD=<PASSWORD> \
-v /var/lib/mysql5.7:/var/lib/mysql \
-v /var/log/mysql5.7/log:/var/log \
--restart=always mysql:5.7
```

### 更改密码

查找生成的root密码

`awk '/A temporary password/{print $NF}' /var/log/mysqld.log`

登录

`mysql -uroot -p<PASSWORD>`

改密码级别设置

`set global validate_password_policy=LOW;`
`set global validate_password_length=4;`

改密

`UPDATE mysql.user SET authentication_string=PASSWORD('<PASSWORD>') WHERE user='root';`

刷新

`FLUSH PRIVILEGES;`

### 增加用户

`CREATE USER '<USER>'@'%' IDENTIFIED BY '<PASSWORD>';`

`GRANT ALL PRIVILEGES ON *.* TO '<USER>'@'%';`

### 配置主从

```
# 在主执行
change master to master_host='<HOST>', master_port=3306, master_user='sync', master_password='sync', master_log_file='mysql-bin.000001'，master_log_pos=154;

start slave;

show slave status\G
```

```
# 在从执行
grant replication slave, replication client on *.* to 'sync'@'%' identified by 'sync';

flush privileges;

show master status\G
```

## 一、常用操作

