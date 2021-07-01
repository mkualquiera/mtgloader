import requests
import json
import sys

uri = sys.argv[1]

request = requests.get(uri)
jsonresp = request.json()

for card in jsonresp["data"]:
    print("1",card["id"])