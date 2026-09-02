#!/usr/bin/env ruby

# PT-BR: Validação estrutural do template UniFi Site Manager.
# EN: Structural validation for the UniFi Site Manager template.

require 'json'
require 'open3'
require 'tempfile'
require 'yaml'

default_path = File.expand_path('../template/template_unifi_site_manager.yaml', __dir__)
path = ARGV.fetch(0, default_path)
source = File.read(path)
data = YAML.safe_load(source, permitted_classes: [], aliases: false)

def check(condition, message)
  raise "VALIDATION ERROR: #{message}" unless condition
end

walk_scalars = lambda do |value, current_path = []|
  case value
  when Hash
    value.each { |key, child| walk_scalars.call(child, current_path + [key]) }
  when Array
    value.each_with_index { |child, index| walk_scalars.call(child, current_path + [index]) }
  else
    check(value.is_a?(String), "non-string scalar at #{current_path.join('.')}: #{value.inspect}")
  end
end
walk_scalars.call(data)

root = data.fetch('zabbix_export')
check(root['version'] == '7.4', 'export version must be 7.4')
check(root.fetch('templates').length == 1, 'exactly one template is expected')
template = root.fetch('templates').first
template_name = 'Template UniFi Site Manager by HTTP'
check(template['template'] == template_name, 'unexpected technical template name')

all_objects = []
collect = lambda do |value|
  case value
  when Hash
    all_objects << value
    value.each_value { |child| collect.call(child) }
  when Array
    value.each { |child| collect.call(child) }
  end
end
collect.call(root)

uuid_pattern = /\A[0-9a-f]{12}4[0-9a-f]{3}[89ab][0-9a-f]{15}\z/
uuids = all_objects.map { |object| object['uuid'] }.compact
uuids.each { |value| check(value.match?(uuid_pattern), "invalid UUID #{value.inspect}") }
check(uuids.uniq.length == uuids.length, 'UUIDs are not unique')

rules = template.fetch('discovery_rules')
required_rules = {
  'LLD - Sites (Independent + Fabric)' => %w[{#SITE.ID} {#SITE.NAME} {#SITE.TYPE}],
  'LLD - Network devices (Gateways, Switches and APs)' => %w[{#DEVICE.MAC} {#DEVICE.NAME} {#DEVICE.MODEL} {#DEVICE.SITE.ID}],
  'LLD - Switch ports' => %w[{#SWITCH.MAC} {#PORT.NUM} {#PORT.NAME}],
  'LLD - Protect cameras' => %w[{#CAMERA.ID} {#CAMERA.NAME} {#CAMERA.MODEL} {#CAMERA.SITE.ID}],
  'LLD - Protect/NVR disks and storage' => %w[{#DISK.ID} {#DISK.MODEL} {#DISK.SERIAL} {#DEVICE.MAC}],
  'LLD - WAN links' => %w[{#WAN.NAME}],
  'LLD - Dynamic routing (BGP/OSPF capability placeholder)' => %w[{#PEER.IP} {#PROTOCOL} {#NEIGHBOR.NAME}],
  'LLD - Subnets and DHCP pools' => %w[{#SUBNET.NAME} {#SUBNET.CIDR}],
  'LLD - WiFi SSIDs' => %w[{#SSID.NAME}],
  'LLD - AP radios' => %w[{#AP.MAC} {#RADIO.BAND}]
}

required_rules.each do |name, required_macros|
  rule = rules.find { |candidate| candidate['name'] == name }
  check(rule, "missing discovery rule #{name}")
  paths = rule.fetch('lld_macro_paths').map { |entry| entry.fetch('lld_macro') }
  required_macros.each { |macro| check(paths.include?(macro), "#{name} is missing #{macro}") }
end

check(rules.find { |rule| rule['key'] == 'unifi.routing.discovery' }['status'] == 'DISABLED',
  'unsupported dynamic-routing rule must remain disabled')

items = template.fetch('items') + rules.flat_map { |rule| rule.fetch('item_prototypes', []) }
keys = items.map { |item| item.fetch('key') }
check(keys.uniq.length == keys.length, 'item and prototype keys are not unique')

http_items = items.select { |item| item['type'] == 'HTTP_AGENT' }
check(http_items.length >= 10, 'expected at least ten asynchronous HTTP Agent collectors')
http_items.each do |item|
  headers = item.fetch('headers').to_h { |entry| [entry.fetch('name'), entry.fetch('value')] }
  check(headers['X-API-Key'] == '{$UNIFI.API.KEY}', "#{item['key']} does not use the API key header")
  check(headers['Accept'] == 'application/json', "#{item['key']} does not request JSON")
  check(item['verify_peer'] == 'YES' && item['verify_host'] == 'YES', "TLS verification is disabled on #{item['key']}")
  check(item.fetch('url').start_with?('{$UNIFI.API.URL}/'), "unexpected URL on #{item['key']}")
end

items.select { |item| item['type'] == 'DEPENDENT' }.each do |item|
  master = item.fetch('master_item').fetch('key')
  check(keys.include?(master), "dependent item #{item['key']} references missing master #{master}")
end

macro_names = template.fetch('macros').map { |macro| macro.fetch('macro') }
required_macros = %w[
  {$UNIFI.API.KEY}
  {$WAN1.EXPECTED.DL}
  {$WAN1.EXPECTED.UL}
  {$WAN2.EXPECTED.DL}
  {$WAN2.EXPECTED.UL}
  {$WAN.SPEED.THRESHOLD.PCT}
  {$DHCP.THRESHOLD.PCT}
  {$TEMP.MAX.WARN}
]
required_macros.each { |macro| check(macro_names.include?(macro), "missing macro #{macro}") }
used_macros = source.scan(/\{\$[A-Z0-9._]+\}/).uniq
check((used_macros - macro_names).empty?, "undefined macros: #{(used_macros - macro_names).join(', ')}")
api_key = template.fetch('macros').find { |macro| macro['macro'] == '{$UNIFI.API.KEY}' }
check(api_key['type'] == 'SECRET_TEXT', 'API key macro must be SECRET_TEXT')
check(!api_key.key?('value'), 'API key macro must not contain a committed value')

triggers = all_objects.select { |object| object.key?('expression') && object.key?('priority') }
required_trigger_fragments = {
  'SMART failure' => 'DISASTER',
  'camera {#CAMERA.NAME} is disconnected' => 'DISASTER',
  'enabled but not recording' => 'DISASTER',
  'adjacency lost' => 'DISASTER',
  'Primary WAN is down' => 'DISASTER',
  'WAN failover is active' => 'HIGH',
  'device {#DEVICE.NAME} is offline' => 'HIGH',
  'Speedtest below' => 'HIGH',
  'Unexpected reboot' => 'HIGH',
  'Link speed degraded' => 'AVERAGE',
  'DHCP pool usage is high' => 'AVERAGE',
  'High WiFi channel utilization' => 'AVERAGE',
  'Recording mode changed' => 'WARNING',
  'Firewall/ACL rules changed' => 'WARNING',
  'VLAN changed' => 'WARNING',
  'Firmware update available' => 'INFO'
}
required_trigger_fragments.each do |fragment, priority|
  found = triggers.find { |trigger| trigger['name'].include?(fragment) }
  check(found, "missing trigger containing #{fragment.inspect}")
  check(found['priority'] == priority, "wrong priority for #{found['name']}")
end
check(template['description'].include?('BGP/OSPF'), 'official API capability limitations are not documented')

javascript = []
rules.each { |rule| javascript << [rule['key'], rule['params']] if rule['type'] == 'SCRIPT' }
items.each do |item|
  item.fetch('preprocessing', []).each_with_index do |step, index|
    javascript << ["#{item['key']} preprocessing #{index}", step.fetch('parameters').first] if step['type'] == 'JAVASCRIPT'
  end
end

node = ENV.fetch('PATH', '').split(File::PATH_SEPARATOR)
  .map { |directory| File.join(directory, 'node') }
  .find { |candidate| File.file?(candidate) && File.executable?(candidate) }
if node
  javascript.each do |label, code|
    Tempfile.create(['unifi-js-', '.js']) do |file|
      file.write("function zabbixCheck(value) {\n#{code}\n}\n")
      file.flush
      _stdout, stderr, status = Open3.capture3(node, '--check', file.path)
      check(status.success?, "JavaScript syntax error in #{label}: #{stderr.strip}")
    end
  end
end

check(!source.match?(/X-API-Key:\s*[A-Za-z0-9_-]{20,}/), 'a possible real API key is present')
check(!source.include?('verify_peer: \'NO\''), 'TLS peer verification must not be disabled')
check(!source.include?('verify_host: \'NO\''), 'TLS host verification must not be disabled')

puts "OK: #{path} parsed and passed structural checks"
puts "    #{rules.length} LLD rules, #{http_items.length} HTTP Agent collectors, #{items.length} total items/prototypes"
puts "    #{triggers.length} triggers/prototypes, #{uuids.length} unique deterministic UUIDv4 values"
