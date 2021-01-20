let db = connect("192.168.169.210:27017/cmdb");
db.auth("cmdb","HI9Yq4ijH2Ga");

function  insertData(db,arr){
    db.getCollection('cc_ObjectBase').insertMany(arr);
}

function loop(db){
    let arr = [];
    for (let x = 0; x< 1000000; x++) {
        let name = "switchport" + x
        arr.push(
            {
                "bindwidth":1000,
                "bk_inst_name":name,
                "status":"1",
                "uuid":x
            }
        );
        if (arr.length >= 500) {
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




