let db = connect("192.168.169.210:27017/cmdb");
db.auth("cmdb","HI9Yq4ijH2Ga");

function  insertData(db,arr){
    let c = db.getCollection('cc_InstAsst').insertMany(arr);
}

function loop(db){
    let arr = [];
    for (let x = 600001; x<= 1000000; x++) {
        instID = 30 + x
        arr.push(
            {
                  "id" : NumberLong(x),
                  "bk_inst_id" : NumberLong(3),
                  "bk_obj_id" : "bk_switch",
                  "bk_asst_inst_id" : NumberLong(instID),
                  "bk_asst_obj_id" : "switch_port",
                  "bk_supplier_account" : "0",
                  "bk_obj_asst_id" : "bk_switch_default_switch_port",
                  "bk_asst_id" : "default",
                  "bk_biz_id" : NumberLong(0)
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





