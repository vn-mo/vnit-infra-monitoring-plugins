curl -k -s -u icingaadmin:vnit \
  -H "Accept: application/json" \
  -H "X-HTTP-Method-Override: GET" \
  -X POST https://monitoring.vn.internal:5665/v1/objects/hosts \
  -d '{
    "filter": "\"Windows Agents\" in host.templates",
    "pretty": true
  }'

