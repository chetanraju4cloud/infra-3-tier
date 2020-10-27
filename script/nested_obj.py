def grab_values(input_dict, keys):
    list_keys = keys.split("/")
    res = input_dict.get(list_keys[0],{})
    if len(list_keys)>1 and isinstance(res, dict):
        return grab_values(res, "/".join(list_keys[1:]))
    else:
        return res

di = {"a":{"b":{"c":"d"}}}
ke = "a/b/c"
print(grab_values(di, ke))
