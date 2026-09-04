#!/usr/bin/env ruby

# PT-BR: Gerador determinístico da extensão SNMP do projeto UniFi Site Manager.
# EN: Deterministic generator for the UniFi Site Manager SNMP extension.

require 'digest'
require 'yaml'

TEMPLATE_NAME = 'Template UniFi Site Manager - SNMP Extension'
TEMPLATE_VERSION = '1.0.0'
OUTPUT = File.expand_path('../template/template_unifi_site_manager_snmp_extension.yaml', __dir__)

def uuid(seed)
  value = Digest::SHA256.hexdigest("unifi-site-manager-snmp-extension/#{seed}")[0, 32]
  value[12] = '4'
  value[16] = '8'
  value
end

def tags(component, extra = {})
  [{'tag' => 'component', 'value' => component}] +
    extra.map { |tag, value| {'tag' => tag, 'value' => value} }
end

def preprocessing(type, parameter = nil)
  step = {'type' => type}
  step['parameters'] = [parameter] if parameter
  [step]
end

def snmp_item(seed:, name:, key:, oid:, delay:, value_type: nil, units: nil, description:, item_tags:)
  item = {
    'uuid' => uuid(seed),
    'name' => name,
    'type' => 'SNMP_AGENT',
    'snmp_oid' => "get[#{oid}]",
    'key' => key,
    'delay' => delay,
    'history' => '30d',
    'description' => description,
    'tags' => item_tags.map(&:dup)
  }
  item['value_type'] = value_type if value_type
  item['trends'] = %w[CHAR TEXT LOG].include?(value_type) ? '0' : '365d'
  item['units'] = units if units
  item
end

def snmp_prototype(seed:, name:, key:, oid:, value_type: nil, units: nil, description:, item_tags:,
                   preprocessing_steps: [], triggers: [])
  item = snmp_item(
    seed: seed,
    name: name,
    key: key,
    oid: oid,
    delay: '{$UNIFI.SNMP.INTERVAL}',
    value_type: value_type,
    units: units,
    description: description,
    item_tags: item_tags
  )
  item['preprocessing'] = preprocessing_steps unless preprocessing_steps.empty?
  item['trigger_prototypes'] = triggers unless triggers.empty?
  item
end

def trigger(seed:, expression:, name:, priority:, description:, opdata: nil, tags_hash: {})
  result = {
    'uuid' => uuid(seed),
    'expression' => expression,
    'name' => name,
    'priority' => priority,
    'description' => description,
    'tags' => [{'tag' => 'scope', 'value' => 'performance'}] +
      tags_hash.map { |tag, value| {'tag' => tag, 'value' => value} }
  }
  result['opdata'] = opdata if opdata
  result
end

items = []

snmp_availability = {
  'uuid' => uuid('snmp-availability'),
  'name' => 'UniFi SNMP extension: Agent availability',
  'type' => 'INTERNAL',
  'key' => 'zabbix[host,snmp,available]',
  'history' => '30d',
  'trends' => '365d',
  'description' => 'Availability of the SNMP interface used only by this optional extension.',
  'valuemap' => {'name' => 'Zabbix host availability'},
  'tags' => tags('SNMP', 'scope' => 'extension'),
  'triggers' => [
    trigger(
      seed: 'trigger-snmp-unavailable',
      expression: 'max(/Template UniFi Site Manager - SNMP Extension/zabbix[host,snmp,available],{$UNIFI.SNMP.TIMEOUT})=0',
      name: '[Warning] UniFi SNMP extension cannot collect from this device',
      priority: 'WARNING',
      description: 'The API-first template remains independent. This event indicates only that optional local SNMP enrichment is unavailable.',
      opdata: 'SNMP availability: {ITEM.LASTVALUE1}',
      tags_hash: {'component' => 'snmp-extension'}
    )
  ]
}
items << snmp_availability

[
  ['system-ip', 'Management IP reported by UI-MIB', 'unifi.snmp.system.ip', '1.3.6.1.4.1.41112.1.6.3.1.0', 'CHAR'],
  ['system-model', 'Model reported by UI-MIB', 'unifi.snmp.system.model', '1.3.6.1.4.1.41112.1.6.3.3.0', 'CHAR'],
  ['system-uplink', 'Uplink information reported by UI-MIB', 'unifi.snmp.system.uplink', '1.3.6.1.4.1.41112.1.6.3.4.0', 'CHAR'],
  ['system-version', 'Firmware version reported by UI-MIB', 'unifi.snmp.system.version', '1.3.6.1.4.1.41112.1.6.3.6.0', 'CHAR']
].each do |seed, name, key, oid, value_type|
  item = snmp_item(
    seed: seed,
    name: name,
    key: key,
    oid: oid,
    delay: '{$UNIFI.SNMP.INVENTORY.INTERVAL}',
    value_type: value_type,
    description: 'Ubiquiti UI-MIB scalar. Primarily implemented by supported UniFi access points.',
    item_tags: tags('Inventory', 'scope' => 'snmp-extension')
  )
  item['preprocessing'] = preprocessing('DISCARD_UNCHANGED_HEARTBEAT', '12h')
  items << item
end

system_uptime = snmp_item(
  seed: 'system-uptime',
  name: 'System uptime reported by UI-MIB',
  key: 'unifi.snmp.system.uptime',
  oid: '1.3.6.1.4.1.41112.1.6.3.5.0',
  delay: '{$UNIFI.SNMP.INTERVAL}',
  units: 'uptime',
  description: 'Device uptime from unifiApSystemUptime. This complements cloud-reported startupTime.',
  item_tags: tags('System', 'scope' => 'snmp-extension')
)
system_uptime['triggers'] = [
  trigger(
    seed: 'trigger-snmp-reboot',
    expression: 'last(/Template UniFi Site Manager - SNMP Extension/unifi.snmp.system.uptime)<10m and change(/Template UniFi Site Manager - SNMP Extension/unifi.snmp.system.uptime)<0',
    name: '[High] UniFi device reboot detected by SNMP',
    priority: 'HIGH',
    description: 'The local UI-MIB uptime decreased and is below ten minutes.',
    opdata: 'Uptime: {ITEM.LASTVALUE1}',
    tags_hash: {'component' => 'snmp-extension'}
  )
]
items << system_uptime

isolated = snmp_item(
  seed: 'system-isolated',
  name: 'Access point isolation state',
  key: 'unifi.snmp.system.isolated',
  oid: '1.3.6.1.4.1.41112.1.6.3.2.0',
  delay: '{$UNIFI.SNMP.INTERVAL}',
  description: 'UI-MIB TruthValue normalized to 1 when the access point is isolated.',
  item_tags: tags('Health', 'scope' => 'snmp-extension')
)
isolated['preprocessing'] = preprocessing('JAVASCRIPT', 'return Number(value) === 1 ? 1 : 0;')
isolated['valuemap'] = {'name' => 'Boolean'}
isolated['triggers'] = [
  trigger(
    seed: 'trigger-ap-isolated',
    expression: 'last(/Template UniFi Site Manager - SNMP Extension/unifi.snmp.system.isolated)=1',
    name: '[High] UniFi access point is isolated',
    priority: 'HIGH',
    description: 'The local UI-MIB reports the AP isolation flag.',
    opdata: 'Isolated: {ITEM.LASTVALUE1}',
    tags_hash: {'component' => 'wireless'}
  )
]
items << isolated

interface_tags = tags('Interface', 'scope' => 'snmp-extension', 'interface' => '{#IFNAME}')
interface_items = []

interface_items << snmp_prototype(
  seed: 'if-admin-status',
  name: 'Interface {#IFNAME} ({#IFALIAS}): Administrative status',
  key: 'unifi.snmp.if.admin[{#SNMPINDEX}]',
  oid: '1.3.6.1.2.1.2.2.1.7.{#SNMPINDEX}',
  description: 'IF-MIB ifAdminStatus.',
  item_tags: interface_tags
)

interface_oper = snmp_prototype(
  seed: 'if-oper-status',
  name: 'Interface {#IFNAME} ({#IFALIAS}): Operational status',
  key: 'unifi.snmp.if.oper[{#SNMPINDEX}]',
  oid: '1.3.6.1.2.1.2.2.1.8.{#SNMPINDEX}',
  description: 'IF-MIB ifOperStatus.',
  item_tags: interface_tags,
  triggers: [
    trigger(
      seed: 'trigger-if-down',
      expression: '{$UNIFI.SNMP.IFCONTROL:"{#IFNAME}"}=1 and last(/Template UniFi Site Manager - SNMP Extension/unifi.snmp.if.admin[{#SNMPINDEX}])=1 and last(/Template UniFi Site Manager - SNMP Extension/unifi.snmp.if.oper[{#SNMPINDEX}])=2',
      name: '[Average] UniFi interface {#IFNAME} is down',
      priority: 'AVERAGE',
      description: 'An administratively enabled interface selected by the context macro is operationally down.',
      opdata: '{#IFDESCR}; alias: {#IFALIAS}',
      tags_hash: {'interface' => '{#IFNAME}'}
    )
  ]
)
interface_items << interface_oper

interface_items << snmp_prototype(
  seed: 'if-speed',
  name: 'Interface {#IFNAME} ({#IFALIAS}): Negotiated speed',
  key: 'unifi.snmp.if.speed[{#SNMPINDEX}]',
  oid: '1.3.6.1.2.1.31.1.1.1.15.{#SNMPINDEX}',
  units: 'Mbps',
  description: 'IF-MIB ifHighSpeed, reported in millions of bits per second.',
  item_tags: interface_tags
)

[
  ['if-in-bits', 'Bits received', 'unifi.snmp.if.in.bps', '1.3.6.1.2.1.31.1.1.1.6', 'bps', [
    {'type' => 'CHANGE_PER_SECOND'}, {'type' => 'MULTIPLIER', 'parameters' => ['8']}
  ]],
  ['if-out-bits', 'Bits sent', 'unifi.snmp.if.out.bps', '1.3.6.1.2.1.31.1.1.1.10', 'bps', [
    {'type' => 'CHANGE_PER_SECOND'}, {'type' => 'MULTIPLIER', 'parameters' => ['8']}
  ]],
  ['if-in-errors', 'Inbound errors', 'unifi.snmp.if.in.errors', '1.3.6.1.2.1.2.2.1.14', 'pps', [{'type' => 'CHANGE_PER_SECOND'}]],
  ['if-out-errors', 'Outbound errors', 'unifi.snmp.if.out.errors', '1.3.6.1.2.1.2.2.1.20', 'pps', [{'type' => 'CHANGE_PER_SECOND'}]],
  ['if-in-discards', 'Inbound discards', 'unifi.snmp.if.in.discards', '1.3.6.1.2.1.2.2.1.13', 'pps', [{'type' => 'CHANGE_PER_SECOND'}]],
  ['if-out-discards', 'Outbound discards', 'unifi.snmp.if.out.discards', '1.3.6.1.2.1.2.2.1.19', 'pps', [{'type' => 'CHANGE_PER_SECOND'}]]
].each do |seed, label, key, oid, units, steps|
  interface_items << snmp_prototype(
    seed: seed,
    name: "Interface {#IFNAME} ({#IFALIAS}): #{label}",
    key: "#{key}[{#SNMPINDEX}]",
    oid: "#{oid}.{#SNMPINDEX}",
    units: units,
    description: 'Standard IF-MIB counter converted to a per-second rate.',
    item_tags: interface_tags,
    preprocessing_steps: steps
  )
end

interface_lld = {
  'uuid' => uuid('lld-interfaces'),
  'name' => 'LLD - UniFi interfaces (SNMP extension)',
  'type' => 'SNMP_AGENT',
  'snmp_oid' => 'discovery[{#IFOPERSTATUS},1.3.6.1.2.1.2.2.1.8,{#IFADMINSTATUS},1.3.6.1.2.1.2.2.1.7,{#IFALIAS},1.3.6.1.2.1.31.1.1.1.18,{#IFNAME},1.3.6.1.2.1.31.1.1.1.1,{#IFDESCR},1.3.6.1.2.1.2.2.1.2,{#IFTYPE},1.3.6.1.2.1.2.2.1.3]',
  'key' => 'unifi.snmp.interfaces.discovery',
  'delay' => '{$UNIFI.SNMP.DISCOVERY.INTERVAL}',
  'lifetime_type' => 'DELETE_AFTER',
  'lifetime' => '7d',
  'enabled_lifetime_type' => 'DISABLE_AFTER',
  'enabled_lifetime' => '1d',
  'filter' => {
    'evaltype' => 'AND',
    'conditions' => [
      {'macro' => '{#IFNAME}', 'value' => '{$UNIFI.SNMP.IFNAME.MATCHES}'},
      {'macro' => '{#IFNAME}', 'value' => '{$UNIFI.SNMP.IFNAME.NOT_MATCHES}', 'operator' => 'NOT_MATCHES_REGEX'}
    ]
  },
  'description' => 'Optional local interface telemetry using standard IF-MIB.',
  'item_prototypes' => interface_items
}

radio_tags = tags('Wireless', 'scope' => 'snmp-extension', 'radio' => '{#RADIO.NAME}')
radio_items = []
[
  ['radio-util-total', 'Total channel utilization', 'util.total', '6'],
  ['radio-util-rx', 'Self receive channel utilization', 'util.self.rx', '7'],
  ['radio-util-tx', 'Self transmit channel utilization', 'util.self.tx', '8'],
  ['radio-util-other', 'Other BSS channel utilization', 'util.other-bss', '9']
].each do |seed, label, suffix, column|
  item = snmp_prototype(
    seed: seed,
    name: 'Radio {#RADIO.NAME} ({#RADIO.TYPE}): ' + label,
    key: "unifi.snmp.radio.#{suffix}[{#SNMPINDEX}]",
    oid: "1.3.6.1.4.1.41112.1.6.1.1.1.#{column}.{#SNMPINDEX}",
    units: '%',
    description: 'Ubiquiti UI-MIB radio channel-utilization metric.',
    item_tags: radio_tags
  )
  if suffix == 'util.total'
    item['trigger_prototypes'] = [
      trigger(
        seed: 'trigger-radio-utilization',
        expression: 'avg(/Template UniFi Site Manager - SNMP Extension/unifi.snmp.radio.util.total[{#SNMPINDEX}],10m)>{$UNIFI.SNMP.RADIO.UTIL.WARN}',
        name: '[Average] High WiFi channel utilization on radio {#RADIO.NAME}',
        priority: 'AVERAGE',
        description: 'Total channel utilization remained above the configured threshold.',
        opdata: 'Utilization: {ITEM.LASTVALUE1}',
        tags_hash: {'radio' => '{#RADIO.NAME}'}
      )
    ]
  elsif suffix == 'util.other-bss'
    item['trigger_prototypes'] = [
      trigger(
        seed: 'trigger-radio-interference',
        expression: 'avg(/Template UniFi Site Manager - SNMP Extension/unifi.snmp.radio.util.other-bss[{#SNMPINDEX}],10m)>{$UNIFI.SNMP.RADIO.INTERFERENCE.WARN}',
        name: '[Average] High neighboring-BSS interference on radio {#RADIO.NAME}',
        priority: 'AVERAGE',
        description: 'Other-BSS utilization remained above the configured threshold.',
        opdata: 'Other BSS: {ITEM.LASTVALUE1}',
        tags_hash: {'radio' => '{#RADIO.NAME}'}
      )
    ]
  end
  radio_items << item
end

radio_lld = {
  'uuid' => uuid('lld-radios'),
  'name' => 'LLD - UniFi radios (SNMP extension)',
  'type' => 'SNMP_AGENT',
  'snmp_oid' => 'discovery[{#RADIO.NAME},1.3.6.1.4.1.41112.1.6.1.1.1.2,{#RADIO.TYPE},1.3.6.1.4.1.41112.1.6.1.1.1.3]',
  'key' => 'unifi.snmp.radios.discovery',
  'delay' => '{$UNIFI.SNMP.DISCOVERY.INTERVAL}',
  'lifetime_type' => 'DELETE_AFTER',
  'lifetime' => '7d',
  'enabled_lifetime_type' => 'DISABLE_AFTER',
  'enabled_lifetime' => '1d',
  'description' => 'Ubiquiti-specific radio telemetry that is not available in the official cloud API.',
  'item_prototypes' => radio_items
}

vap_tags = tags('Wireless', 'scope' => 'snmp-extension', 'ssid' => '{#VAP.ESSID}', 'radio' => '{#VAP.RADIO}')
vap_items = []
[
  ['vap-clients', 'Connected stations', 'clients', '8', nil, nil],
  ['vap-ccq', 'Client connection quality', 'ccq', '3', '%', nil],
  ['vap-channel', 'Channel', 'channel', '4', nil, nil],
  ['vap-tx-power', 'Transmit power', 'tx.power', '21', 'dBm', nil],
  ['vap-up', 'Operational state', 'up', '22', nil, 'return Number(value) === 1 ? 1 : 0;']
].each do |seed, label, suffix, column, units, javascript|
  steps = javascript ? preprocessing('JAVASCRIPT', javascript) : []
  item = snmp_prototype(
    seed: seed,
    name: 'SSID {#VAP.ESSID} / {#VAP.RADIO}: ' + label,
    key: "unifi.snmp.vap.#{suffix}[{#SNMPINDEX}]",
    oid: "1.3.6.1.4.1.41112.1.6.1.2.1.#{column}.{#SNMPINDEX}",
    units: units,
    description: 'Ubiquiti UI-MIB virtual access point metric.',
    item_tags: vap_tags,
    preprocessing_steps: steps
  )
  item['valuemap'] = {'name' => 'Boolean'} if suffix == 'up'
  if suffix == 'ccq'
    item['trigger_prototypes'] = [
      trigger(
        seed: 'trigger-vap-ccq',
        expression: 'last(/Template UniFi Site Manager - SNMP Extension/unifi.snmp.vap.clients[{#SNMPINDEX}])>0 and avg(/Template UniFi Site Manager - SNMP Extension/unifi.snmp.vap.ccq[{#SNMPINDEX}],10m)<{$UNIFI.SNMP.CCQ.WARN}',
        name: '[Average] Low WiFi connection quality on SSID {#VAP.ESSID}',
        priority: 'AVERAGE',
        description: 'Average CCQ is below the threshold while stations are connected.',
        opdata: 'CCQ: {ITEM.LASTVALUE1}',
        tags_hash: {'ssid' => '{#VAP.ESSID}'}
      )
    ]
  end
  vap_items << item
end

[
  ['vap-rx-bits', 'Bits received', 'rx.bps', '10', 'bps', [{'type' => 'CHANGE_PER_SECOND'}, {'type' => 'MULTIPLIER', 'parameters' => ['8']}]],
  ['vap-tx-bits', 'Bits sent', 'tx.bps', '16', 'bps', [{'type' => 'CHANGE_PER_SECOND'}, {'type' => 'MULTIPLIER', 'parameters' => ['8']}]],
  ['vap-rx-dropped', 'Receive drops', 'rx.dropped', '12', 'pps', [{'type' => 'CHANGE_PER_SECOND'}]],
  ['vap-rx-errors', 'Receive errors', 'rx.errors', '13', 'pps', [{'type' => 'CHANGE_PER_SECOND'}]],
  ['vap-tx-dropped', 'Transmit drops', 'tx.dropped', '17', 'pps', [{'type' => 'CHANGE_PER_SECOND'}]],
  ['vap-tx-errors', 'Transmit errors', 'tx.errors', '18', 'pps', [{'type' => 'CHANGE_PER_SECOND'}]],
  ['vap-tx-packets', 'Packets sent', 'tx.packets', '19', 'pps', [{'type' => 'CHANGE_PER_SECOND'}]],
  ['vap-tx-retries', 'Transmit retries', 'tx.retries', '20', 'pps', [{'type' => 'CHANGE_PER_SECOND'}]]
].each do |seed, label, suffix, column, units, steps|
  vap_items << snmp_prototype(
    seed: seed,
    name: 'SSID {#VAP.ESSID} / {#VAP.RADIO}: ' + label,
    key: "unifi.snmp.vap.#{suffix}[{#SNMPINDEX}]",
    oid: "1.3.6.1.4.1.41112.1.6.1.2.1.#{column}.{#SNMPINDEX}",
    units: units,
    description: 'Ubiquiti UI-MIB VAP counter converted to a per-second rate.',
    item_tags: vap_tags,
    preprocessing_steps: steps
  )
end

vap_lld = {
  'uuid' => uuid('lld-vaps'),
  'name' => 'LLD - UniFi virtual access points (SNMP extension)',
  'type' => 'SNMP_AGENT',
  'snmp_oid' => 'discovery[{#VAP.ESSID},1.3.6.1.4.1.41112.1.6.1.2.1.6,{#VAP.NAME},1.3.6.1.4.1.41112.1.6.1.2.1.7,{#VAP.RADIO},1.3.6.1.4.1.41112.1.6.1.2.1.9,{#VAP.UP},1.3.6.1.4.1.41112.1.6.1.2.1.22]',
  'key' => 'unifi.snmp.vaps.discovery',
  'delay' => '{$UNIFI.SNMP.DISCOVERY.INTERVAL}',
  'lifetime_type' => 'DELETE_AFTER',
  'lifetime' => '7d',
  'enabled_lifetime_type' => 'DISABLE_AFTER',
  'enabled_lifetime' => '1d',
  'description' => 'Discovers UI-MIB VAPs and adds local SSID/radio telemetry to the API-first project.',
  'item_prototypes' => vap_items
}

macros = [
  {'macro' => '{$UNIFI.SNMP.INTERVAL}', 'value' => '2m', 'description' => 'Optional local SNMP telemetry interval.'},
  {'macro' => '{$UNIFI.SNMP.INVENTORY.INTERVAL}', 'value' => '6h', 'description' => 'Static UI-MIB system information interval.'},
  {'macro' => '{$UNIFI.SNMP.DISCOVERY.INTERVAL}', 'value' => '6h', 'description' => 'Interface, radio and VAP discovery interval.'},
  {'macro' => '{$UNIFI.SNMP.TIMEOUT}', 'value' => '5m', 'description' => 'SNMP-unavailable alarm window.'},
  {'macro' => '{$UNIFI.SNMP.IFNAME.MATCHES}', 'value' => '.*', 'description' => 'Interface names included by discovery.'},
  {'macro' => '{$UNIFI.SNMP.IFNAME.NOT_MATCHES}', 'value' => '^(lo|loopback|sit[0-9]*|ip6tnl[0-9]*)$', 'description' => 'Interface names excluded by discovery.'},
  {'macro' => '{$UNIFI.SNMP.IFCONTROL}', 'value' => '0', 'description' => 'Default interface-down alarm control. Set context macros to 1 only for critical interfaces.'},
  {'macro' => '{$UNIFI.SNMP.RADIO.UTIL.WARN}', 'value' => '80', 'description' => 'High total channel utilization threshold in percent.'},
  {'macro' => '{$UNIFI.SNMP.RADIO.INTERFERENCE.WARN}', 'value' => '70', 'description' => 'High other-BSS utilization threshold in percent.'},
  {'macro' => '{$UNIFI.SNMP.CCQ.WARN}', 'value' => '70', 'description' => 'Low client connection quality threshold in percent.'}
]

valuemaps = [
  {
    'uuid' => uuid('valuemap-boolean'),
    'name' => 'Boolean',
    'mappings' => [
      {'value' => '0', 'newvalue' => 'No'},
      {'value' => '1', 'newvalue' => 'Yes'}
    ]
  },
  {
    'uuid' => uuid('valuemap-zabbix-availability'),
    'name' => 'Zabbix host availability',
    'mappings' => [
      {'value' => '0', 'newvalue' => 'Not available'},
      {'value' => '1', 'newvalue' => 'Available'},
      {'value' => '2', 'newvalue' => 'Unknown'}
    ]
  }
]

template = {
  'uuid' => uuid('template'),
  'template' => TEMPLATE_NAME,
  'name' => TEMPLATE_NAME,
  'description' => <<~DESC,
    PT-BR:
    Extensão opcional do Template UniFi Site Manager. Acrescenta telemetria local de
    interfaces IF-MIB e métricas de rádios/VAPs do UI-MIB. Não substitui o monitoramento
    principal pela API e requer uma interface SNMP alcançável pelo Zabbix Server ou Proxy.
    O UI-MIB oficial não publica discos, SMART ou RAID.

    EN:
    Optional extension for Template UniFi Site Manager. It adds local IF-MIB interface
    telemetry and Ubiquiti UI-MIB radio/VAP metrics. It never replaces API-first monitoring
    and requires a reachable SNMP interface. The official UI-MIB exposes no disk, SMART,
    or RAID objects.
  DESC
  'vendor' => {'name' => 'Daniel Carvalho', 'version' => TEMPLATE_VERSION},
  'groups' => [{'name' => 'Templates/Network devices'}],
  'items' => items,
  'discovery_rules' => [interface_lld, radio_lld, vap_lld],
  'tags' => [
    {'tag' => 'class', 'value' => 'network'},
    {'tag' => 'component', 'value' => 'snmp-extension'},
    {'tag' => 'target', 'value' => 'unifi-device'}
  ],
  'macros' => macros,
  'valuemaps' => valuemaps
}

export = {
  'zabbix_export' => {
    'version' => '7.4',
    'template_groups' => [
      {'uuid' => uuid('template-group-network-devices'), 'name' => 'Templates/Network devices'}
    ],
    'templates' => [template]
  }
}

banner = <<~HEADER
  # PT-BR: Extensão SNMP opcional do projeto UniFi Site Manager para Zabbix 7.4+.
  # EN: Optional UniFi Site Manager SNMP extension for Zabbix 7.4+.
  #
  # Autor / Author: Daniel Carvalho <danielrc10@gmail.com>
  # Repositório / Repository: https://github.com/danielrc10/zabbix-template-unifi-site-manager
  # Licença / License: PolyForm Noncommercial 1.0.0

HEADER

File.write(OUTPUT, banner + YAML.dump(export).sub(/\A---\s*\n/, ''))
puts "Generated #{OUTPUT}"
