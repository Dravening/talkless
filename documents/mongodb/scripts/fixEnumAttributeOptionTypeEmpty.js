function fixEnumAttributeOptionTypeEmpty() {
    let filter = {
        bk_property_type: "enum"
    };
    cursor = db.cc_ObjAttDes.find(filter);
    while(cursor.hasNext()) {
        let attr = cursor.next();
        if (attr.option != null) {
            for (let index = 0; index < attr.option.length; index++) {
                if (!attr.option[index].type || attr.option[index].type == "") {
                    attr.option[index].type = "text"
                }
            }
        }
        let filter = {
            id : attr.id
        };
        let opt = {
            $set: {
                option : attr.option ,
            }
        };
        db.cc_ObjAttDes.updateOne(filter, opt);
    }
}
fixEnumAttributeOptionTypeEmpty();