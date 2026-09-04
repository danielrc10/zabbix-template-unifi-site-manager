#!/usr/bin/env ruby

require 'open3'
require 'tempfile'
require 'yaml'

path = ARGV.fetch(0, File.expand_path('../template/template_unifi_site_manager_snmp_extension.yaml', __dir__))
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
check(root.fetch('templates').length == 1, 'exactly one extension template is expected')
template = root.fetch('templates').first
template_name = 'Template UniFi Site Manager - SNMP Extension'
check(template['template'] == template_name, 'unexpected extension template name')
check(template.dig('vendor', 'version').match?(/\A\d+\.\d+\.\d+\z/), 'extension version must use semantic versioning')
check(template['description'].include?('Não substitui') && template['description'].include?('never replaces'), 'description must state that SNMP never replaces API monitoring')
check(template['description'].include?('SMART') && template['description'].include?('RAID'), 'storage limitation must be explicit')

objects = []
collect = lambda do |value|
  case value
  when Hash
    objects << value
    value.each_value { |child| collect.call(child) }
  when Array
    value.each { |child| collect.call(child) }
  end
end
collect.call(root)

uuid_pattern = /\A[0-9a-f]{12}4[0-9a-f]{3}[89ab][0-9a-f]{15}\z/
uuids = objects.map { |object| object['uuid'] }.compact
uuids.each { |uuid| check(uuid.match?(uuid_pattern), "invalid UUID #{uuid.inspect}") }
check(uuids.uniq.length == uuids.length, 'UUIDs are not unique')

items = template.fetch('items') + template.fetch('discovery_rules').flat_map { |rule| rule.fetch('item_prototypes', []) }
keys = items.map { |item| item.fetch('key') }
check(keys.uniq.length == keys.length, 'SNMP extension item keys are not unique')
snmp_items = items.select { |item| item['type'] == 'SNMP_AGENT' }
check(snmp_items.length >= 20, 'expected a useful SNMP enrichment set')
snmp_items.each do |item|
  check(item.fetch('snmp_oid').start_with?('get['), "#{item['key']} must use an explicit numeric OID")
  check(item.fetch('snmp_oid').match?(/\Aget\[[0-9.{}#A-Z]+\]\z/), "unexpected OID syntax on #{item['key']}")
end

rules = template.fetch('discovery_rules')
%w[unifi.snmp.interfaces.discovery unifi.snmp.radios.discovery unifi.snmp.vaps.discovery].each do |key|
  rule = rules.find { |candidate| candidate['key'] == key }
  check(rule && rule['type'] == 'SNMP_AGENT', "missing SNMP discovery #{key}")
  check(rule.fetch('snmp_oid').start_with?('discovery['), "#{key} must use SNMP discovery")
  check(rule['delay'] == '{$UNIFI.SNMP.DISCOVERY.INTERVAL}', "#{key} has an unexpected interval")
end

macro_names = template.fetch('macros').map { |macro| macro.fetch('macro') }
%w[
  {$UNIFI.SNMP.INTERVAL}
  {$UNIFI.SNMP.INVENTORY.INTERVAL}
  {$UNIFI.SNMP.DISCOVERY.INTERVAL}
  {$UNIFI.SNMP.IFCONTROL}
  {$UNIFI.SNMP.RADIO.UTIL.WARN}
].each { |macro| check(macro_names.include?(macro), "missing macro #{macro}") }
used_macros = source.scan(/\{\$[A-Z0-9._]+(?::"[^\"]+")?\}/).uniq
used_macro_bases = used_macros.map { |macro| macro.sub(/:"[^\"]+"/, '') }
check((used_macro_bases - macro_names).empty?, "undefined macros: #{(used_macro_bases - macro_names).join(', ')}")

check(source.include?('1.3.6.1.4.1.41112.1.6'), 'official Ubiquiti UI-MIB subtree is absent')
check(source.include?('1.3.6.1.2.1.31.1.1.1.6'), 'IF-MIB high-capacity inbound counter is absent')
check(!source.match?(/smart|raid|disk/i) || template['description'].match?(/no disk|não publica discos/i), 'storage must not be fabricated through SNMP')
check(!source.include?('SNMP_TRAP'), 'Ubiquiti currently documents polling, not SNMP traps')

javascript = []
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
    Tempfile.create(['unifi-snmp-js-', '.js']) do |file|
      file.write("function zabbixCheck(value) {\n#{code}\n}\n")
      file.flush
      _stdout, stderr, status = Open3.capture3(node, '--check', file.path)
      check(status.success?, "JavaScript syntax error in #{label}: #{stderr.strip}")
    end
  end
end

puts "OK: #{path} parsed and passed SNMP extension checks"
puts "    #{rules.length} LLD rules, #{snmp_items.length} SNMP items/prototypes, #{uuids.length} deterministic UUIDv4 values"
