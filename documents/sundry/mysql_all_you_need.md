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

`set global validate_password.policy=LOW; ------ mysql8`

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

### sql replace
update <table> set <column> = replace(<column>, '<source>', '<target>');

### 数据库备份

```
#!/bin/bash

backup_database=$1
backup_table=$2

excute_date=$(date +"%Y%m%d")
excute_time=$(date +"%Y%m%d_%H%M")
backupdir=~/mysqlbackup/$excute_date
MYSQLPASS="XXXXXXXXXXXX"

[ -z "$backup_database" ] && {
    echo "请输入要备份的数据库, 支持所有库/单库/单库下的某个表"
    exit 1
}

[ -n "$backup_table" ] && {
    echo "单表备份模式: 备份表==> $backup_table"
}

while [ "$MYSQLPASS" == "" ]; do
    read -s -p "请输入MySQLroot用户密码: " MYSQLPASS
done

excute_date=$(date +"%Y%m%d")
excute_time=$(date +"%Y%m%d_%H%M")
backupdir=~/mysqlbackup/$excute_date

mysql_user=root
mysql_password="$MYSQLPASS"
mysql_port=3306
mysql_host=localhost
mysql_cmd="mysql -u$mysql_user -p$mysql_password -h $mysql_host -P $mysql_port"

[ ! -d $backupdir ] && mkdir -p $backupdir

check_mysql_dbname() {
    $mysql_cmd -e "show databases" | grep -w $backup_database || {
        echo "Database $backup_database 不存在, 请检查"
        exit 1
    }
}

check_mysql_table() {
    $mysql_cmd $backup_database -e "desc $backup_table;" | grep -q Field || {
        echo "Database $backup_database -> Table $backup_table 不存在, 请检查"
        exit 1
    }
}

backup_single_dbname() {
    local dbname=$1
    local ignore_table_db=onedata
    if [[ "$dbname" =~ "onedata" ]];then
        ignore_table_db=$dbname
    fi
    mysqldump -u$mysql_user -p$mysql_password -h $mysql_host -P $mysql_port --ignore-table=${ignore_table_db}.bi_cache --single-transaction --databases $dbname -c | \
        gzip > $backupdir/${dbname}_backup_${excute_time}.gz
}

backup_single_table() {
    local dbname=$1
    local table_name=$2
    mysqldump -u$mysql_user -p$mysql_password -h $mysql_host -P $mysql_port --ignore-table=${ignore_table_db}.bi_cache --single-transaction $dbname $table_name -c | \
        gzip > $backupdir/${dbname}_TABLE_${table_name}_backup_${excute_time}.gz
}

backup_all_db() {
    $mysql_cmd -e "show databases" \
        | grep -Evw "Database|mysql|information_schema|performance_schema|sys" | while read dbname; do
        echo $dbname
        backup_single_dbname $dbname
    done
    exit 0
}

function choose_database() {
    read -p "SELECT which database to backup" Database
    $mysql_cmd -e "show databases" | grep -Ev "Database"
}

function clean_backup_file() {
    local clean_dir=${1:-$backupdir/..}
    local keep_some_days=${2:-60}
    [ -z "$clean_dir" ] && {
        echo "需要指定删除目录"
        return 1
    }
    find $clean_dir -ctime +$keep_some_days -name "*.gz" -exec rm {} \;
}

if [ "$backup_database" == "all" ];then
    backup_all_db
elif [ -n "$backup_table" ];then
    check_mysql_dbname
    check_mysql_table
    backup_single_table $backup_database $backup_table
else
    check_mysql_dbname
    backup_single_dbname $backup_database
fi

clean_backup_file
```