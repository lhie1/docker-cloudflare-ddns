#!/usr/bin/with-contenv sh

cloudflare() {
  if [ -f "$API_KEY_FILE" ]; then
      API_KEY=$(cat "$API_KEY_FILE")
  fi
  
  AUTH_HEADER="-H \"Authorization: Bearer $API_KEY\""
  if [ ! -z "$EMAIL" ]; then
      AUTH_HEADER="-H \"X-Auth-Email: $EMAIL\" -H \"X-Auth-Key: $API_KEY\""
  fi

  curl -sSL \
      -H "Accept: application/json" \
      -H "Content-Type: application/json" \
      $AUTH_HEADER \
      "$@"
}

getIpAddress() {
  local method=$1
  local filter=$2
  local interface=${3:-$INTERFACE}
  local custom_cmd=${4:-$CUSTOM_LOOKUP_CMD}

  case $method in
    local)
      ip addr show "$interface" | awk "\$1 == \"$filter\" {gsub(/\/.*$/, \"\", \$2); print \$2; exit}"
      ;;
    custom)
      sh -c "$custom_cmd"
      ;;
    public)
      IP_ADDRESS=$(curl -4 ip.sb)
      if [ -z "$IP_ADDRESS" ]; then
        DNS_SERVER=${DNS_SERVER:=1.1.1.1}
        CLOUD_FLARE_IP=$(dig +short @$DNS_SERVER ch txt whoami.cloudflare +time=3 | tr -d '"')
        IP_ADDRESS=$([ ${#CLOUD_FLARE_IP} -gt 15 ] && dig +short myip.opendns.com @resolver1.opendns.com +time=3 || echo "$CLOUD_FLARE_IP")
      fi
      echo "$IP_ADDRESS"
      ;;
    public6)
      IP_ADDRESS=$(curl -6 ip.sb)
      if [ -z "$IP_ADDRESS" ]; then
        IP_ADDRESS=$(dig +short @2606:4700:4700::1111 -6 ch txt whoami.cloudflare | tr -d '"')
      fi
      echo "$IP_ADDRESS"
      ;;
  esac
}

getDnsRecordName() {
  [ ! -z "$SUBDOMAIN" ] && echo "$SUBDOMAIN.$ZONE" || echo "$ZONE"
}

verifyToken() {
  if [ -z "$EMAIL" ]; then
    cloudflare -o /dev/null -w "%{http_code}" "$CF_API/user/tokens/verify"
  else
    cloudflare -o /dev/null -w "%{http_code}" "$CF_API/user"
  fi
}

getZoneId() {
  cloudflare "$CF_API/zones?name=$ZONE" | jq -r '.result[0].id'
}

getDnsRecordId() {
  cloudflare "$CF_API/zones/$1/dns_records?type=$RRTYPE&name=$2" | jq -r '.result[0].id'
}

createDnsRecord() {
  local proxied=${PROXIED:-false}
  cloudflare -X POST -d "{\"type\": \"$RRTYPE\",\"name\":\"$2\",\"content\":\"$3\",\"proxied\":$proxied,\"ttl\":1 }" "$CF_API/zones/$1/dns_records" | jq -r '.result.id'
}

updateDnsRecord() {
  local proxied=${PROXIED:-false}
  cloudflare -X PATCH -d "{\"type\": \"$RRTYPE\",\"name\":\"$3\",\"content\":\"$4\",\"proxied\":$proxied }" "$CF_API/zones/$1/dns_records/$2" | jq -r '.result.id'
}

deleteDnsRecord() {
  cloudflare -X DELETE "$CF_API/zones/$1/dns_records/$2" | jq -r '.result.id'
}

getDnsRecordIp() {
  cloudflare "$CF_API/zones/$1/dns_records/$2" | jq -r '.result.content'
}

main() {
  case $1 in
    local)
      getIpAddress local inet "$2"
      ;;
    local6)
      getIpAddress local inet6 "$2"
      ;;
    custom)
      getIpAddress custom "" "" "$2"
      ;;
    public)
      getIpAddress public
      ;;
    public6)
      getIpAddress public6
      ;;
    verify)
      verifyToken
      ;;
    zone)
      getZoneId
      ;;
    record)
      getDnsRecordId "$2" "$3"
      ;;
    create)
      createDnsRecord "$2" "$3" "$4"
      ;;
    update)
      updateDnsRecord "$2" "$3" "$4"
      ;;
    delete)
      deleteDnsRecord "$2" "$3"
      ;;
    getIp)
      getDnsRecordIp "$2" "$3"
      ;;
    *)
      echo "Usage: $0 {local|local6|custom|public|public6|verify|zone|record|create|update|delete|getIp}"
      ;;
  esac
}

main "$@"
