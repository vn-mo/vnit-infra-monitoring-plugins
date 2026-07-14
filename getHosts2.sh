curl -v -k -s \
  -u root:d04e0e3607dd5c8c \
  -H "Accept: application/json" \
  -H "X-HTTP-Method-Override: GET" \
  -X POST https://monitoring.vn.internal:5665/v1/objects/hosts \
  -d '{
    "filter": "\"Windows Agents\" in host.templates",
    "attrs": [ "name", "address", "templates" ],
    "pretty": true
  }' \
  | jq -r '.results[].name'
