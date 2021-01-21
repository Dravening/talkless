# mongoDB性能探究

mongoDB作为一款在db-engine的nosql榜单上排名榜首的数据库，我们来测试下它的性能。

本次测试使用的server环境为8核CPU，32G内存的linux系统主机，mongoDB版本为4.0.2。

-------------------

-------------------

## 插入性能

### 执行脚本

```js
let db = connect("192.168.169.210:27017/cmdb");
db.auth("cmdb","HI9Yq4ijH2Ga");

function  insertData(db,arr){
    db.getCollection('cc_ObjectBase').insertMany(arr);
}

function loop(db){
    let arr = [];
    for (let x = 1; x<= 1000000; x++) {
        let name = "switchport" + x
        let instID = 30 + x
        arr.push(
             {
                  "bk_supplier_account":"0",
                  "bk_inst_id":NumberLong(instID),
                  "create_time" : ISODate("2021-01-21T02:20:56.544Z"),
                  "last_time" : ISODate("2021-01-21T02:20:56.544Z"),
                  "bk_obj_id":"switch_port",
                  "bindwidth":NumberLong(1000),
                  "bk_inst_name":name,
                  "status":"1",
                  "uuid":NumberLong(x)
              }
        );
        if (arr.length >= 1000) {
            insertData(db,arr);
            arr = [];
        }
    }
}

function printNow() {
    let timestamp = (new Date()).valueOf();
    print(timestamp);
}

printNow();
loop(db);
printNow();
```

### 实验结果

| 序号 | 插入总数 | 单次插入数（insertMany） | 插入次数 | 文档k:v个数 | 执行时间             |
| ---- | -------- | ------------------------ | -------- | ----------- | -------------------- |
| 1    | 0.1w     | 50                       | 20       | 5           | 264(ms)              |
| 2    | 10w      | 50                       | 2000     | 5           | 28276(ms)≈28.2(s)    |
| 3    | 10w      | 500                      | 200      | 5           | 15666(ms)≈15.7(s)    |
| 4    | 100w     | 500                      | 2000     | 5           | 121802(ms)≈2.0(min)  |
| 5    | 100w     | 1000                     | 1000     | 9           | 162577(ms)≈2.71(min) |
| 6-1  | 100w     | 500                      | 2000     | 9           | 171058(ms)≈2.85(min) |
| 6-2  | 100w     | 500                      | 2000     | 9           | 194346(ms)≈3.23(min) |

### 小结

通过对比序号2和序号3，发现同等插入数据总量的情况下，单次插入量越多，可以减少mongoDB的执行时间。

并且可以大体了解mongoDB的性能，百万数据插入时长在3min左右。

--------------------

-----------------





## 删除性能

### 执行脚本

```js
let db = connect("192.168.169.210:27017/cmdb");
db.auth("cmdb","HI9Yq4ijH2Ga");

function  deleteData(db,cond){
    db.getCollection('cc_ObjectBase').deleteMany(cond);
}

function loop(db){
    let cond = {"uuid":"999"}
    deleteData(db,cond)
}

function printNow() {
    let timestamp = (new Date()).valueOf();
    print(timestamp);
}

printNow();
loop(db);
printNow();
```

### 实验结果

执行实验时，使用下表的`删除条件`替换上方脚本中第九行`{"uuid":"999"}`

| 序号 | 查找方案 | 删除条件*(uuid无索引,bk_inst_id有索引)*                      | 集合数据总数 | 删除文档条目 | 执行时间          |
| ---- | -------- | ------------------------------------------------------------ | ------------ | ------------ | ----------------- |
| 1    | 遍历     | {"uuid":"999"}                                               | 100w         | 1            | 1960(ms)≈2(s)     |
| 2    | 遍历     | {"uuid":{"$lt":NumberLong(2000),"$gte":NumberLong(1000)}}    | 100w         | 1000         | 2245(ms)≈2.2(s)   |
| 3    | 索引     | {"bk_inst_id":{"$lt":NumberLong(3000),"$gte":NumberLong(2000)}} | 100w         | 1000         | 295(ms)≈0.3(s)    |
| 4    | 索引     | {"bk_inst_id":{"$lt":NumberLong(20000),"$gte":NumberLong(10000)}} | 100w         | 1w           | 2026(ms)≈2(s)     |
| 5    | 遍历     | {"uuid":{"$lt":NumberLong(30000),"$gte":NumberLong(20000)}}  | 99w          | 1w           | 3551(ms)≈3.6(s)   |
| 6    | 遍历     | {"status":"1"}                                               | 98w          | 98w          | 241452(ms)≈4(min) |



### 结论

大体了解mongoDB的删除性能，百万数据删除时长在4分钟左右。