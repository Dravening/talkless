let db = connect("192.168.169.210:27017/cmdb");
db.auth("cmdb","HI9Yq4ijH2Ga");

// 平台版本2.5填0，平台版本3.0填1
const bkVersion = 1

// delStartDay最好填一个比较大的数，如果客户的cmdb是156天前部署的，这里可以填160。
let delStartDay = 160

// delEndDay是保留多少天前的数据，如果希望保留一个月的审计，这里填30。
let delEndDay = 30


//------------请用户按需填写上方内容---------------

//------------请用户不要修改下方内容---------------
let  arr  = ["cc_OperationLog", "cc_AuditLog"];
let collectionName = arr[bkVersion];

function countData(db, i) {
    let y = Math.floor(new Date(new Date()-1000*60*60*24*i).getTime()/1000).toString(16) + "0000000000000000"
    print("_id: ", y)
    return db.getCollection(collectionName).find({_id: {$lt:new ObjectId( Math.floor(new Date(new Date()-1000*60*60*24*i).getTime()/1000).toString(16) + "0000000000000000" )}}).count()
}

function deleteOperationLog(i) {
    db.getCollection(collectionName).deleteMany({_id: {$lt:new ObjectId( Math.floor(new Date(new Date()-1000*60*60*24*i).getTime()/1000).toString(16) + "0000000000000000" )}});
}

function loop(db){
    let totalDel = 0
    for (i = delStartDay; i > delEndDay; i--) {
        let num = countData(db, i);
        print("del count: ", num);
        deleteOperationLog(i);
        totalDel = totalDel  +  num
        sleep(200);
    }
    print("del count total: ", totalDel);
}

function printNow() {
    // 此时间戳用来记录执行脚本的时间
    let timestamp = (new Date()).valueOf();
    print("timestamp: ", timestamp);
}

printNow();
loop(db);
printNow();
