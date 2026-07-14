curl -k -s \
  -u "icingaadmin:vnit" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -X PUT "http://monitoring.vn.internal:8080/director/service?name=Nuclei" \
  -d '{
    "object_name": "Nuclei",
    "object_type": "apply",
    "check_command": "passive",
    "enable_active_checks": false,
    "enable_passive_checks": true,
    "assign_filter": "\"Wordpress\" in host.templates"
  }' | jq .
