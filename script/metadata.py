import requests
import json
import pprint
import sys

def hit_url(url, data_dict):
    res = requests.get(url).text.split("\n")
    for each_key in res:
        new_url= url+"/"+each_key
        if each_key.endswith('/'):
            another_key = each_key.split('/')[-2]
            final_meta[another_key]={}
            hit_url(new_url, final_meta[another_key])
        else:
            res = requests.get(new_url)
            try:
                data_dict[each_key] = json.loads(res.text)
            except:
                # pass
                data_dict[each_key] = res.text
    return data_dict

base_url = "http://169.254.169.254/latest/meta-data"
final_meta = {}
hit_url(base_url,final_meta)
if len(sys.argv)>1:
    for each_key in sys.argv[1:]:
        pprint.pprint("Requested Key Name and Value {}:{}".format(each_key,final_meta.get(each_key)))
else:
    pprint.pprint(final_meta)
