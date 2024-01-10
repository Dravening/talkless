# clickhouse运维小全

## 一、安装

### Local安装

1.获取clickhouse的全部安装rpm

2.yum localinstall *rpm -y

## 二、常用命令

### 登录

`clickhouse-client -h127.0.0.1 --port 9000 -u<USER> --password <PASSWORD> --multiquery`

### 权限

`GRANT ON CLUSTER <CLUSTER_NAME> SELECT(<COLUME_NAME1>,<COLUME_NAME2>) ON <DB_NAME>.<TABLE_NAME> TO <USER_NAME>`

### 使用

##### 创建view

`create view <VIEW_NAME> as select <COLUME_NAME1>,<COLUME_NAME2> from <DB_NAME>.<TABLE_NAME> where xxx=xxx;`

