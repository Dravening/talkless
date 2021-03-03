let db = connect("192.168.169.210:27017/cmdb");
db.auth("cmdb","HI9Yq4ijH2Ga");

function  insertData(db,arr){
    let c = db.getCollection('cc_ObjectBase').insertMany(arr);
}

function loop(db){
    let arr = [];
    for (let x = 1; x<= 1000000; x++) {
        name = "switchport" + x
        instID = 30 + x
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
        };
    }
}

function printNow() {
    let timestamp = (new Date()).valueOf();
    print(timestamp);
}

printNow();
loop(db);
printNow();





