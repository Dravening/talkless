wrk.method = "POST"
wrk.body   = "foo=bar&baz=quux"
wrk.headers["Content-Type"] = "application/x-www-form-urlencoded"

math.randomseed(os.time())

function getRandom()
    local t = {
        "switch_port","tenant","tenant_vms",
    }
    local s = t[math.random(3)]
    return s
end


request = function()
    local headers = { }
    headers['Content-Type'] = "application/json"
    local a = math.random(900000)
    local obj = getRandom()

    local body = {
        bk_app_code="bk_sops",
        bk_app_secret="72f2505a-585c-44e5-858a-dc1e76e0d33a",
        bk_username="admin",
        bk_obj_id=obj,
        bk_supplier_account="0",
        condition={},
        page={
            start=a,
            limit=20,
            sort="bk_inst_id"
        }
    }
    local cjson = require("cjson")
    local body_str = cjson.encode(body)
    print(body_str)
    return wrk.format('POST', nil, headers, body_str)
end

success_number = 0
fail_number = 0
function response(status,headers,body)
    local cjson = require("cjson")
    local body_table = cjson.decode(body)
    local code = body_table.code
    if code ~= 0 then --将服务器返回状态码不是200的请求结果打印出来
        fail_number = fail_number + 1
        print("fail_number:" .. fail_number)
        print(body)
        --      wrk.thread:stop()
    else
        success_number = success_number + 1
        print("success_number:" .. success_number)
        print(body)
    end
end