## cacheservice服务无限重启问题解决方案

cacheservice服务无限重启，大概率是崩溃保护机制不健全的缘故，在3.9.12和3.9.14版本均有发现。往往在mongodb崩溃之后，或cmdb重启之后就会出现。

> ***本次给出粗暴解决方案，官方不推荐正式环境使用。***

**步骤1：**

**清空mongodb的“cc_DelArchive”集合内文档。**

```sql
db.getCollection('cc_DelArchive').deleteMany({})
```

 

**步骤2：**

**清除redis内相关的键值。**

**参考脚本如下：**

```shell
[root@localhost data]# cat redis_del.sh
#!/bin/bash
redis-cli -h 192.168.169.213 -p 6380 <<EOF
auth WegMjMwLClRl
del cc:v3:watch:host:chain tail
del cc:v3:watch:host_relation:chain tail
del cc:v3:watch:biz:chain tail
del cc:v3:watch:set:chain tail
del cc:v3:watch:module:chain tail
del cc:v3:watch:set_template:chain tail
del cc:v3:watch:object:chain tail
del cc:v3:watch:process:chain tail
del cc:v3:watch:process_instance:chain tail
EOF
[root@localhost data]#
```

这样操作后，cmdb的cacheservice即可正常启动。

> ***注意：再次提醒，本方案不适合正式环境使用。***