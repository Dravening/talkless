let db = connect("192.168.169.210:27017/cmdb");
db.auth("cmdb","HI9Yq4ijH2Ga");

function  deleteData(db,cond){
    db.getCollection('cc_ObjectBase').deleteMany(cond);
}

function loop(db){
    cond = {"bk_obj_id":"switch_port","bk_inst_id":{$gt:1000}}
    deleteData(db,cond)
}

function printNow() {
    let timestamp = (new Date()).valueOf();
    print(timestamp);
}

printNow();
loop(db);
printNow();





