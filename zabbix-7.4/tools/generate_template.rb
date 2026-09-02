#!/usr/bin/env ruby

# PT-BR: Gerador determinístico do template UniFi Site Manager para Zabbix 7.4.
# EN: Deterministic generator for the Zabbix 7.4 UniFi Site Manager template.
#
# Autor / Author: Daniel Carvalho <danielrc10@gmail.com>
# LinkedIn: https://www.linkedin.com/in/daniel-ti/
# Licença / License: PolyForm Noncommercial 1.0.0

require 'digest'
require 'yaml'

TEMPLATE_NAME = 'Template UniFi Site Manager by HTTP'
OUTPUT = File.expand_path('../template/template_unifi_site_manager.yaml', __dir__)
SITE_JS_OUTPUT = File.expand_path('../javascript/site_discovery.js', __dir__)

def uuid(seed)
  value = Digest::SHA256.hexdigest("unifi-site-manager/#{seed}")[0, 32]
  value[12] = '4'
  value[16] = '8'
  value
end

def header
  [
    {'name' => 'Accept', 'value' => 'application/json'},
    {'name' => 'X-API-Key', 'value' => '{$UNIFI.API.KEY}'}
  ]
end

def tags(component, extra = {})
  [{'tag' => 'component', 'value' => component}] +
    extra.map { |tag, value| {'tag' => tag, 'value' => value} }
end

def http_item(seed:, name:, key:, url:, delay: '{$UNIFI.INTERVAL}', prototype: false)
  item = {
    'uuid' => uuid(seed),
    'name' => name,
    'type' => 'HTTP_AGENT',
    'key' => key,
    'delay' => delay,
    'history' => '1d',
    'trends' => '0',
    'value_type' => 'TEXT',
    'url' => url,
    'request_method' => 'GET',
    'headers' => header,
    'status_codes' => '200,400-599',
    'follow_redirects' => 'YES',
    'retrieve_mode' => 'BODY',
    'output_format' => 'RAW',
    'timeout' => '{$UNIFI.HTTP.TIMEOUT}',
    'verify_peer' => 'YES',
    'verify_host' => 'YES',
    'tags' => tags('Raw')
  }
  item
end

def dependent_item(seed:, name:, key:, master:, value_type: 'UNSIGNED', units: nil,
                   preprocessing:, item_tags:, triggers: [])
  item = {
    'uuid' => uuid(seed),
    'name' => name,
    'type' => 'DEPENDENT',
    'key' => key,
    'history' => value_type == 'TEXT' || value_type == 'CHAR' ? '30d' : '90d',
    'value_type' => value_type,
    'preprocessing' => preprocessing,
    'master_item' => {'key' => master},
    'tags' => item_tags
  }
  item['trends'] = '365d' unless %w[TEXT CHAR LOG].include?(value_type)
  item['trends'] = '0' if %w[TEXT CHAR LOG].include?(value_type)
  item['units'] = units if units
  item['trigger_prototypes'] = triggers unless triggers.empty?
  item
end

def calculated_source(seed:, name:, key:, formula:, item_tags:)
  {
    'uuid' => uuid(seed),
    'name' => name,
    'type' => 'CALCULATED',
    'key' => key,
    'delay' => '{$UNIFI.INTERVAL}',
    'history' => '1d',
    'trends' => '0',
    'value_type' => 'TEXT',
    'params' => formula,
    'tags' => item_tags
  }
end

def js(code, on_fail: nil)
  step = {'type' => 'JAVASCRIPT', 'parameters' => [code.rstrip + "\n"]}
  if on_fail
    step['error_handler'] = on_fail
    step['error_handler_params'] = ''
  end
  [step]
end

def trigger(seed:, expression:, name:, priority:, description:, opdata: nil, recovery: nil, tags: {})
  trigger = {
    'uuid' => uuid(seed),
    'expression' => expression,
    'name' => name,
    'priority' => priority,
    'description' => description,
    'tags' => [{'tag' => 'scope', 'value' => 'availability'}] +
      tags.map { |tag, value| {'tag' => tag, 'value' => value} }
  }
  trigger['opdata'] = opdata if opdata
  trigger['recovery_expression'] = recovery if recovery
  trigger
end

def lld_rule(seed:, name:, key:, script:, macros:, item_prototypes: [], description:, parameters: nil,
             status: nil, delay: '{$UNIFI.DISCOVERY.INTERVAL}')
  rule = {
    'uuid' => uuid(seed),
    'name' => name,
    'type' => 'SCRIPT',
    'key' => key,
    'delay' => delay,
    'lifetime_type' => 'DELETE_AFTER',
    'lifetime' => '7d',
    'enabled_lifetime_type' => 'DISABLE_AFTER',
    'enabled_lifetime' => '1d',
    'params' => script.rstrip + "\n",
    'description' => description,
    'item_prototypes' => item_prototypes,
    'timeout' => '{$UNIFI.LLD.TIMEOUT}',
    'parameters' => parameters || standard_script_parameters,
    'lld_macro_paths' => macros.map { |macro, path| {'lld_macro' => macro, 'path' => path} }
  }
  rule['status'] = status if status
  rule
end

def standard_script_parameters(extra = [])
  [
    {'name' => 'api_url', 'value' => '{$UNIFI.API.URL}'},
    {'name' => 'token', 'value' => '{$UNIFI.API.KEY}'}
  ] + extra
end

HTTP_HELPERS = <<~'JS'
  var params = JSON.parse(value);
  var apiUrl = String(params.api_url || '').replace(/\/$/, '');
  var token = String(params.token || '');

  if (!/^https:\/\//i.test(apiUrl)) {
      throw 'api_url must use HTTPS.';
  }
  if (token === '' || token === '{$UNIFI.API.KEY}') {
      throw 'Configure {$UNIFI.API.KEY} before running discovery.';
  }

  function requestJson(url, allowMissingApplication) {
      var request = new HttpRequest();
      request.addHeader('Accept: application/json');
      request.addHeader('X-API-Key: ' + token);
      var body = request.get(url);
      var status = request.getStatus();
      var parsed;

      try {
          parsed = JSON.parse(body);
      }
      catch (error) {
          throw 'Invalid JSON from ' + url + ': ' + error;
      }

      if (status !== 200) {
          if (allowMissingApplication && (status === 404 || status === 403 || status === 408)) {
              return null;
          }
          throw 'HTTP ' + status + ' from ' + url + ': ' + String(parsed.message || parsed.code || body);
      }

      return parsed;
  }

  function siteManagerPages(path) {
      var pages = [];
      var nextToken = '';
      var guard = 0;
      do {
          var separator = path.indexOf('?') === -1 ? '?' : '&';
          var url = apiUrl + path + (nextToken ? separator + 'nextToken=' + encodeURIComponent(nextToken) : '');
          var page = requestJson(url, false);
          pages.push(page);
          nextToken = page && page.nextToken ? String(page.nextToken) : '';
          guard++;
      } while (nextToken && guard < 50);
      return pages;
  }

  function siteManagerData(path) {
      var pages = siteManagerPages(path);
      var result = [];
      for (var i = 0; i < pages.length; i++) {
          var rows = pages[i] && Array.isArray(pages[i].data) ? pages[i].data : [];
          result = result.concat(rows);
      }
      return result;
  }

  function connector(hostId, application, path, allowMissingApplication) {
      return requestJson(apiUrl + '/v1/connector/consoles/' + encodeURIComponent(hostId) +
          '/proxy/' + application + '/integration' + path, allowMissingApplication);
  }

  function connectorData(hostId, application, path, allowMissingApplication) {
      var response = connector(hostId, application, path, allowMissingApplication);
      if (response === null) {
          return [];
      }
      if (Array.isArray(response)) {
          return response;
      }
      if (Array.isArray(response.data)) {
          return response.data;
      }
      return [];
  }

  function connectorPaged(hostId, application, path, allowMissingApplication) {
      var result = [];
      var offset = 0;
      var guard = 0;
      while (guard < 100) {
          var separator = path.indexOf('?') === -1 ? '?' : '&';
          var page = connector(hostId, application, path + separator + 'offset=' + offset + '&limit=200', allowMissingApplication);
          if (page === null) {
              return result;
          }
          var rows = Array.isArray(page) ? page : (Array.isArray(page.data) ? page.data : []);
          result = result.concat(rows);
          if (Array.isArray(page) || rows.length === 0 || typeof page.totalCount === 'undefined' || result.length >= Number(page.totalCount)) {
              break;
          }
          offset += rows.length;
          guard++;
      }
      return result;
  }

  function clean(value, fallback) {
      if (value === null || typeof value === 'undefined' || String(value).trim() === '') {
          return fallback;
      }
      return String(value).trim();
  }

  function lower(value) {
      return clean(value, '').toLowerCase();
  }

  function appInstalled(host, application) {
      var controllers = host && host.userData && Array.isArray(host.userData.controllers) ? host.userData.controllers : [];
      if (controllers.length === 0) {
          return true;
      }
      return controllers.indexOf(application) !== -1;
  }
JS

SITE_NORMALIZER = <<~'JS'
  function normalizeSiteManagerPage(page) {
      var output = [];
      var seen = {};

      function add(site, type, fabric) {
          if (!site || typeof site !== 'object') {
              return;
          }
          var meta = site.meta || site.metadata || {};
          var siteId = clean(site.siteId || site.id || meta.id, '');
          var hostId = clean(site.hostId || site.consoleId || meta.hostId, '');
          if (siteId === '') {
              return;
          }
          var key = hostId + '|' + siteId;
          if (seen[key]) {
              return;
          }
          seen[key] = true;
          var fabricId = site.fabricId || meta.fabricId || (fabric && (fabric.id || fabric.fabricId));
          var inferredType = fabricId ? 'Fabric' : (type || site.siteType || meta.siteType || 'Independent');
          output.push({
              siteId: siteId,
              hostId: hostId,
              name: clean(meta.desc || meta.name || site.name, siteId),
              internalReference: clean(meta.name || site.internalReference, ''),
              type: /fabric/i.test(String(inferredType)) ? 'Fabric' : 'Independent',
              fabricId: clean(fabricId, ''),
              raw: site
          });
      }

      var root = page && typeof page === 'object' && page.data ? page.data : page;
      if (Array.isArray(root)) {
          for (var i = 0; i < root.length; i++) add(root[i], 'Independent', null);
          return output;
      }
      root = root || {};
      var independent = root.independentSites || root.independent || root.sites || [];
      for (var j = 0; j < independent.length; j++) add(independent[j], 'Independent', null);
      var fabrics = root.fabrics || root.siteFabrics || [];
      for (var f = 0; f < fabrics.length; f++) {
          var fabricSites = fabrics[f].sites || fabrics[f].members || fabrics[f].siteMemberships || [];
          for (var s = 0; s < fabricSites.length; s++) {
              add(fabricSites[s].site || fabricSites[s], 'Fabric', fabrics[f]);
          }
      }
      return output;
  }
JS

def script(body, normalize_sites: false)
  HTTP_HELPERS + (normalize_sites ? "\n" + SITE_NORMALIZER : '') + "\n" + body
end

account_items = []
account_items << http_item(
  seed: 'item-sm-hosts-raw',
  name: 'UniFi API: Hosts raw data',
  key: 'unifi.sm.hosts.raw',
  url: '{$UNIFI.API.URL}/v1/hosts?pageSize=200'
)
account_items << http_item(
  seed: 'item-sm-sites-raw',
  name: 'UniFi API: Sites raw data',
  key: 'unifi.sm.sites.raw',
  url: '{$UNIFI.API.URL}/v1/sites?pageSize=200'
)
account_items << http_item(
  seed: 'item-sm-devices-raw',
  name: 'UniFi API: Devices raw data',
  key: 'unifi.sm.devices.raw',
  url: '{$UNIFI.API.URL}/v1/devices?pageSize=200'
)
account_items << http_item(
  seed: 'item-sm-isp-raw',
  name: 'UniFi API: ISP metrics raw data',
  key: 'unifi.sm.isp.raw',
  url: '{$UNIFI.API.URL}/v1/isp-metrics/5m?duration=24h',
  delay: '5m'
)

api_health = dependent_item(
  seed: 'item-api-health',
  name: 'UniFi API: Availability',
  key: 'unifi.api.health',
  master: 'unifi.sm.hosts.raw',
  preprocessing: js(<<~'JS'),
    var data = JSON.parse(value);
    return Number(data.httpStatusCode) === 200 && Array.isArray(data.data) ? 1 : 0;
  JS
  item_tags: tags('API')
)
api_health['valuemap'] = {'name' => 'UniFi availability'}
api_health['triggers'] = [
  trigger(
    seed: 'trigger-api-error',
    expression: 'last(/Template UniFi Site Manager by HTTP/unifi.api.health)=0',
    name: '[High] UniFi Site Manager API returned an error',
    priority: 'HIGH',
    description: 'The official Site Manager API returned a non-success response. Check the API key, permissions, rate limit and api.ui.com service status.',
    opdata: 'Availability: {ITEM.LASTVALUE1}',
    tags: {'service' => 'unifi-api'}
  )
]
account_items << api_health

api_http_status = dependent_item(
  seed: 'item-api-http-status',
  name: 'UniFi API: HTTP status',
  key: 'unifi.api.http.status',
  master: 'unifi.sm.hosts.raw',
  preprocessing: js(<<~'JS'),
    var data = JSON.parse(value);
    return Number(data.httpStatusCode || 200);
  JS
  item_tags: tags('API')
)
api_http_status['triggers'] = [
  trigger(
    seed: 'trigger-api-auth',
    expression: 'last(/Template UniFi Site Manager by HTTP/unifi.api.http.status)=401 or last(/Template UniFi Site Manager by HTTP/unifi.api.http.status)=403',
    name: '[High] UniFi API authentication or permission failure',
    priority: 'HIGH',
    description: 'The API key is invalid, revoked, expired or lacks the required access.',
    opdata: 'HTTP status: {ITEM.LASTVALUE1}',
    tags: {'service' => 'unifi-api'}
  ),
  trigger(
    seed: 'trigger-api-rate-limit',
    expression: 'last(/Template UniFi Site Manager by HTTP/unifi.api.http.status)=429',
    name: '[Warning] UniFi API rate limit reached',
    priority: 'WARNING',
    description: 'api.ui.com returned HTTP 429. Increase collection/discovery intervals and respect Retry-After.',
    opdata: 'HTTP status: {ITEM.LASTVALUE1}',
    tags: {'service' => 'unifi-api'}
  )
]
account_items << api_http_status

api_error = dependent_item(
  seed: 'item-api-error',
  name: 'UniFi API: Last error',
  key: 'unifi.api.error',
  master: 'unifi.sm.hosts.raw',
  value_type: 'TEXT',
  preprocessing: js(<<~'JS'),
    var data = JSON.parse(value);
    return String(data.message || data.code || '');
  JS
  item_tags: tags('API')
)
api_error['preprocessing'] << {'type' => 'DISCARD_UNCHANGED_HEARTBEAT', 'parameters' => ['1h']}
account_items << api_error

account_items << dependent_item(
  seed: 'item-host-count',
  name: 'UniFi account: Console/host count',
  key: 'unifi.account.hosts.count',
  master: 'unifi.sm.hosts.raw',
  preprocessing: js(<<~'JS'),
    var data = JSON.parse(value);
    return Array.isArray(data.data) ? data.data.length : 0;
  JS
  item_tags: tags('Inventory')
)

devices_data_age = dependent_item(
  seed: 'item-devices-data-age',
  name: 'UniFi API: Oldest device inventory age',
  key: 'unifi.api.devices.data.age',
  master: 'unifi.sm.devices.raw',
  units: 's',
  preprocessing: js(<<~'JS'),
    var payload = JSON.parse(value);
    if (payload.code || Number(payload.httpStatusCode) >= 400) throw String(payload.message || payload.code);
    var groups = Array.isArray(payload.data) ? payload.data : [];
    var oldest = null;
    for (var i = 0; i < groups.length; i++) {
        if (!groups[i].updatedAt) continue;
        var timestamp = Date.parse(groups[i].updatedAt);
        if (!isNaN(timestamp) && (oldest === null || timestamp < oldest)) oldest = timestamp;
    }
    if (oldest === null) throw 'updatedAt is absent from device inventory.';
    return Math.max(0, Math.floor(((new Date()).getTime() - oldest) / 1000));
  JS
  item_tags: tags('API')
)
devices_data_age['triggers'] = [
  trigger(
    seed: 'trigger-api-stale',
    expression: 'last(/Template UniFi Site Manager by HTTP/unifi.api.devices.data.age)>{$UNIFI.DATA.MAX.AGE}',
    name: '[Average] UniFi device inventory data is stale',
    priority: 'AVERAGE',
    description: 'The oldest host group in /v1/devices has not been refreshed within the configured maximum age.',
    opdata: 'Oldest data age: {ITEM.LASTVALUE1}',
    tags: {'service' => 'unifi-api'}
  )
]
account_items << devices_data_age

account_items << dependent_item(
  seed: 'item-site-count',
  name: 'UniFi account: Site count',
  key: 'unifi.account.sites.count',
  master: 'unifi.sm.sites.raw',
  preprocessing: js(<<~'JS'),
    var data = JSON.parse(value);
    return Array.isArray(data.data) ? data.data.length : 0;
  JS
  item_tags: tags('Inventory')
)

account_items << dependent_item(
  seed: 'item-device-count',
  name: 'UniFi account: Managed device count',
  key: 'unifi.account.devices.count',
  master: 'unifi.sm.devices.raw',
  preprocessing: js(<<~'JS'),
    var data = JSON.parse(value);
    var groups = Array.isArray(data.data) ? data.data : [];
    var total = 0;
    for (var i = 0; i < groups.length; i++) total += Array.isArray(groups[i].devices) ? groups[i].devices.length : 0;
    return total;
  JS
  item_tags: tags('Inventory')
)

account_items.first['triggers'] = [
  trigger(
    seed: 'trigger-api-nodata',
    expression: 'nodata(/Template UniFi Site Manager by HTTP/unifi.sm.hosts.raw,{$UNIFI.API.NODATA})=1',
    name: '[High] No data from UniFi Site Manager API',
    priority: 'HIGH',
    description: 'Zabbix has not received any response body from api.ui.com. Check DNS, routing, proxy, TLS, timeout and the HTTP agent pollers.',
    tags: {'service' => 'unifi-api'}
  )
]

console_item_prototypes = []
console_item_prototypes << dependent_item(
  seed: 'console-cloud-state',
  name: '[{#HOST.NAME}] Console: Cloud connection',
  key: 'unifi.console.cloud.state[{#HOST.ID}]',
  master: 'unifi.sm.hosts.raw',
  preprocessing: js(<<~'JS'),
    var payload = JSON.parse(value);
    var hosts = Array.isArray(payload.data) ? payload.data : [];
    var id = '{#HOST.ID}';
    for (var i = 0; i < hosts.length; i++) {
        if (String(hosts[i].id) !== id) continue;
        if (hosts[i].isBlocked === true) return 0;
        var state = hosts[i].reportedState && hosts[i].reportedState.state;
        if (state) return /connected/i.test(String(state)) ? 1 : 0;
        var members = hosts[i].userData && Array.isArray(hosts[i].userData.consoleGroupMembers) ? hosts[i].userData.consoleGroupMembers : [];
        if (members.length && members[0].roleAttributes) return String(members[0].roleAttributes.connectedState) === 'CONNECTED' ? 1 : 0;
        return 2;
    }
    throw 'Console was not found in /v1/hosts.';
  JS
  item_tags: tags('Console', 'console' => '{#HOST.NAME}'),
  triggers: [
    trigger(
      seed: 'trigger-console-offline',
      expression: 'max(/Template UniFi Site Manager by HTTP/unifi.console.cloud.state[{#HOST.ID}],5m)=0',
      name: '[High] UniFi console {#HOST.NAME} is offline for more than 5 minutes',
      priority: 'HIGH',
      description: 'The console is disconnected from UniFi cloud or remote access is blocked.',
      opdata: 'Host ID: {#HOST.ID}',
      tags: {'console' => '{#HOST.NAME}'}
    )
  ]
)
console_item_prototypes.last['valuemap'] = {'name' => 'UniFi availability'}

console_item_prototypes << dependent_item(
  seed: 'console-blocked',
  name: '[{#HOST.NAME}] Console: Remote access blocked',
  key: 'unifi.console.blocked[{#HOST.ID}]',
  master: 'unifi.sm.hosts.raw',
  preprocessing: js(<<~'JS'),
    var payload = JSON.parse(value);
    var hosts = Array.isArray(payload.data) ? payload.data : [];
    for (var i = 0; i < hosts.length; i++) if (String(hosts[i].id) === '{#HOST.ID}') return hosts[i].isBlocked ? 1 : 0;
    throw 'Console was not found in /v1/hosts.';
  JS
  item_tags: tags('Console', 'console' => '{#HOST.NAME}'),
  triggers: [
    trigger(
      seed: 'trigger-console-blocked',
      expression: 'last(/Template UniFi Site Manager by HTTP/unifi.console.blocked[{#HOST.ID}])=1',
      name: '[High] UniFi console {#HOST.NAME} has cloud access blocked',
      priority: 'HIGH',
      description: 'UniFi reports isBlocked=true. Cloud Connector requests cannot reach this console.',
      tags: {'console' => '{#HOST.NAME}'}
    )
  ]
)
console_item_prototypes.last['valuemap'] = {'name' => 'Boolean'}

console_backup_age = dependent_item(
  seed: 'console-backup-age',
  name: '[{#HOST.NAME}] Console: Latest cloud backup age',
  key: 'unifi.console.backup.age[{#HOST.ID}]',
  master: 'unifi.sm.hosts.raw',
  units: 's',
  preprocessing: js(<<~'JS'),
    var payload = JSON.parse(value);
    var hosts = Array.isArray(payload.data) ? payload.data : [];
    for (var i = 0; i < hosts.length; i++) {
        if (String(hosts[i].id) !== '{#HOST.ID}') continue;
        if (!hosts[i].latestBackupTime) throw 'Latest backup time is not available for this console.';
        var timestamp = Date.parse(hosts[i].latestBackupTime);
        if (isNaN(timestamp)) throw 'Invalid latestBackupTime.';
        return Math.max(0, Math.floor(((new Date()).getTime() - timestamp) / 1000));
    }
    throw 'Console was not found in /v1/hosts.';
  JS
  item_tags: tags('Backup', 'console' => '{#HOST.NAME}'),
  triggers: [
    trigger(
      seed: 'trigger-console-backup-stale',
      expression: 'last(/Template UniFi Site Manager by HTTP/unifi.console.backup.age[{#HOST.ID}])>{$UNIFI.BACKUP.MAX.AGE}',
      name: '[Average] UniFi console {#HOST.NAME} cloud backup is old',
      priority: 'AVERAGE',
      description: 'The latestBackupTime reported by Site Manager is older than the configured maximum.',
      opdata: 'Backup age: {ITEM.LASTVALUE1}',
      tags: {'console' => '{#HOST.NAME}'}
    )
  ]
)
console_item_prototypes << console_backup_age

%w[network protect].each do |application|
  raw = http_item(
    seed: "console-#{application}-raw",
    name: "[{#HOST.NAME}] #{application.capitalize}: API health raw data",
    key: "unifi.console.#{application}.raw[{#HOST.ID}]",
    url: "{$UNIFI.API.URL}/v1/connector/consoles/{#HOST.ID}/proxy/#{application}/integration/v1/#{application == 'network' ? 'info' : 'meta/info'}",
    prototype: true
  )
  raw['tags'] = tags('API', 'application' => application.capitalize, 'console' => '{#HOST.NAME}')
  console_item_prototypes << raw
  health = dependent_item(
    seed: "console-#{application}-health",
    name: "[{#HOST.NAME}] #{application.capitalize}: API availability",
    key: "unifi.console.#{application}.health[{#HOST.ID}]",
    master: "unifi.console.#{application}.raw[{#HOST.ID}]",
    preprocessing: js(<<~'JS'),
      var data = JSON.parse(value);
      if (Number(data.httpStatusCode) >= 400 || data.code || data.message) return 0;
      return 1;
    JS
    item_tags: tags('API', 'application' => application.capitalize, 'console' => '{#HOST.NAME}'),
    triggers: [
      trigger(
        seed: "trigger-console-#{application}-api",
        expression: "last(/Template UniFi Site Manager by HTTP/unifi.console.#{application}.health[{#HOST.ID}])=0 and {#HAS.#{application.upcase}}=1",
        name: "[High] #{application.capitalize} API is unavailable on {#HOST.NAME}",
        priority: 'HIGH',
        description: "Cloud Connector could not access the #{application.capitalize} Integration API on a console that advertises this application.",
        tags: {'console' => '{#HOST.NAME}', 'application' => application.capitalize}
      )
    ]
  )
  health['valuemap'] = {'name' => 'UniFi availability'}
  console_item_prototypes << health
end

console_lld = {
  'uuid' => uuid('lld-consoles'),
  'name' => 'LLD - UniFi consoles',
  'type' => 'DEPENDENT',
  'key' => 'unifi.consoles.discovery',
  'lifetime_type' => 'DELETE_AFTER',
  'lifetime' => '7d',
  'enabled_lifetime_type' => 'DISABLE_AFTER',
  'enabled_lifetime' => '1d',
  'description' => 'Discovers UniFi consoles/hosts and monitors cloud, Network API and Protect API reachability.',
  'item_prototypes' => console_item_prototypes,
  'master_item' => {'key' => 'unifi.sm.hosts.raw'},
  'lld_macro_paths' => [
    {'lld_macro' => '{#HOST.ID}', 'path' => '$.host_id'},
    {'lld_macro' => '{#HOST.NAME}', 'path' => '$.host_name'},
    {'lld_macro' => '{#HOST.TYPE}', 'path' => '$.host_type'},
    {'lld_macro' => '{#HAS.NETWORK}', 'path' => '$.has_network'},
    {'lld_macro' => '{#HAS.PROTECT}', 'path' => '$.has_protect'}
  ],
  'preprocessing' => js(<<~'JS')
    var payload = JSON.parse(value);
    var hosts = Array.isArray(payload.data) ? payload.data : [];
    var output = [];
    for (var i = 0; i < hosts.length; i++) {
        var userData = hosts[i].userData || {};
        var controllers = Array.isArray(userData.controllers) ? userData.controllers : [];
        var reported = hosts[i].reportedState || {};
        output.push({
            host_id: String(hosts[i].id || ''),
            host_name: String(reported.name || reported.hostname || hosts[i].hardwareId || hosts[i].id || 'Unknown console'),
            host_type: String(hosts[i].type || 'console'),
            has_network: controllers.length === 0 || controllers.indexOf('network') !== -1 ? '1' : '0',
            has_protect: controllers.length === 0 || controllers.indexOf('protect') !== -1 ? '1' : '0'
        });
    }
    return JSON.stringify(output);
  JS
}

site_item_prototypes = []

site_raw_endpoints = {
  'devices' => ['/v1/sites/{#NETWORK.SITE.ID}/devices?offset=0&limit=200', 'Devices'],
  'clients' => ['/v1/sites/{#NETWORK.SITE.ID}/clients?offset=0&limit=200', 'Clients'],
  'networks' => ['/v1/sites/{#NETWORK.SITE.ID}/networks?offset=0&limit=200', 'Networks'],
  'wifi' => ['/v1/sites/{#NETWORK.SITE.ID}/wifi/broadcasts?offset=0&limit=200', 'WiFi broadcasts'],
  'wans' => ['/v1/sites/{#NETWORK.SITE.ID}/wans?offset=0&limit=200', 'WAN interfaces'],
  'acl' => ['/v1/sites/{#NETWORK.SITE.ID}/acl-rules?offset=0&limit=200', 'ACL/firewall rules'],
  'vpn' => ['/v1/sites/{#NETWORK.SITE.ID}/vpn/site-to-site-tunnels?offset=0&limit=200', 'Site-to-site VPN tunnels']
}

site_raw_endpoints.each do |slug, (path, label)|
  raw = http_item(
    seed: "site-#{slug}-raw",
    name: "[{#SITE.NAME}] Network: #{label} raw data",
    key: "unifi.site.#{slug}.raw[{#NETWORK.SITE.ID}]",
    url: "{$UNIFI.API.URL}/v1/connector/consoles/{#HOST.ID}/proxy/network/integration#{path}",
    prototype: true
  )
  raw['tags'] = tags('Raw', 'site' => '{#SITE.NAME}', 'application' => 'Network')
  site_item_prototypes << raw
end

%w[devices clients acl].each do |slug|
  truncated = dependent_item(
    seed: "site-#{slug}-truncated",
    name: "[{#SITE.NAME}] Network: #{slug.capitalize} response truncated",
    key: "unifi.site.#{slug}.truncated[{#NETWORK.SITE.ID}]",
    master: "unifi.site.#{slug}.raw[{#NETWORK.SITE.ID}]",
    preprocessing: js(<<~'JS'),
      var payload = JSON.parse(value);
      if (payload.code || Number(payload.httpStatusCode) >= 400) throw String(payload.message || payload.code);
      var returned = Array.isArray(payload.data) ? payload.data.length : 0;
      return typeof payload.totalCount !== 'undefined' && returned < Number(payload.totalCount) ? 1 : 0;
    JS
    item_tags: tags('API', 'site' => '{#SITE.NAME}')
  )
  truncated['valuemap'] = {'name' => 'Boolean'}
  truncated['trigger_prototypes'] = [
    trigger(
      seed: "trigger-site-#{slug}-truncated",
      expression: "last(/Template UniFi Site Manager by HTTP/unifi.site.#{slug}.truncated[{#NETWORK.SITE.ID}])=1",
      name: "[Warning] UniFi #{slug} metrics are truncated on {#SITE.NAME}",
      priority: 'WARNING',
      description: 'The asynchronous master item reached its 200-row page limit. Discovery still paginates, but dependent counts/hashes require collection splitting or a future bulk strategy.',
      tags: {'site' => '{#SITE.NAME}', 'service' => 'unifi-api'}
    )
  ]
  site_item_prototypes << truncated
end

site_health = dependent_item(
  seed: 'site-api-health',
  name: '[{#SITE.NAME}] Network: API availability',
  key: 'unifi.site.api.health[{#NETWORK.SITE.ID}]',
  master: 'unifi.site.devices.raw[{#NETWORK.SITE.ID}]',
  preprocessing: js(<<~'JS'),
    var data = JSON.parse(value);
    if (Number(data.httpStatusCode) >= 400 || data.code || data.message) return 0;
    return Array.isArray(data.data) ? 1 : 0;
  JS
  item_tags: tags('API', 'site' => '{#SITE.NAME}', 'application' => 'Network'),
  triggers: [
    trigger(
      seed: 'trigger-site-api',
      expression: 'last(/Template UniFi Site Manager by HTTP/unifi.site.api.health[{#NETWORK.SITE.ID}])=0',
      name: '[High] Network API is unavailable for site {#SITE.NAME}',
      priority: 'HIGH',
      description: 'The official Network Integration API cannot be reached through Cloud Connector for this site.',
      opdata: 'Console: {#HOST.ID}; Network site: {#NETWORK.SITE.ID}',
      tags: {'site' => '{#SITE.NAME}', 'application' => 'Network'}
    )
  ]
)
site_health['valuemap'] = {'name' => 'UniFi availability'}
site_item_prototypes << site_health

site_online = dependent_item(
  seed: 'site-online',
  name: '[{#SITE.NAME}] Site: Availability',
  key: 'unifi.site.online[{#SITE.ID}]',
  master: 'unifi.sm.sites.raw',
  preprocessing: js(<<~'JS'),
    var payload = JSON.parse(value);
    var sites = Array.isArray(payload.data) ? payload.data : [];
    for (var i = 0; i < sites.length; i++) {
        if (String(sites[i].siteId || sites[i].id) !== '{#SITE.ID}') continue;
        var counts = sites[i].statistics && sites[i].statistics.counts ? sites[i].statistics.counts : {};
        var total = Number(counts.totalDevice || 0);
        var offline = Number(counts.offlineDevice || 0);
        if (total <= 0) return 2;
        return offline >= total ? 0 : 1;
    }
    throw 'Site was not found in /v1/sites.';
  JS
  item_tags: tags('Site', 'site' => '{#SITE.NAME}'),
  triggers: [
    trigger(
      seed: 'trigger-site-offline',
      expression: 'last(/Template UniFi Site Manager by HTTP/unifi.site.online[{#SITE.ID}])=0 and min(/Template UniFi Site Manager by HTTP/unifi.site.online[{#SITE.ID}],5m)=0',
      name: '[High] UniFi site {#SITE.NAME} is offline',
      priority: 'HIGH',
      description: 'All devices reported for this site have been offline for at least five minutes.',
      opdata: 'Site type: {#SITE.TYPE}; Site ID: {#SITE.ID}',
      tags: {'site' => '{#SITE.NAME}'}
    )
  ]
)
site_online['valuemap'] = {'name' => 'UniFi availability'}
site_item_prototypes << site_online

[
  ['totalDevice', 'devices.total', 'Total devices'],
  ['offlineDevice', 'devices.offline', 'Offline devices'],
  ['wifiClient', 'clients.wifi', 'WiFi clients'],
  ['wiredClient', 'clients.wired', 'Wired clients'],
  ['pendingUpdateDevice', 'firmware.pending', 'Devices with firmware update'],
  ['criticalNotification', 'notifications.critical', 'Critical notifications']
].each do |field, suffix, label|
  item = dependent_item(
    seed: "site-count-#{suffix}",
    name: "[{#SITE.NAME}] Site: #{label}",
    key: "unifi.site.#{suffix}[{#SITE.ID}]",
    master: 'unifi.sm.sites.raw',
    preprocessing: js(<<~JS),
      var payload = JSON.parse(value);
      var sites = Array.isArray(payload.data) ? payload.data : [];
      for (var i = 0; i < sites.length; i++) {
          if (String(sites[i].siteId || sites[i].id) === '{#SITE.ID}') {
              var counts = sites[i].statistics && sites[i].statistics.counts ? sites[i].statistics.counts : {};
              return Number(counts.#{field} || 0);
          }
      }
      throw 'Site was not found in /v1/sites.';
    JS
    item_tags: tags('Site', 'site' => '{#SITE.NAME}')
  )
  if field == 'criticalNotification'
    item['trigger_prototypes'] = [
      trigger(
        seed: 'trigger-site-critical-notification',
        expression: 'last(/Template UniFi Site Manager by HTTP/unifi.site.notifications.critical[{#SITE.ID}])>0',
        name: '[Average] UniFi site {#SITE.NAME} has critical notifications',
        priority: 'AVERAGE',
        description: 'Site Manager reports one or more critical notifications for the site.',
        opdata: 'Critical notifications: {ITEM.LASTVALUE1}',
        tags: {'site' => '{#SITE.NAME}'}
      )
    ]
  end
  site_item_prototypes << item
end

firewall_count = dependent_item(
  seed: 'site-firewall-count',
  name: '[{#SITE.NAME}] Security: Active ACL/firewall rules',
  key: 'unifi.site.firewall.active.count[{#NETWORK.SITE.ID}]',
  master: 'unifi.site.acl.raw[{#NETWORK.SITE.ID}]',
  preprocessing: js(<<~'JS'),
    var payload = JSON.parse(value);
    if (payload.code || Number(payload.httpStatusCode) >= 400) throw String(payload.message || payload.code);
    var rows = Array.isArray(payload.data) ? payload.data : [];
    var total = 0;
    for (var i = 0; i < rows.length; i++) if (rows[i].enabled !== false) total++;
    return total;
  JS
  item_tags: tags('Security', 'site' => '{#SITE.NAME}')
)
site_item_prototypes << firewall_count

firewall_hash = dependent_item(
  seed: 'site-firewall-hash',
  name: '[{#SITE.NAME}] Security: Active ACL/firewall rules hash',
  key: 'unifi.site.firewall.hash[{#NETWORK.SITE.ID}]',
  master: 'unifi.site.acl.raw[{#NETWORK.SITE.ID}]',
  value_type: 'CHAR',
  preprocessing: js(<<~'JS'),
    function canonical(value) {
        if (value === null || typeof value !== 'object') return JSON.stringify(value);
        if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
        var keys = Object.keys(value).sort();
        var parts = [];
        for (var i = 0; i < keys.length; i++) {
            if (keys[i] === 'metadata') continue;
            parts.push(JSON.stringify(keys[i]) + ':' + canonical(value[keys[i]]));
        }
        return '{' + parts.join(',') + '}';
    }
    var payload = JSON.parse(value);
    if (payload.code || Number(payload.httpStatusCode) >= 400) throw String(payload.message || payload.code);
    var rows = Array.isArray(payload.data) ? payload.data.filter(function (row) { return row.enabled !== false; }) : [];
    rows.sort(function (a, b) { return String(a.id || '').localeCompare(String(b.id || '')); });
    var text = canonical(rows);
    var hash = 2166136261;
    for (var i = 0; i < text.length; i++) {
        hash ^= text.charCodeAt(i);
        hash = (hash + ((hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24))) >>> 0;
    }
    return ('00000000' + hash.toString(16)).slice(-8);
  JS
  item_tags: tags('Security', 'site' => '{#SITE.NAME}'),
  triggers: [
    trigger(
      seed: 'trigger-firewall-change',
      expression: 'last(/Template UniFi Site Manager by HTTP/unifi.site.firewall.hash[{#NETWORK.SITE.ID}],#1)<>last(/Template UniFi Site Manager by HTTP/unifi.site.firewall.hash[{#NETWORK.SITE.ID}],#2)',
      name: '[Warning] Firewall/ACL rules changed on {#SITE.NAME}',
      priority: 'WARNING',
      description: 'The canonical hash of enabled rules changed. A rule may have been created, edited, reordered, enabled, disabled or deleted. The official Network 10 API exposes ACL rules, not every legacy firewall policy family.',
      opdata: 'Current hash: {ITEM.LASTVALUE1}',
      tags: {'site' => '{#SITE.NAME}', 'scope' => 'security'}
    )
  ]
)
site_item_prototypes << firewall_hash

site_item_prototypes << dependent_item(
  seed: 'site-vpn-count',
  name: '[{#SITE.NAME}] VPN: Site-to-site tunnel count',
  key: 'unifi.site.vpn.tunnels.count[{#NETWORK.SITE.ID}]',
  master: 'unifi.site.vpn.raw[{#NETWORK.SITE.ID}]',
  preprocessing: js(<<~'JS'),
    var payload = JSON.parse(value);
    if (payload.code || Number(payload.httpStatusCode) >= 400) throw String(payload.message || payload.code);
    return Array.isArray(payload.data) ? payload.data.length : 0;
  JS
  item_tags: tags('VPN', 'site' => '{#SITE.NAME}')
)

site_discovery_script = script(<<~'JS', normalize_sites: true)
  var managerPages = siteManagerPages('/v1/sites?pageSize=200');
  var managerSites = [];
  for (var p = 0; p < managerPages.length; p++) managerSites = managerSites.concat(normalizeSiteManagerPage(managerPages[p]));
  var hosts = siteManagerData('/v1/hosts?pageSize=200');
  var output = [];
  var usedManager = {};

  function managerMatch(hostId, localSite) {
      var localNames = [lower(localSite.name), lower(localSite.internalReference)];
      var candidates = [];
      for (var i = 0; i < managerSites.length; i++) {
          if (managerSites[i].hostId !== hostId) continue;
          candidates.push(managerSites[i]);
          if (localNames.indexOf(lower(managerSites[i].name)) !== -1 ||
              localNames.indexOf(lower(managerSites[i].internalReference)) !== -1) return managerSites[i];
      }
      return candidates.length === 1 ? candidates[0] : null;
  }

  for (var h = 0; h < hosts.length; h++) {
      if (!appInstalled(hosts[h], 'network')) continue;
      var localSites = connectorPaged(hosts[h].id, 'network', '/v1/sites', true);
      for (var s = 0; s < localSites.length; s++) {
          var match = managerMatch(String(hosts[h].id), localSites[s]);
          if (match) usedManager[match.hostId + '|' + match.siteId] = true;
          output.push({
              site_id: match ? match.siteId : clean(localSites[s].id, ''),
              network_site_id: clean(localSites[s].id, ''),
              site_name: clean(localSites[s].name, match ? match.name : clean(localSites[s].id, 'Unknown site')),
              site_type: match ? match.type : 'Independent',
              fabric_id: match ? match.fabricId : '',
              host_id: String(hosts[h].id)
          });
      }
  }

  for (var m = 0; m < managerSites.length; m++) {
      var managerKey = managerSites[m].hostId + '|' + managerSites[m].siteId;
      if (usedManager[managerKey]) continue;
      output.push({
          site_id: managerSites[m].siteId,
          network_site_id: managerSites[m].siteId,
          site_name: managerSites[m].name,
          site_type: managerSites[m].type,
          fabric_id: managerSites[m].fabricId,
          host_id: managerSites[m].hostId
      });
  }

  return JSON.stringify(output);
JS

sites_lld = lld_rule(
  seed: 'lld-sites',
  name: 'LLD - Sites (Independent + Fabric)',
  key: 'unifi.sites.discovery',
  script: site_discovery_script,
  macros: {
    '{#SITE.ID}' => '$.site_id',
    '{#SITE.NAME}' => '$.site_name',
    '{#SITE.TYPE}' => '$.site_type',
    '{#FABRIC.ID}' => '$.fabric_id',
    '{#HOST.ID}' => '$.host_id',
    '{#NETWORK.SITE.ID}' => '$.network_site_id'
  },
  item_prototypes: site_item_prototypes,
  description: <<~DESC
    Discovers Network sites through the official Cloud Connector and correlates them with /v1/sites.
    The JavaScript normalizer accepts the current flat Site Manager response plus nested independentSites/fabrics
    shapes for forward compatibility. The current public v1 contract does not expose Fabric membership, so
    SITE.TYPE remains Independent unless a fabric identifier is actually present in the API payload.
  DESC
)

device_item_prototypes = []
device_detail_raw = http_item(
  seed: 'device-detail-raw',
  name: '[{#DEVICE.NAME}] Device: Details raw data',
  key: 'unifi.device.detail.raw[{#DEVICE.ID},{#SITE.ID}]',
  url: '{$UNIFI.API.URL}/v1/connector/consoles/{#HOST.ID}/proxy/network/integration/v1/sites/{#SITE.ID}/devices/{#DEVICE.ID}',
  prototype: true
)
device_detail_raw['tags'] = tags('Raw', 'device' => '{#DEVICE.NAME}', 'site' => '{#SITE.NAME}')
device_item_prototypes << device_detail_raw

device_stats_raw = http_item(
  seed: 'device-stats-raw',
  name: '[{#DEVICE.NAME}] Device: Latest statistics raw data',
  key: 'unifi.device.stats.raw[{#DEVICE.ID},{#SITE.ID}]',
  url: '{$UNIFI.API.URL}/v1/connector/consoles/{#HOST.ID}/proxy/network/integration/v1/sites/{#SITE.ID}/devices/{#DEVICE.ID}/statistics/latest',
  prototype: true
)
device_stats_raw['tags'] = tags('Raw', 'device' => '{#DEVICE.NAME}', 'site' => '{#SITE.NAME}')
device_item_prototypes << device_stats_raw

device_clients_source = calculated_source(
  seed: 'device-clients-source',
  name: '[{#DEVICE.NAME}] Device/AP: Connected clients source',
  key: 'unifi.device.clients.source[{#DEVICE.ID},{#SITE.ID}]',
  formula: 'last(//unifi.site.clients.raw[{#SITE.ID}])',
  item_tags: tags('Raw', 'device' => '{#DEVICE.NAME}', 'site' => '{#SITE.NAME}')
)
device_item_prototypes << device_clients_source

device_item_prototypes << dependent_item(
  seed: 'device-clients',
  name: '[{#DEVICE.NAME}] Device/AP: Connected client count',
  key: 'unifi.device.clients[{#DEVICE.ID},{#SITE.ID}]',
  master: 'unifi.device.clients.source[{#DEVICE.ID},{#SITE.ID}]',
  preprocessing: js(<<~'JS'),
    var payload = JSON.parse(value);
    if (payload.code || Number(payload.httpStatusCode) >= 400) throw String(payload.message || payload.code);
    var clients = Array.isArray(payload.data) ? payload.data : [];
    var count = 0;
    for (var i = 0; i < clients.length; i++) if (String(clients[i].uplinkDeviceId) === '{#DEVICE.ID}') count++;
    return count;
  JS
  item_tags: tags('Clients', 'device' => '{#DEVICE.NAME}', 'site' => '{#SITE.NAME}')
)

device_online = dependent_item(
  seed: 'device-online',
  name: '[{#DEVICE.NAME}] Device: Availability',
  key: 'unifi.device.online[{#DEVICE.MAC}]',
  master: 'unifi.device.detail.raw[{#DEVICE.ID},{#SITE.ID}]',
  preprocessing: js(<<~'JS'),
    var data = JSON.parse(value);
    if (data.code || Number(data.httpStatusCode) >= 400) throw String(data.message || data.code);
    return String(data.state || '').toUpperCase() === 'ONLINE' ? 1 : 0;
  JS
  item_tags: tags('Device', 'device' => '{#DEVICE.NAME}', 'site' => '{#SITE.NAME}'),
  triggers: [
    trigger(
      seed: 'trigger-device-offline',
      expression: 'last(/Template UniFi Site Manager by HTTP/unifi.device.online[{#DEVICE.MAC}])=0 and max(/Template UniFi Site Manager by HTTP/unifi.device.online[{#DEVICE.MAC}],5m)=0',
      name: '[High] UniFi device {#DEVICE.NAME} is offline for more than 5 minutes',
      priority: 'HIGH',
      description: 'The adopted Network device has remained outside ONLINE state for at least five minutes.',
      opdata: '{#DEVICE.MODEL} / {#DEVICE.MAC} / site {#SITE.NAME}',
      tags: {'device' => '{#DEVICE.NAME}', 'site' => '{#SITE.NAME}'}
    )
  ]
)
device_online['valuemap'] = {'name' => 'UniFi availability'}
device_item_prototypes << device_online

[
  ['uptimeSec', 'uptime', 'Uptime', 'UNSIGNED', 'uptime'],
  ['cpuUtilizationPct', 'cpu', 'CPU utilization', 'FLOAT', '%'],
  ['memoryUtilizationPct', 'memory', 'Memory utilization', 'FLOAT', '%']
].each do |field, suffix, label, value_type, units|
  item = dependent_item(
    seed: "device-#{suffix}",
    name: "[{#DEVICE.NAME}] Device: #{label}",
    key: "unifi.device.#{suffix}[{#DEVICE.MAC}]",
    master: 'unifi.device.stats.raw[{#DEVICE.ID},{#SITE.ID}]',
    value_type: value_type,
    units: units,
    preprocessing: js(<<~JS),
      var data = JSON.parse(value);
      if (data.code || Number(data.httpStatusCode) >= 400) throw String(data.message || data.code);
      if (typeof data.#{field} === 'undefined' || data.#{field} === null) throw '#{field} is not exposed for this device.';
      return Number(data.#{field});
    JS
    item_tags: tags('Device', 'device' => '{#DEVICE.NAME}', 'site' => '{#SITE.NAME}')
  )
  if suffix == 'uptime'
    item['trigger_prototypes'] = [
      trigger(
        seed: 'trigger-device-reboot',
        expression: 'last(/Template UniFi Site Manager by HTTP/unifi.device.uptime[{#DEVICE.MAC}])<10m and change(/Template UniFi Site Manager by HTTP/unifi.device.uptime[{#DEVICE.MAC}])<0',
        name: '[High] Unexpected reboot detected on {#DEVICE.NAME}',
        priority: 'HIGH',
        description: 'Device uptime dropped and is below ten minutes.',
        opdata: 'Uptime: {ITEM.LASTVALUE1}',
        tags: {'device' => '{#DEVICE.NAME}', 'site' => '{#SITE.NAME}'}
      )
    ]
  end
  device_item_prototypes << item
end

device_temperature = dependent_item(
  seed: 'device-temperature',
  name: '[{#DEVICE.NAME}] Device: Temperature (when exposed)',
  key: 'unifi.device.temperature[{#DEVICE.MAC}]',
  master: 'unifi.device.stats.raw[{#DEVICE.ID},{#SITE.ID}]',
  value_type: 'FLOAT',
  units: '°C',
  preprocessing: js(<<~'JS'),
    var data = JSON.parse(value);
    if (data.code || Number(data.httpStatusCode) >= 400) throw String(data.message || data.code);
    var candidates = [data.temperatureC, data.temperature, data.systemStats && data.systemStats.temperatureC];
    for (var i = 0; i < candidates.length; i++) if (candidates[i] !== null && typeof candidates[i] !== 'undefined') return Number(candidates[i]);
    throw 'Temperature is not exposed by the official Network schema for this device.';
  JS
  item_tags: tags('Device', 'device' => '{#DEVICE.NAME}', 'site' => '{#SITE.NAME}'),
  triggers: [
    trigger(
      seed: 'trigger-device-temperature',
      expression: 'last(/Template UniFi Site Manager by HTTP/unifi.device.temperature[{#DEVICE.MAC}])>{$TEMP.MAX.WARN}',
      name: '[Average] High temperature on UniFi device {#DEVICE.NAME}',
      priority: 'AVERAGE',
      description: 'The device-reported temperature exceeded the configured maximum.',
      opdata: 'Temperature: {ITEM.LASTVALUE1}; limit: {$TEMP.MAX.WARN}°C',
      tags: {'device' => '{#DEVICE.NAME}', 'site' => '{#SITE.NAME}'}
    )
  ]
)
device_item_prototypes << device_temperature

firmware = dependent_item(
  seed: 'device-firmware-update',
  name: '[{#DEVICE.NAME}] Device: Firmware update available',
  key: 'unifi.device.firmware.updatable[{#DEVICE.MAC}]',
  master: 'unifi.device.detail.raw[{#DEVICE.ID},{#SITE.ID}]',
  preprocessing: js(<<~'JS'),
    var data = JSON.parse(value);
    if (data.code || Number(data.httpStatusCode) >= 400) throw String(data.message || data.code);
    return data.firmwareUpdatable === true ? 1 : 0;
  JS
  item_tags: tags('Firmware', 'device' => '{#DEVICE.NAME}', 'site' => '{#SITE.NAME}'),
  triggers: [
    trigger(
      seed: 'trigger-device-firmware',
      expression: 'last(/Template UniFi Site Manager by HTTP/unifi.device.firmware.updatable[{#DEVICE.MAC}])=1',
      name: '[Information] Firmware update available for {#DEVICE.NAME}',
      priority: 'INFO',
      description: 'The official Network API reports firmwareUpdatable=true.',
      tags: {'device' => '{#DEVICE.NAME}', 'site' => '{#SITE.NAME}'}
    )
  ]
)
firmware['valuemap'] = {'name' => 'Boolean'}
device_item_prototypes << firmware

rps = dependent_item(
  seed: 'device-rps',
  name: '[{#DEVICE.NAME}] Device: Redundant power state (when exposed)',
  key: 'unifi.device.rps.ok[{#DEVICE.MAC}]',
  master: 'unifi.device.detail.raw[{#DEVICE.ID},{#SITE.ID}]',
  preprocessing: js(<<~'JS'),
    var data = JSON.parse(value);
    var power = data.redundantPower || data.rps || data.uspRps;
    if (!power) throw 'USP-RPS state is not exposed by the official Network schema for this device.';
    var state = String(power.state || power.status || power).toUpperCase();
    return /OK|ONLINE|CONNECTED|ACTIVE/.test(state) ? 1 : 0;
  JS
  item_tags: tags('Power', 'device' => '{#DEVICE.NAME}', 'site' => '{#SITE.NAME}')
)
rps['valuemap'] = {'name' => 'UniFi availability'}
device_item_prototypes << rps

device_discovery_script = script(<<~'JS')
  var hosts = siteManagerData('/v1/hosts?pageSize=200');
  var output = [];
  for (var h = 0; h < hosts.length; h++) {
      if (!appInstalled(hosts[h], 'network')) continue;
      var sites = connectorPaged(hosts[h].id, 'network', '/v1/sites', true);
      for (var s = 0; s < sites.length; s++) {
          var devices = connectorPaged(hosts[h].id, 'network', '/v1/sites/' + encodeURIComponent(sites[s].id) + '/devices', true);
          for (var d = 0; d < devices.length; d++) {
              output.push({
                  device_id: clean(devices[d].id, ''),
                  device_mac: clean(devices[d].macAddress, clean(devices[d].id, 'unknown')),
                  device_name: clean(devices[d].name, clean(devices[d].macAddress, 'Unknown device')),
                  device_model: clean(devices[d].model, 'Unknown'),
                  device_site_id: clean(sites[s].id, ''),
                  site_id: clean(sites[s].id, ''),
                  site_name: clean(sites[s].name, clean(sites[s].id, 'Unknown site')),
                  host_id: String(hosts[h].id),
                  features: Array.isArray(devices[d].features) ? devices[d].features.join(',') : ''
              });
          }
      }
  }
  return JSON.stringify(output);
JS

devices_lld = lld_rule(
  seed: 'lld-network-devices',
  name: 'LLD - Network devices (Gateways, Switches and APs)',
  key: 'unifi.network.devices.discovery',
  script: device_discovery_script,
  macros: {
    '{#DEVICE.ID}' => '$.device_id',
    '{#DEVICE.MAC}' => '$.device_mac',
    '{#DEVICE.NAME}' => '$.device_name',
    '{#DEVICE.MODEL}' => '$.device_model',
    '{#DEVICE.SITE.ID}' => '$.device_site_id',
    '{#SITE.ID}' => '$.site_id',
    '{#SITE.NAME}' => '$.site_name',
    '{#HOST.ID}' => '$.host_id',
    '{#DEVICE.FEATURES}' => '$.features'
  },
  item_prototypes: device_item_prototypes,
  description: 'Discovers adopted gateways, switches and access points through the official Network Integration API.'
)

port_item_prototypes = []
port_source = calculated_source(
  seed: 'port-source',
  name: '[{#SWITCH.NAME} / {#PORT.NAME}] Port: Device details source',
  key: 'unifi.port.source[{#SWITCH.MAC},{#PORT.NUM}]',
  formula: 'last(//unifi.device.detail.raw[{#DEVICE.ID},{#SITE.ID}])',
  item_tags: tags('Raw', 'device' => '{#SWITCH.NAME}', 'port' => '{#PORT.NAME}', 'site' => '{#SITE.NAME}')
)
port_item_prototypes << port_source

port_lookup_prefix = <<~'JS'
  var data = JSON.parse(value);
  if (data.code || Number(data.httpStatusCode) >= 400) throw String(data.message || data.code);
  var ports = data.interfaces && Array.isArray(data.interfaces.ports) ? data.interfaces.ports : [];
  var port = null;
  for (var i = 0; i < ports.length; i++) if (Number(ports[i].idx) === Number('{#PORT.NUM}')) { port = ports[i]; break; }
  if (!port) throw 'Port was not found in device details.';
JS

port_link = dependent_item(
  seed: 'port-link',
  name: '[{#SWITCH.NAME} / {#PORT.NAME}] Port: Link status',
  key: 'unifi.port.link[{#SWITCH.MAC},{#PORT.NUM}]',
  master: 'unifi.port.source[{#SWITCH.MAC},{#PORT.NUM}]',
  preprocessing: js(port_lookup_prefix + <<~'JS'),
    return String(port.state || 'UNKNOWN').toUpperCase() === 'UP' ? 1 : 0;
  JS
  item_tags: tags('Port', 'device' => '{#SWITCH.NAME}', 'port' => '{#PORT.NAME}', 'site' => '{#SITE.NAME}')
)
port_link['valuemap'] = {'name' => 'UniFi availability'}
port_item_prototypes << port_link

[
  ['speedMbps', 'speed', 'Operating speed', 'Mbps'],
  ['maxSpeedMbps', 'maxspeed', 'Maximum speed', 'Mbps']
].each do |field, suffix, label, units|
  item = dependent_item(
    seed: "port-#{suffix}",
    name: "[{#SWITCH.NAME} / {#PORT.NAME}] Port: #{label}",
    key: "unifi.port.#{suffix}[{#SWITCH.MAC},{#PORT.NUM}]",
    master: 'unifi.port.source[{#SWITCH.MAC},{#PORT.NUM}]',
    units: units,
    preprocessing: js(port_lookup_prefix + <<~JS),
      if (typeof port.#{field} === 'undefined') return 0;
      return Number(port.#{field});
    JS
    item_tags: tags('Port', 'device' => '{#SWITCH.NAME}', 'port' => '{#PORT.NAME}', 'site' => '{#SITE.NAME}')
  )
  if suffix == 'speed'
    item['trigger_prototypes'] = [
      trigger(
        seed: 'trigger-port-speed-degraded',
        expression: 'last(/Template UniFi Site Manager by HTTP/unifi.port.speed[{#SWITCH.MAC},{#PORT.NUM}])>0 and last(/Template UniFi Site Manager by HTTP/unifi.port.speed[{#SWITCH.MAC},{#PORT.NUM}])<last(/Template UniFi Site Manager by HTTP/unifi.port.speed[{#SWITCH.MAC},{#PORT.NUM}],#2)',
        name: '[Average] Link speed degraded on {#SWITCH.NAME} / {#PORT.NAME}',
        priority: 'AVERAGE',
        description: 'The negotiated link speed dropped while the port remains up.',
        opdata: 'Current: {ITEM.LASTVALUE1}',
        tags: {'device' => '{#SWITCH.NAME}', 'port' => '{#PORT.NAME}', 'site' => '{#SITE.NAME}'}
      )
    ]
  end
  port_item_prototypes << item
end

port_vlan = dependent_item(
  seed: 'port-vlan',
  name: '[{#SWITCH.NAME} / {#PORT.NAME}] Port: Operational VLAN (when exposed)',
  key: 'unifi.port.vlan[{#SWITCH.MAC},{#PORT.NUM}]',
  master: 'unifi.port.source[{#SWITCH.MAC},{#PORT.NUM}]',
  preprocessing: js(port_lookup_prefix + <<~'JS'),
    var vlan = port.vlanId;
    if (typeof vlan === 'undefined' && port.nativeNetwork) vlan = port.nativeNetwork.vlanId;
    if (typeof vlan === 'undefined') throw 'Operational VLAN is not exposed by the official port schema.';
    return Number(vlan);
  JS
  item_tags: tags('Port', 'device' => '{#SWITCH.NAME}', 'port' => '{#PORT.NAME}', 'site' => '{#SITE.NAME}'),
  triggers: [
    trigger(
      seed: 'trigger-port-vlan-change',
      expression: 'change(/Template UniFi Site Manager by HTTP/unifi.port.vlan[{#SWITCH.MAC},{#PORT.NUM}])<>0',
      name: '[Warning] VLAN changed on {#SWITCH.NAME} / {#PORT.NAME}',
      priority: 'WARNING',
      description: 'The operational/native VLAN value changed. This item is collected only when a future/extended official response exposes the field.',
      opdata: 'VLAN: {ITEM.LASTVALUE1}',
      tags: {'device' => '{#SWITCH.NAME}', 'port' => '{#PORT.NAME}', 'site' => '{#SITE.NAME}'}
    )
  ]
)
port_item_prototypes << port_vlan

port_poe_state = dependent_item(
  seed: 'port-poe-state',
  name: '[{#SWITCH.NAME} / {#PORT.NAME}] Port: PoE state',
  key: 'unifi.port.poe.state[{#SWITCH.MAC},{#PORT.NUM}]',
  master: 'unifi.port.source[{#SWITCH.MAC},{#PORT.NUM}]',
  value_type: 'CHAR',
  preprocessing: js(port_lookup_prefix + <<~'JS'),
    if (!port.poe) throw 'Port has no PoE capability.';
    return String(port.poe.state || 'UNKNOWN');
  JS
  item_tags: tags('PoE', 'device' => '{#SWITCH.NAME}', 'port' => '{#PORT.NAME}', 'site' => '{#SITE.NAME}')
)
port_item_prototypes << port_poe_state

port_poe_power = dependent_item(
  seed: 'port-poe-power',
  name: '[{#SWITCH.NAME} / {#PORT.NAME}] Port: PoE power (when exposed)',
  key: 'unifi.port.poe.watts[{#SWITCH.MAC},{#PORT.NUM}]',
  master: 'unifi.port.source[{#SWITCH.MAC},{#PORT.NUM}]',
  value_type: 'FLOAT',
  units: 'W',
  preprocessing: js(port_lookup_prefix + <<~'JS'),
    if (!port.poe) throw 'Port has no PoE capability.';
    var power = port.poe.powerWatts;
    if (typeof power === 'undefined') power = port.poe.powerConsumptionWatts;
    if (typeof power === 'undefined') throw 'PoE watts are not exposed by the official port schema.';
    return Number(power);
  JS
  item_tags: tags('PoE', 'device' => '{#SWITCH.NAME}', 'port' => '{#PORT.NAME}', 'site' => '{#SITE.NAME}')
)
port_item_prototypes << port_poe_power

ports_discovery_script = script(<<~'JS')
  var hosts = siteManagerData('/v1/hosts?pageSize=200');
  var output = [];
  for (var h = 0; h < hosts.length; h++) {
      if (!appInstalled(hosts[h], 'network')) continue;
      var sites = connectorPaged(hosts[h].id, 'network', '/v1/sites', true);
      for (var s = 0; s < sites.length; s++) {
          var devices = connectorPaged(hosts[h].id, 'network', '/v1/sites/' + encodeURIComponent(sites[s].id) + '/devices', true);
          for (var d = 0; d < devices.length; d++) {
              if (!Array.isArray(devices[d].interfaces) || devices[d].interfaces.indexOf('ports') === -1) continue;
              var detail = connector(hosts[h].id, 'network', '/v1/sites/' + encodeURIComponent(sites[s].id) + '/devices/' + encodeURIComponent(devices[d].id), true);
              var ports = detail && detail.interfaces && Array.isArray(detail.interfaces.ports) ? detail.interfaces.ports : [];
              for (var p = 0; p < ports.length; p++) {
                  output.push({
                      switch_mac: clean(devices[d].macAddress, devices[d].id),
                      switch_name: clean(devices[d].name, clean(devices[d].macAddress, 'Switch')),
                      device_id: clean(devices[d].id, ''),
                      port_num: String(ports[p].idx),
                      port_name: clean(ports[p].name, 'Port ' + ports[p].idx),
                      site_id: clean(sites[s].id, ''),
                      site_name: clean(sites[s].name, sites[s].id),
                      host_id: String(hosts[h].id)
                  });
              }
          }
      }
  }
  return JSON.stringify(output);
JS

ports_lld = lld_rule(
  seed: 'lld-switch-ports',
  name: 'LLD - Switch ports',
  key: 'unifi.switch.ports.discovery',
  script: ports_discovery_script,
  macros: {
    '{#SWITCH.MAC}' => '$.switch_mac',
    '{#SWITCH.NAME}' => '$.switch_name',
    '{#DEVICE.ID}' => '$.device_id',
    '{#PORT.NUM}' => '$.port_num',
    '{#PORT.NAME}' => '$.port_name',
    '{#SITE.ID}' => '$.site_id',
    '{#SITE.NAME}' => '$.site_name',
    '{#HOST.ID}' => '$.host_id'
  },
  item_prototypes: port_item_prototypes,
  description: 'Discovers physical switch ports. Name falls back to Port N because the current official schema exposes idx, link, connector, speed and PoE state but not the configured port name.'
)

camera_item_prototypes = []
camera_raw = http_item(
  seed: 'camera-raw',
  name: '[{#CAMERA.NAME}] Protect: Camera raw data',
  key: 'unifi.camera.raw[{#HOST.ID},{#CAMERA.ID}]',
  url: '{$UNIFI.API.URL}/v1/connector/consoles/{#HOST.ID}/proxy/protect/integration/v1/cameras/{#CAMERA.ID}',
  prototype: true
)
camera_raw['tags'] = tags('Raw', 'camera' => '{#CAMERA.NAME}', 'application' => 'Protect', 'site' => '{#CAMERA.SITE.ID}')
camera_item_prototypes << camera_raw

camera_online = dependent_item(
  seed: 'camera-online',
  name: '[{#CAMERA.NAME}] Protect: Camera connection/video availability',
  key: 'unifi.camera.online[{#CAMERA.ID}]',
  master: 'unifi.camera.raw[{#HOST.ID},{#CAMERA.ID}]',
  preprocessing: js(<<~'JS'),
    var data = JSON.parse(value);
    if (data.code || Number(data.httpStatusCode) >= 400) throw String(data.message || data.code);
    var state = String(data.state || '').toUpperCase();
    if (data.isVideoReady === false || /LOST|FAILED|OFFLINE/.test(String(data.streamState || '').toUpperCase())) return 0;
    return state === 'CONNECTED' ? 1 : 0;
  JS
  item_tags: tags('Camera', 'camera' => '{#CAMERA.NAME}', 'application' => 'Protect', 'site' => '{#CAMERA.SITE.ID}'),
  triggers: [
    trigger(
      seed: 'trigger-camera-offline',
      expression: 'last(/Template UniFi Site Manager by HTTP/unifi.camera.online[{#CAMERA.ID}])=0',
      name: '[Disaster] Security camera {#CAMERA.NAME} is disconnected or has no video',
      priority: 'DISASTER',
      description: 'Protect reports the camera disconnected. If a compatible official response exposes isVideoReady/streamState, explicit stream loss is also detected.',
      opdata: '{#CAMERA.MODEL} / camera ID {#CAMERA.ID}',
      tags: {'camera' => '{#CAMERA.NAME}', 'application' => 'Protect'}
    )
  ]
)
camera_online['valuemap'] = {'name' => 'UniFi availability'}
camera_item_prototypes << camera_online

camera_enabled = dependent_item(
  seed: 'camera-enabled',
  name: '[{#CAMERA.NAME}] Protect: Camera enabled',
  key: 'unifi.camera.enabled[{#CAMERA.ID}]',
  master: 'unifi.camera.raw[{#HOST.ID},{#CAMERA.ID}]',
  preprocessing: js(<<~'JS'),
    var data = JSON.parse(value);
    if (data.code || Number(data.httpStatusCode) >= 400) throw String(data.message || data.code);
    if (typeof data.isEnabled !== 'undefined') return data.isEnabled ? 1 : 0;
    return 1;
  JS
  item_tags: tags('Camera', 'camera' => '{#CAMERA.NAME}', 'application' => 'Protect')
)
camera_enabled['valuemap'] = {'name' => 'Boolean'}
camera_item_prototypes << camera_enabled

camera_recording = dependent_item(
  seed: 'camera-recording',
  name: '[{#CAMERA.NAME}] Protect: Recording active (when exposed)',
  key: 'unifi.camera.recording.active[{#CAMERA.ID}]',
  master: 'unifi.camera.raw[{#HOST.ID},{#CAMERA.ID}]',
  preprocessing: js(<<~'JS'),
    var data = JSON.parse(value);
    if (data.code || Number(data.httpStatusCode) >= 400) throw String(data.message || data.code);
    if (typeof data.isRecording !== 'undefined') return data.isRecording ? 1 : 0;
    var state = data.recordingState || (data.recording && data.recording.state);
    if (typeof state === 'undefined') throw 'Active recording state is not exposed by the current official Protect Integration API.';
    return /RECORDING|ACTIVE|ON/i.test(String(state)) ? 1 : 0;
  JS
  item_tags: tags('Recording', 'camera' => '{#CAMERA.NAME}', 'application' => 'Protect'),
  triggers: [
    trigger(
      seed: 'trigger-camera-not-recording',
      expression: 'last(/Template UniFi Site Manager by HTTP/unifi.camera.enabled[{#CAMERA.ID}])=1 and last(/Template UniFi Site Manager by HTTP/unifi.camera.recording.active[{#CAMERA.ID}])=0',
      name: '[Disaster] Camera {#CAMERA.NAME} is enabled but not recording',
      priority: 'DISASTER',
      description: 'The trigger becomes operational only when the official Protect response provides an active-recording field. No value is fabricated when the field is absent.',
      tags: {'camera' => '{#CAMERA.NAME}', 'application' => 'Protect'}
    )
  ]
)
camera_recording['valuemap'] = {'name' => 'Boolean'}
camera_item_prototypes << camera_recording

camera_mode = dependent_item(
  seed: 'camera-recording-mode',
  name: '[{#CAMERA.NAME}] Protect: Recording mode (when exposed)',
  key: 'unifi.camera.recording.mode[{#CAMERA.ID}]',
  master: 'unifi.camera.raw[{#HOST.ID},{#CAMERA.ID}]',
  value_type: 'CHAR',
  preprocessing: js(<<~'JS'),
    var data = JSON.parse(value);
    var mode = data.recordingMode || (data.recordingSettings && data.recordingSettings.mode) || (data.recording && data.recording.mode);
    if (typeof mode === 'undefined') throw 'Recording mode is not exposed by the current official Protect Integration API.';
    var normalized = String(mode).toUpperCase();
    if (/ALWAYS|CONTINUOUS/.test(normalized)) return 'Continuous';
    if (/SMART/.test(normalized)) return 'Smart Detections';
    if (/MOTION|DETECTION/.test(normalized)) return 'Motion';
    if (/NEVER|OFF/.test(normalized)) return 'Never';
    return String(mode);
  JS
  item_tags: tags('Recording', 'camera' => '{#CAMERA.NAME}', 'application' => 'Protect'),
  triggers: [
    trigger(
      seed: 'trigger-camera-mode-change',
      expression: 'last(/Template UniFi Site Manager by HTTP/unifi.camera.recording.mode[{#CAMERA.ID}],#1)<>last(/Template UniFi Site Manager by HTTP/unifi.camera.recording.mode[{#CAMERA.ID}],#2)',
      name: '[Warning] Recording mode changed on camera {#CAMERA.NAME}',
      priority: 'WARNING',
      description: 'The recording mode changed between two successful collections.',
      opdata: 'Current mode: {ITEM.LASTVALUE1}',
      tags: {'camera' => '{#CAMERA.NAME}', 'application' => 'Protect'}
    )
  ]
)
camera_item_prototypes << camera_mode

camera_discovery_script = script(<<~'JS')
  var hosts = siteManagerData('/v1/hosts?pageSize=200');
  var managerSites = siteManagerData('/v1/sites?pageSize=200');
  var output = [];
  for (var h = 0; h < hosts.length; h++) {
      if (!appInstalled(hosts[h], 'protect')) continue;
      var cameras = connectorData(hosts[h].id, 'protect', '/v1/cameras', true);
      var siteIds = [];
      for (var s = 0; s < managerSites.length; s++) if (String(managerSites[s].hostId) === String(hosts[h].id)) siteIds.push(String(managerSites[s].siteId));
      var protectSite = siteIds.length === 1 ? siteIds[0] : String(hosts[h].id);
      for (var c = 0; c < cameras.length; c++) {
          output.push({
              camera_id: clean(cameras[c].id, ''),
              camera_name: clean(cameras[c].name, clean(cameras[c].mac, cameras[c].id)),
              camera_model: clean(cameras[c].type || cameras[c].model || cameras[c].modelKey, 'Camera'),
              camera_site_id: protectSite,
              host_id: String(hosts[h].id)
          });
      }
  }
  return JSON.stringify(output);
JS

cameras_lld = lld_rule(
  seed: 'lld-protect-cameras',
  name: 'LLD - Protect cameras',
  key: 'unifi.protect.cameras.discovery',
  script: camera_discovery_script,
  macros: {
    '{#CAMERA.ID}' => '$.camera_id',
    '{#CAMERA.NAME}' => '$.camera_name',
    '{#CAMERA.MODEL}' => '$.camera_model',
    '{#CAMERA.SITE.ID}' => '$.camera_site_id',
    '{#HOST.ID}' => '$.host_id'
  },
  item_prototypes: camera_item_prototypes,
  description: 'Discovers cameras through the official Protect Integration API on every console that advertises Protect.'
)

disk_item_prototypes = []
disk_raw = http_item(
  seed: 'disk-nvr-raw',
  name: '[{#DISK.MODEL} / {#DISK.SERIAL}] Protect: NVR storage raw data',
  key: 'unifi.disk.raw[{#HOST.ID},{#DISK.ID}]',
  url: '{$UNIFI.API.URL}/v1/connector/consoles/{#HOST.ID}/proxy/protect/integration/v1/nvrs',
  prototype: true
)
disk_raw['tags'] = tags('Raw', 'disk' => '{#DISK.MODEL}', 'device' => '{#DEVICE.MAC}', 'application' => 'Protect')
disk_item_prototypes << disk_raw

disk_lookup = <<~'JS'
  var data = JSON.parse(value);
  if (data.code || Number(data.httpStatusCode) >= 400) throw String(data.message || data.code);
  var storage = data.storage || data.storageInfo || {};
  var disks = storage.disks || storage.hardDrives || data.disks || data.hardDrives || [];
  var disk = null;
  for (var i = 0; i < disks.length; i++) if (String(disks[i].id || disks[i].slot || disks[i].serial) === '{#DISK.ID}') { disk = disks[i]; break; }
  if (!disk) throw 'Disk was not found in NVR response.';
JS

disk_smart = dependent_item(
  seed: 'disk-smart',
  name: '[{#DISK.MODEL} / {#DISK.SERIAL}] Storage: SMART health',
  key: 'unifi.disk.smart[{#DEVICE.MAC},{#DISK.ID}]',
  master: 'unifi.disk.raw[{#HOST.ID},{#DISK.ID}]',
  preprocessing: js(disk_lookup + <<~'JS'),
    var state = String(disk.smartStatus || disk.health || disk.status || 'UNKNOWN').toUpperCase();
    if (/CRITICAL|FAILED|ERROR|BAD/.test(state)) return 2;
    if (/WARN|DEGRADED/.test(state)) return 1;
    if (/HEALTHY|GOOD|OK|NORMAL/.test(state)) return 0;
    throw 'Unknown SMART state: ' + state;
  JS
  item_tags: tags('Storage', 'disk' => '{#DISK.MODEL}', 'device' => '{#DEVICE.MAC}'),
  triggers: [
    trigger(
      seed: 'trigger-disk-smart',
      expression: 'last(/Template UniFi Site Manager by HTTP/unifi.disk.smart[{#DEVICE.MAC},{#DISK.ID}])=2',
      name: '[Disaster] Critical SMART failure on {#DISK.MODEL}',
      priority: 'DISASTER',
      description: 'Protect reports a critical/failed/error SMART health state for the discovered disk.',
      opdata: 'Serial: {#DISK.SERIAL}; device: {#DEVICE.MAC}',
      tags: {'disk' => '{#DISK.MODEL}', 'application' => 'Protect'}
    )
  ]
)
disk_smart['valuemap'] = {'name' => 'UniFi SMART health'}
disk_item_prototypes << disk_smart

disk_temperature = dependent_item(
  seed: 'disk-temperature',
  name: '[{#DISK.MODEL} / {#DISK.SERIAL}] Storage: Temperature',
  key: 'unifi.disk.temperature[{#DEVICE.MAC},{#DISK.ID}]',
  master: 'unifi.disk.raw[{#HOST.ID},{#DISK.ID}]',
  value_type: 'FLOAT',
  units: '°C',
  preprocessing: js(disk_lookup + <<~'JS'),
    var temp = disk.temperatureC;
    if (typeof temp === 'undefined') temp = disk.temperature;
    if (typeof temp === 'undefined') throw 'Disk temperature is absent.';
    return Number(temp);
  JS
  item_tags: tags('Storage', 'disk' => '{#DISK.MODEL}', 'device' => '{#DEVICE.MAC}'),
  triggers: [
    trigger(
      seed: 'trigger-disk-temperature',
      expression: 'last(/Template UniFi Site Manager by HTTP/unifi.disk.temperature[{#DEVICE.MAC},{#DISK.ID}])>{$TEMP.MAX.WARN}',
      name: '[Average] High temperature on disk {#DISK.MODEL}',
      priority: 'AVERAGE',
      description: 'Disk temperature exceeded the configured maximum.',
      opdata: 'Temperature: {ITEM.LASTVALUE1}; serial: {#DISK.SERIAL}',
      tags: {'disk' => '{#DISK.MODEL}', 'application' => 'Protect'}
    )
  ]
)
disk_item_prototypes << disk_temperature

disk_used = dependent_item(
  seed: 'disk-used',
  name: '[{#DISK.MODEL} / {#DISK.SERIAL}] Storage: Space used',
  key: 'unifi.disk.used.pct[{#DEVICE.MAC},{#DISK.ID}]',
  master: 'unifi.disk.raw[{#HOST.ID},{#DISK.ID}]',
  value_type: 'FLOAT',
  units: '%',
  preprocessing: js(disk_lookup + <<~'JS'),
    if (typeof disk.usedPct !== 'undefined') return Number(disk.usedPct);
    if (Number(disk.capacityBytes) > 0 && typeof disk.freeBytes !== 'undefined') return (Number(disk.capacityBytes) - Number(disk.freeBytes)) * 100 / Number(disk.capacityBytes);
    throw 'Disk utilization is absent.';
  JS
  item_tags: tags('Storage', 'disk' => '{#DISK.MODEL}', 'device' => '{#DEVICE.MAC}')
)
disk_item_prototypes << disk_used

raid_status = dependent_item(
  seed: 'raid-status',
  name: '[{#DEVICE.MAC}] Storage: RAID state',
  key: 'unifi.raid.status[{#DEVICE.MAC}]',
  master: 'unifi.disk.raw[{#HOST.ID},{#DISK.ID}]',
  value_type: 'CHAR',
  preprocessing: js(<<~'JS'),
    var data = JSON.parse(value);
    var storage = data.storage || data.storageInfo || {};
    var state = storage.raidStatus || storage.raidState || data.raidStatus;
    if (typeof state === 'undefined') throw 'RAID state is not exposed by the current official Protect API.';
    return String(state);
  JS
  item_tags: tags('Storage', 'device' => '{#DEVICE.MAC}', 'application' => 'Protect')
)
disk_item_prototypes << raid_status

disk_discovery_script = script(<<~'JS')
  var hosts = siteManagerData('/v1/hosts?pageSize=200');
  var output = [];
  for (var h = 0; h < hosts.length; h++) {
      if (!appInstalled(hosts[h], 'protect')) continue;
      var nvr = connector(hosts[h].id, 'protect', '/v1/nvrs', true);
      if (!nvr) continue;
      var storage = nvr.storage || nvr.storageInfo || {};
      var disks = storage.disks || storage.hardDrives || nvr.disks || nvr.hardDrives || [];
      for (var d = 0; d < disks.length; d++) {
          output.push({
              disk_id: clean(disks[d].id || disks[d].slot || disks[d].serial, String(d + 1)),
              disk_model: clean(disks[d].model, 'Unknown disk'),
              disk_serial: clean(disks[d].serial, 'Unknown'),
              device_mac: clean(nvr.mac, clean(nvr.id, hosts[h].hardwareId)),
              host_id: String(hosts[h].id)
          });
      }
  }
  return JSON.stringify(output);
JS

disks_lld = lld_rule(
  seed: 'lld-protect-disks',
  name: 'LLD - Protect/NVR disks and storage',
  key: 'unifi.protect.disks.discovery',
  script: disk_discovery_script,
  macros: {
    '{#DISK.ID}' => '$.disk_id',
    '{#DISK.MODEL}' => '$.disk_model',
    '{#DISK.SERIAL}' => '$.disk_serial',
    '{#DEVICE.MAC}' => '$.device_mac',
    '{#HOST.ID}' => '$.host_id'
  },
  item_prototypes: disk_item_prototypes,
  description: 'Forward-compatible disk discovery. The current official Protect v7.2.105 NVR schema contains no disk, SMART, capacity, temperature or RAID fields, so this rule safely returns an empty array until such fields are officially exposed.'
)

wan_item_prototypes = []
wan_source = calculated_source(
  seed: 'wan-source',
  name: '[{#SITE.NAME} / {#WAN.NAME}] WAN: Interface source',
  key: 'unifi.wan.source[{#SITE.ID},{#WAN.ID}]',
  formula: 'last(//unifi.site.wans.raw[{#SITE.ID}])',
  item_tags: tags('Raw', 'site' => '{#SITE.NAME}', 'wan' => '{#WAN.NAME}')
)
wan_item_prototypes << wan_source

wan_lookup = <<~'JS'
  var payload = JSON.parse(value);
  if (payload.code || Number(payload.httpStatusCode) >= 400) throw String(payload.message || payload.code);
  var rows = Array.isArray(payload.data) ? payload.data : [];
  var wan = null;
  for (var i = 0; i < rows.length; i++) if (String(rows[i].id) === '{#WAN.ID}') { wan = rows[i]; break; }
  if (!wan) throw 'WAN interface was not found.';
JS

wan_configured_state = dependent_item(
  seed: 'wan-configured-state',
  name: '[{#SITE.NAME} / {#WAN.NAME}] WAN: Link state (when exposed)',
  key: 'unifi.wan.state[{#SITE.ID},{#WAN.ID}]',
  master: 'unifi.wan.source[{#SITE.ID},{#WAN.ID}]',
  preprocessing: js(wan_lookup + <<~'JS'),
    var state = wan.state || wan.status || wan.linkState;
    if (typeof state === 'undefined') throw 'Per-interface WAN state is not exposed by the current official WAN schema.';
    return /UP|ONLINE|ACTIVE|CONNECTED/i.test(String(state)) ? 1 : 0;
  JS
  item_tags: tags('WAN', 'site' => '{#SITE.NAME}', 'wan' => '{#WAN.NAME}')
)
wan_configured_state['valuemap'] = {'name' => 'UniFi availability'}
wan_item_prototypes << wan_configured_state

wan_internet = dependent_item(
  seed: 'wan-internet-state',
  name: '[{#SITE.NAME} / {#WAN.NAME}] WAN: Site internet availability (aggregate)',
  key: 'unifi.wan.internet[{#SITE.MANAGER.ID},{#WAN.NAME}]',
  master: 'unifi.sm.isp.raw',
  preprocessing: js(<<~'JS'),
    var payload = JSON.parse(value);
    var metrics = Array.isArray(payload.data) ? payload.data : [];
    for (var i = 0; i < metrics.length; i++) {
        if (String(metrics[i].siteId) !== '{#SITE.MANAGER.ID}') continue;
        var periods = Array.isArray(metrics[i].periods) ? metrics[i].periods : [];
        if (!periods.length) throw 'No ISP metric periods for site.';
        periods.sort(function (a, b) { return String(a.metricTime).localeCompare(String(b.metricTime)); });
        var wan = periods[periods.length - 1].data && periods[periods.length - 1].data.wan;
        if (!wan) throw 'WAN metrics are absent.';
        return Number(wan.downtime || 0) > 0 || Number(wan.uptime || 0) <= 0 ? 0 : 1;
    }
    throw 'Site is absent from ISP metrics.';
  JS
  item_tags: tags('WAN', 'site' => '{#SITE.NAME}', 'wan' => '{#WAN.NAME}'),
  triggers: [
    trigger(
      seed: 'trigger-primary-wan-down',
      expression: 'last(/Template UniFi Site Manager by HTTP/unifi.wan.internet[{#SITE.MANAGER.ID},{#WAN.NAME}])=0 and {#WAN.IS.PRIMARY}=1',
      name: '[Disaster] Primary WAN is down on {#SITE.NAME}',
      priority: 'DISASTER',
      description: 'The latest official ISP metric reports downtime/no uptime for the site. Current API data is aggregate per site; the primary WAN guard prevents duplicate events.',
      opdata: 'WAN: {#WAN.NAME}; site: {#SITE.NAME}',
      tags: {'site' => '{#SITE.NAME}', 'wan' => '{#WAN.NAME}'}
    )
  ]
)
wan_internet['valuemap'] = {'name' => 'UniFi availability'}
wan_item_prototypes << wan_internet

wan_failover = dependent_item(
  seed: 'wan-failover',
  name: '[{#SITE.NAME} / {#WAN.NAME}] WAN: Failover active (when exposed)',
  key: 'unifi.wan.failover.active[{#SITE.ID},{#WAN.ID}]',
  master: 'unifi.wan.source[{#SITE.ID},{#WAN.ID}]',
  preprocessing: js(wan_lookup + <<~'JS'),
    if (typeof wan.active !== 'undefined') return wan.active && Number('{#WAN.IS.PRIMARY}') === 0 ? 1 : 0;
    var role = wan.activeRole || wan.role || wan.priorityState;
    if (typeof role === 'undefined') throw 'Active WAN priority is not exposed by the current official WAN schema.';
    return /FAILOVER|SECONDARY_ACTIVE/i.test(String(role)) ? 1 : 0;
  JS
  item_tags: tags('WAN', 'site' => '{#SITE.NAME}', 'wan' => '{#WAN.NAME}'),
  triggers: [
    trigger(
      seed: 'trigger-wan-failover',
      expression: 'last(/Template UniFi Site Manager by HTTP/unifi.wan.failover.active[{#SITE.ID},{#WAN.ID}])=1',
      name: '[High] WAN failover is active on {#SITE.NAME}',
      priority: 'HIGH',
      description: 'A secondary WAN reports the active/failover role. This item is unsupported until the official API exposes the active role.',
      opdata: 'Active WAN: {#WAN.NAME}',
      tags: {'site' => '{#SITE.NAME}', 'wan' => '{#WAN.NAME}'}
    )
  ]
)
wan_failover['valuemap'] = {'name' => 'Boolean'}
wan_item_prototypes << wan_failover

wan_public_ip = dependent_item(
  seed: 'wan-public-ip',
  name: '[{#SITE.NAME} / {#WAN.NAME}] WAN: Public IP (when exposed)',
  key: 'unifi.wan.public.ip[{#SITE.ID},{#WAN.ID}]',
  master: 'unifi.wan.source[{#SITE.ID},{#WAN.ID}]',
  value_type: 'CHAR',
  preprocessing: js(wan_lookup + <<~'JS'),
    var ip = wan.publicIpAddress || wan.publicIp || wan.ipAddress;
    if (!ip) throw 'Public IP is not exposed by the current official WAN schema.';
    return String(ip);
  JS
  item_tags: tags('WAN', 'site' => '{#SITE.NAME}', 'wan' => '{#WAN.NAME}')
)
wan_item_prototypes << wan_public_ip

isp_fields = [
  ['avgLatency', 'latency', 'Average latency', 'ms', 'FLOAT'],
  ['packetLoss', 'packetloss', 'Packet loss', '%', 'FLOAT'],
  ['download_kbps', 'download', 'Observed download throughput', 'Kbps', 'UNSIGNED'],
  ['upload_kbps', 'upload', 'Observed upload throughput', 'Kbps', 'UNSIGNED']
]
isp_fields.each do |field, suffix, label, units, value_type|
  wan_item_prototypes << dependent_item(
    seed: "wan-isp-#{suffix}",
    name: "[{#SITE.NAME} / {#WAN.NAME}] WAN: #{label} (site aggregate)",
    key: "unifi.wan.#{suffix}[{#SITE.MANAGER.ID},{#WAN.NAME}]",
    master: 'unifi.sm.isp.raw',
    value_type: value_type,
    units: units,
    preprocessing: js(<<~JS),
      var payload = JSON.parse(value);
      var metrics = Array.isArray(payload.data) ? payload.data : [];
      for (var i = 0; i < metrics.length; i++) {
          if (String(metrics[i].siteId) !== '{#SITE.MANAGER.ID}') continue;
          var periods = Array.isArray(metrics[i].periods) ? metrics[i].periods : [];
          if (!periods.length) throw 'No ISP metric periods for site.';
          periods.sort(function (a, b) { return String(a.metricTime).localeCompare(String(b.metricTime)); });
          var wan = periods[periods.length - 1].data && periods[periods.length - 1].data.wan;
          if (!wan || typeof wan.#{field} === 'undefined') throw '#{field} is absent.';
          return Number(wan.#{field});
      }
      throw 'Site is absent from ISP metrics.';
    JS
    item_tags: tags('WAN', 'site' => '{#SITE.NAME}', 'wan' => '{#WAN.NAME}')
  )
end

%w[download upload].each do |direction|
  expected_macro = direction == 'download' ? '{#WAN.EXPECTED.DL}' : '{#WAN.EXPECTED.UL}'
  item = dependent_item(
    seed: "wan-speedtest-#{direction}",
    name: "[{#SITE.NAME} / {#WAN.NAME}] WAN: Internal Speedtest #{direction} (when exposed)",
    key: "unifi.wan.speedtest.#{direction}[{#SITE.ID},{#WAN.ID}]",
    master: 'unifi.wan.source[{#SITE.ID},{#WAN.ID}]',
    value_type: 'FLOAT',
    units: 'Mbps',
    preprocessing: js(wan_lookup + <<~JS),
      var speedtest = wan.speedtest || wan.lastSpeedtest || {};
      var result = speedtest.#{direction}Mbps;
      if (typeof result === 'undefined') result = wan.speedtest#{direction.capitalize}Mbps;
      if (typeof result === 'undefined') throw 'Internal Speedtest result is not exposed by the official WAN schema.';
      return Number(result);
    JS
    item_tags: tags('WAN', 'site' => '{#SITE.NAME}', 'wan' => '{#WAN.NAME}')
  )
  if direction == 'download'
    item['trigger_prototypes'] = [
      trigger(
        seed: 'trigger-speedtest-low',
        expression: "#{expected_macro}>0 and last(/Template UniFi Site Manager by HTTP/unifi.wan.speedtest.download[{#SITE.ID},{#WAN.ID}])<#{expected_macro}*{$WAN.SPEED.THRESHOLD.PCT}/100",
        name: '[High] WAN Speedtest below the acceptable threshold on {#SITE.NAME} / {#WAN.NAME}',
        priority: 'HIGH',
        description: 'The internal Speedtest download result is below expected Mbps × threshold percent. This trigger receives data only when Ubiquiti exposes the result in the official API.',
        opdata: 'Measured: {ITEM.LASTVALUE1}; expected: {#WAN.EXPECTED.DL} Mbps',
        tags: {'site' => '{#SITE.NAME}', 'wan' => '{#WAN.NAME}'}
      )
    ]
  end
  wan_item_prototypes << item
end

wan_discovery_script = script(<<~'JS')
  var hosts = siteManagerData('/v1/hosts?pageSize=200');
  var managerSites = siteManagerData('/v1/sites?pageSize=200');
  var output = [];
  for (var h = 0; h < hosts.length; h++) {
      if (!appInstalled(hosts[h], 'network')) continue;
      var sites = connectorPaged(hosts[h].id, 'network', '/v1/sites', true);
      for (var s = 0; s < sites.length; s++) {
          var managerId = '';
          for (var m = 0; m < managerSites.length; m++) {
              if (String(managerSites[m].hostId) !== String(hosts[h].id)) continue;
              var meta = managerSites[m].meta || {};
              if (lower(meta.name) === lower(sites[s].internalReference) || lower(meta.desc) === lower(sites[s].name)) { managerId = String(managerSites[m].siteId); break; }
          }
          var wans = connectorPaged(hosts[h].id, 'network', '/v1/sites/' + encodeURIComponent(sites[s].id) + '/wans', true);
          for (var w = 0; w < wans.length; w++) {
              var original = clean(wans[w].name, 'WAN' + (w + 1));
              var canonical = /(?:^|\D)2(?:\D|$)|secondary/i.test(original) ? 'WAN2' : (/1|primary/i.test(original) ? 'WAN1' : 'WAN' + (w + 1));
              output.push({
                  wan_id: clean(wans[w].id, canonical),
                  wan_name: canonical,
                  wan_display_name: original,
                  wan_is_primary: canonical === 'WAN1' ? '1' : '0',
                  wan_expected_dl: canonical === 'WAN2' ? String(params.wan2_dl) : String(params.wan1_dl),
                  wan_expected_ul: canonical === 'WAN2' ? String(params.wan2_ul) : String(params.wan1_ul),
                  site_id: clean(sites[s].id, ''),
                  site_manager_id: managerId || clean(sites[s].id, ''),
                  site_name: clean(sites[s].name, sites[s].id),
                  host_id: String(hosts[h].id)
              });
          }
      }
  }
  return JSON.stringify(output);
JS

wans_lld = lld_rule(
  seed: 'lld-wan-links',
  name: 'LLD - WAN links',
  key: 'unifi.wan.discovery',
  script: wan_discovery_script,
  macros: {
    '{#WAN.ID}' => '$.wan_id',
    '{#WAN.NAME}' => '$.wan_name',
    '{#WAN.DISPLAY.NAME}' => '$.wan_display_name',
    '{#WAN.IS.PRIMARY}' => '$.wan_is_primary',
    '{#WAN.EXPECTED.DL}' => '$.wan_expected_dl',
    '{#WAN.EXPECTED.UL}' => '$.wan_expected_ul',
    '{#SITE.ID}' => '$.site_id',
    '{#SITE.MANAGER.ID}' => '$.site_manager_id',
    '{#SITE.NAME}' => '$.site_name',
    '{#HOST.ID}' => '$.host_id'
  },
  item_prototypes: wan_item_prototypes,
  parameters: standard_script_parameters([
    {'name' => 'wan1_dl', 'value' => '{$WAN1.EXPECTED.DL}'},
    {'name' => 'wan1_ul', 'value' => '{$WAN1.EXPECTED.UL}'},
    {'name' => 'wan2_dl', 'value' => '{$WAN2.EXPECTED.DL}'},
    {'name' => 'wan2_ul', 'value' => '{$WAN2.EXPECTED.UL}'}
  ]),
  description: 'Discovers WAN interfaces. The official WAN schema currently guarantees only id/name; ISP latency, loss, throughput and uptime are site-aggregate metrics.'
)

routing_item_prototypes = [
  {
    'uuid' => uuid('routing-peer-state'),
    'name' => '[{#PROTOCOL} / {#PEER.IP}] Routing: Adjacency state',
    'type' => 'CALCULATED',
    'key' => 'unifi.routing.peer.state[{#PROTOCOL},{#PEER.IP}]',
    'delay' => '{$UNIFI.INTERVAL}',
    'history' => '90d',
    'trends' => '365d',
    'params' => '{#PEER.STATE}',
    'tags' => tags('Routing', 'neighbor' => '{#NEIGHBOR.NAME}', 'protocol' => '{#PROTOCOL}'),
    'trigger_prototypes' => [
      trigger(
        seed: 'trigger-routing-adjacency',
        expression: 'last(/Template UniFi Site Manager by HTTP/unifi.routing.peer.state[{#PROTOCOL},{#PEER.IP}])=0',
        name: '[Disaster] {#PROTOCOL} adjacency lost with {#PEER.IP}',
        priority: 'DISASTER',
        description: 'Structural trigger retained for the requested design. The parent LLD is disabled because the official Network API currently has no BGP/OSPF endpoint.',
        opdata: 'Neighbor: {#NEIGHBOR.NAME}',
        tags: {'neighbor' => '{#NEIGHBOR.NAME}', 'protocol' => '{#PROTOCOL}'}
      )
    ]
  },
  {
    'uuid' => uuid('routing-peer-flaps'),
    'name' => '[{#PROTOCOL} / {#PEER.IP}] Routing: State changes/flaps',
    'type' => 'CALCULATED',
    'key' => 'unifi.routing.peer.flaps[{#PROTOCOL},{#PEER.IP}]',
    'delay' => '{$UNIFI.INTERVAL}',
    'history' => '90d',
    'trends' => '365d',
    'params' => '{#PEER.FLAPS}',
    'tags' => tags('Routing', 'neighbor' => '{#NEIGHBOR.NAME}', 'protocol' => '{#PROTOCOL}')
  },
  {
    'uuid' => uuid('routing-peer-routes'),
    'name' => '[{#PROTOCOL} / {#PEER.IP}] Routing: Route count',
    'type' => 'CALCULATED',
    'key' => 'unifi.routing.peer.routes[{#PROTOCOL},{#PEER.IP}]',
    'delay' => '{$UNIFI.INTERVAL}',
    'history' => '90d',
    'trends' => '365d',
    'params' => '{#PEER.ROUTES}',
    'tags' => tags('Routing', 'neighbor' => '{#NEIGHBOR.NAME}', 'protocol' => '{#PROTOCOL}')
  }
]
routing_lld = lld_rule(
  seed: 'lld-dynamic-routing',
  name: 'LLD - Dynamic routing (BGP/OSPF capability placeholder)',
  key: 'unifi.routing.discovery',
  script: <<~'JS',
    /* The official Network 10.0.162 Integration API publishes no BGP or OSPF peer endpoint. */
    return '[]';
  JS
  macros: {
    '{#PEER.IP}' => '$.peer_ip',
    '{#PROTOCOL}' => '$.protocol',
    '{#NEIGHBOR.NAME}' => '$.neighbor_name',
    '{#PEER.STATE}' => '$.peer_state',
    '{#PEER.FLAPS}' => '$.peer_flaps',
    '{#PEER.ROUTES}' => '$.peer_routes'
  },
  item_prototypes: routing_item_prototypes,
  description: 'Intentionally disabled: the official API has no BGP/OSPF neighbor, state, flap or route-count endpoint. Enabling a fabricated collector would create false assurance.',
  parameters: [],
  status: 'DISABLED'
)

subnet_item_prototypes = []
subnet_clients_source = calculated_source(
  seed: 'subnet-clients-source',
  name: '[{#SUBNET.NAME}] DHCP: Connected clients source',
  key: 'unifi.subnet.clients.source[{#SITE.ID},{#SUBNET.ID}]',
  formula: 'last(//unifi.site.clients.raw[{#SITE.ID}])',
  item_tags: tags('Raw', 'site' => '{#SITE.NAME}', 'subnet' => '{#SUBNET.NAME}')
)
subnet_item_prototypes << subnet_clients_source

dhcp_usage = dependent_item(
  seed: 'subnet-dhcp-usage',
  name: '[{#SITE.NAME} / {#SUBNET.NAME}] DHCP: Connected-address utilization estimate',
  key: 'unifi.subnet.dhcp.used.pct[{#SITE.ID},{#SUBNET.ID}]',
  master: 'unifi.subnet.clients.source[{#SITE.ID},{#SUBNET.ID}]',
  value_type: 'FLOAT',
  units: '%',
  preprocessing: js(<<~'JS'),
    function ipv4(value) {
        var parts = String(value).split('.');
        if (parts.length !== 4) return null;
        var result = 0;
        for (var i = 0; i < 4; i++) {
            var part = Number(parts[i]);
            if (part < 0 || part > 255 || Math.floor(part) !== part) return null;
            result = result * 256 + part;
        }
        return result;
    }
    var start = ipv4('{#DHCP.START}');
    var stop = ipv4('{#DHCP.STOP}');
    if (start === null || stop === null || stop < start) throw 'DHCP range is unavailable.';
    var payload = JSON.parse(value);
    if (payload.code || Number(payload.httpStatusCode) >= 400) throw String(payload.message || payload.code);
    var clients = Array.isArray(payload.data) ? payload.data : [];
    var used = {};
    for (var i = 0; i < clients.length; i++) {
        var address = ipv4(clients[i].ipAddress);
        if (address !== null && address >= start && address <= stop) used[String(address)] = true;
    }
    return Object.keys(used).length * 100 / (stop - start + 1);
  JS
  item_tags: tags('DHCP', 'site' => '{#SITE.NAME}', 'subnet' => '{#SUBNET.NAME}'),
  triggers: [
    trigger(
      seed: 'trigger-dhcp-high',
      expression: 'last(/Template UniFi Site Manager by HTTP/unifi.subnet.dhcp.used.pct[{#SITE.ID},{#SUBNET.ID}])>{$DHCP.THRESHOLD.PCT}',
      name: '[Average] DHCP pool usage is high on {#SUBNET.NAME}',
      priority: 'AVERAGE',
      description: 'Connected client IPs inside the configured pool exceed the threshold. This is an estimate, because the official API does not publish the DHCP lease table.',
      opdata: 'Estimated use: {ITEM.LASTVALUE1}; subnet: {#SUBNET.CIDR}',
      tags: {'site' => '{#SITE.NAME}', 'subnet' => '{#SUBNET.NAME}'}
    )
  ]
)
subnet_item_prototypes << dhcp_usage

subnet_discovery_script = script(<<~'JS')
  var hosts = siteManagerData('/v1/hosts?pageSize=200');
  var output = [];
  for (var h = 0; h < hosts.length; h++) {
      if (!appInstalled(hosts[h], 'network')) continue;
      var sites = connectorPaged(hosts[h].id, 'network', '/v1/sites', true);
      for (var s = 0; s < sites.length; s++) {
          var networks = connectorPaged(hosts[h].id, 'network', '/v1/sites/' + encodeURIComponent(sites[s].id) + '/networks', true);
          for (var n = 0; n < networks.length; n++) {
              var detail = connector(hosts[h].id, 'network', '/v1/sites/' + encodeURIComponent(sites[s].id) + '/networks/' + encodeURIComponent(networks[n].id), true);
              var ipv4 = detail && detail.ipv4Configuration ? detail.ipv4Configuration : {};
              var dhcp = ipv4.dhcpConfiguration || {};
              var range = dhcp.ipAddressRange || {};
              if (!ipv4.hostIpAddress || typeof ipv4.prefixLength === 'undefined') continue;
              output.push({
                  subnet_id: clean(networks[n].id, ''),
                  subnet_name: clean(networks[n].name, networks[n].id),
                  subnet_cidr: String(ipv4.hostIpAddress) + '/' + String(ipv4.prefixLength),
                  dhcp_start: clean(range.start, ''),
                  dhcp_stop: clean(range.stop, ''),
                  site_id: clean(sites[s].id, ''),
                  site_name: clean(sites[s].name, sites[s].id),
                  host_id: String(hosts[h].id)
              });
          }
      }
  }
  return JSON.stringify(output);
JS

subnets_lld = lld_rule(
  seed: 'lld-subnets',
  name: 'LLD - Subnets and DHCP pools',
  key: 'unifi.subnets.discovery',
  script: subnet_discovery_script,
  macros: {
    '{#SUBNET.ID}' => '$.subnet_id',
    '{#SUBNET.NAME}' => '$.subnet_name',
    '{#SUBNET.CIDR}' => '$.subnet_cidr',
    '{#DHCP.START}' => '$.dhcp_start',
    '{#DHCP.STOP}' => '$.dhcp_stop',
    '{#SITE.ID}' => '$.site_id',
    '{#SITE.NAME}' => '$.site_name',
    '{#HOST.ID}' => '$.host_id'
  },
  item_prototypes: subnet_item_prototypes,
  description: 'Discovers official Network objects and DHCP ranges. Utilization is estimated from connected client addresses, not from the unavailable DHCP lease table.'
)

ssid_item_prototypes = []
ssid_clients_source = calculated_source(
  seed: 'ssid-clients-source',
  name: '[{#SITE.NAME} / {#SSID.NAME}] WiFi: Connected clients source',
  key: 'unifi.ssid.clients.source[{#SITE.ID},{#SSID.ID}]',
  formula: 'last(//unifi.site.clients.raw[{#SITE.ID}])',
  item_tags: tags('Raw', 'site' => '{#SITE.NAME}', 'ssid' => '{#SSID.NAME}')
)
ssid_item_prototypes << ssid_clients_source

ssid_clients = dependent_item(
  seed: 'ssid-clients',
  name: '[{#SITE.NAME} / {#SSID.NAME}] WiFi: Connected clients (when attributed)',
  key: 'unifi.ssid.clients[{#SITE.ID},{#SSID.ID}]',
  master: 'unifi.ssid.clients.source[{#SITE.ID},{#SSID.ID}]',
  preprocessing: js(<<~'JS'),
    var payload = JSON.parse(value);
    if (payload.code || Number(payload.httpStatusCode) >= 400) throw String(payload.message || payload.code);
    var clients = Array.isArray(payload.data) ? payload.data : [];
    var count = 0;
    var attributionSeen = false;
    for (var i = 0; i < clients.length; i++) {
        if (String(clients[i].type).toUpperCase() !== 'WIRELESS') continue;
        var id = clients[i].wifiBroadcastId || clients[i].ssidId || (clients[i].wifi && clients[i].wifi.broadcastId);
        var name = clients[i].ssid || (clients[i].wifi && clients[i].wifi.ssid);
        if (typeof id !== 'undefined' || typeof name !== 'undefined') attributionSeen = true;
        if (String(id || '') === '{#SSID.ID}' || String(name || '') === '{#SSID.NAME}') count++;
    }
    if (!attributionSeen && clients.length) throw 'The official client list does not attribute clients to an SSID.';
    return count;
  JS
  item_tags: tags('WiFi', 'site' => '{#SITE.NAME}', 'ssid' => '{#SSID.NAME}')
)
ssid_item_prototypes << ssid_clients

ssid_discovery_script = script(<<~'JS')
  var hosts = siteManagerData('/v1/hosts?pageSize=200');
  var output = [];
  for (var h = 0; h < hosts.length; h++) {
      if (!appInstalled(hosts[h], 'network')) continue;
      var sites = connectorPaged(hosts[h].id, 'network', '/v1/sites', true);
      for (var s = 0; s < sites.length; s++) {
          var broadcasts = connectorPaged(hosts[h].id, 'network', '/v1/sites/' + encodeURIComponent(sites[s].id) + '/wifi/broadcasts', true);
          for (var b = 0; b < broadcasts.length; b++) {
              output.push({
                  ssid_id: clean(broadcasts[b].id, ''),
                  ssid_name: clean(broadcasts[b].name, broadcasts[b].id),
                  site_id: clean(sites[s].id, ''),
                  site_name: clean(sites[s].name, sites[s].id),
                  host_id: String(hosts[h].id)
              });
          }
      }
  }
  return JSON.stringify(output);
JS

ssids_lld = lld_rule(
  seed: 'lld-ssids',
  name: 'LLD - WiFi SSIDs',
  key: 'unifi.ssids.discovery',
  script: ssid_discovery_script,
  macros: {
    '{#SSID.ID}' => '$.ssid_id',
    '{#SSID.NAME}' => '$.ssid_name',
    '{#SITE.ID}' => '$.site_id',
    '{#SITE.NAME}' => '$.site_name',
    '{#HOST.ID}' => '$.host_id'
  },
  item_prototypes: ssid_item_prototypes,
  description: 'Discovers WiFi broadcasts/SSIDs. The current client-list contract does not attribute a client to an SSID, so per-SSID counts remain unsupported unless that field is present.'
)

radio_item_prototypes = []
radio_stats_source = calculated_source(
  seed: 'radio-stats-source',
  name: '[{#AP.NAME} / {#RADIO.BAND}] Radio: Device statistics source',
  key: 'unifi.radio.stats.source[{#AP.MAC},{#RADIO.BAND}]',
  formula: 'last(//unifi.device.stats.raw[{#DEVICE.ID},{#SITE.ID}])',
  item_tags: tags('Raw', 'device' => '{#AP.NAME}', 'radio' => '{#RADIO.BAND}', 'site' => '{#SITE.NAME}')
)
radio_item_prototypes << radio_stats_source

radio_clients_source = calculated_source(
  seed: 'radio-clients-source',
  name: '[{#AP.NAME} / {#RADIO.BAND}] Radio: Client list source',
  key: 'unifi.radio.clients.source[{#AP.MAC},{#RADIO.BAND}]',
  formula: 'last(//unifi.site.clients.raw[{#SITE.ID}])',
  item_tags: tags('Raw', 'device' => '{#AP.NAME}', 'radio' => '{#RADIO.BAND}', 'site' => '{#SITE.NAME}')
)
radio_item_prototypes << radio_clients_source

radio_stats_lookup = <<~'JS'
  var data = JSON.parse(value);
  if (data.code || Number(data.httpStatusCode) >= 400) throw String(data.message || data.code);
  var radios = data.interfaces && Array.isArray(data.interfaces.radios) ? data.interfaces.radios : [];
  var radio = null;
  for (var i = 0; i < radios.length; i++) if (String(radios[i].frequencyGHz) === '{#RADIO.FREQUENCY}') { radio = radios[i]; break; }
  if (!radio) throw 'Radio statistics were not found.';
JS

radio_retries = dependent_item(
  seed: 'radio-retries',
  name: '[{#AP.NAME} / {#RADIO.BAND}] Radio: TX retries',
  key: 'unifi.radio.tx.retries[{#AP.MAC},{#RADIO.BAND}]',
  master: 'unifi.radio.stats.source[{#AP.MAC},{#RADIO.BAND}]',
  value_type: 'FLOAT',
  units: '%',
  preprocessing: js(radio_stats_lookup + <<~'JS'),
    if (typeof radio.txRetriesPct === 'undefined') throw 'TX retries are absent.';
    return Number(radio.txRetriesPct);
  JS
  item_tags: tags('WiFi', 'device' => '{#AP.NAME}', 'radio' => '{#RADIO.BAND}', 'site' => '{#SITE.NAME}')
)
radio_item_prototypes << radio_retries

radio_airtime = dependent_item(
  seed: 'radio-airtime',
  name: '[{#AP.NAME} / {#RADIO.BAND}] Radio: Airtime utilization (when exposed)',
  key: 'unifi.radio.airtime[{#AP.MAC},{#RADIO.BAND}]',
  master: 'unifi.radio.stats.source[{#AP.MAC},{#RADIO.BAND}]',
  value_type: 'FLOAT',
  units: '%',
  preprocessing: js(radio_stats_lookup + <<~'JS'),
    var airtime = radio.airtimeUtilizationPct;
    if (typeof airtime === 'undefined') airtime = radio.channelUtilizationPct;
    if (typeof airtime === 'undefined') throw 'Airtime/channel utilization is not exposed by the current official radio statistics schema.';
    return Number(airtime);
  JS
  item_tags: tags('WiFi', 'device' => '{#AP.NAME}', 'radio' => '{#RADIO.BAND}', 'site' => '{#SITE.NAME}'),
  triggers: [
    trigger(
      seed: 'trigger-radio-airtime',
      expression: 'avg(/Template UniFi Site Manager by HTTP/unifi.radio.airtime[{#AP.MAC},{#RADIO.BAND}],10m)>80',
      name: '[Average] High WiFi channel utilization on {#AP.NAME} / {#RADIO.BAND}',
      priority: 'AVERAGE',
      description: 'Ten-minute average airtime/channel utilization exceeds 80%. No value is generated until the official API exposes this field.',
      opdata: 'Average/current utilization: {ITEM.LASTVALUE1}',
      tags: {'device' => '{#AP.NAME}', 'radio' => '{#RADIO.BAND}', 'site' => '{#SITE.NAME}'}
    )
  ]
)
radio_item_prototypes << radio_airtime

radio_experience = dependent_item(
  seed: 'radio-experience',
  name: '[{#AP.NAME} / {#RADIO.BAND}] Radio: WiFi experience (when exposed)',
  key: 'unifi.radio.experience[{#AP.MAC},{#RADIO.BAND}]',
  master: 'unifi.radio.stats.source[{#AP.MAC},{#RADIO.BAND}]',
  value_type: 'FLOAT',
  units: '%',
  preprocessing: js(radio_stats_lookup + <<~'JS'),
    var score = radio.wifiExperiencePct;
    if (typeof score === 'undefined') score = radio.experienceScore;
    if (typeof score === 'undefined') throw 'WiFi experience is not exposed by the current official radio statistics schema.';
    return Number(score);
  JS
  item_tags: tags('WiFi', 'device' => '{#AP.NAME}', 'radio' => '{#RADIO.BAND}', 'site' => '{#SITE.NAME}')
)
radio_item_prototypes << radio_experience

radio_band_clients = dependent_item(
  seed: 'radio-band-clients',
  name: '[{#AP.NAME} / {#RADIO.BAND}] Radio: Connected clients (when band is attributed)',
  key: 'unifi.radio.clients[{#AP.MAC},{#RADIO.BAND}]',
  master: 'unifi.radio.clients.source[{#AP.MAC},{#RADIO.BAND}]',
  preprocessing: js(<<~'JS'),
    var payload = JSON.parse(value);
    var clients = Array.isArray(payload.data) ? payload.data : [];
    var count = 0;
    var bandSeen = false;
    for (var i = 0; i < clients.length; i++) {
        if (String(clients[i].uplinkDeviceId) !== '{#DEVICE.ID}') continue;
        var band = clients[i].frequencyGHz || clients[i].radioBand || (clients[i].wifi && clients[i].wifi.frequencyGHz);
        if (typeof band !== 'undefined') bandSeen = true;
        if (String(band) === '{#RADIO.FREQUENCY}' || String(band) === '{#RADIO.BAND}') count++;
    }
    if (!bandSeen && clients.length) throw 'The official client list does not attribute clients to a radio band.';
    return count;
  JS
  item_tags: tags('WiFi', 'device' => '{#AP.NAME}', 'radio' => '{#RADIO.BAND}', 'site' => '{#SITE.NAME}')
)
radio_item_prototypes << radio_band_clients

radio_discovery_script = script(<<~'JS')
  var hosts = siteManagerData('/v1/hosts?pageSize=200');
  var output = [];
  function band(frequency) {
      if (String(frequency) === '2.4') return '2.4GHz';
      if (String(frequency) === '5') return '5GHz';
      if (String(frequency) === '6') return '6GHz';
      return String(frequency) + 'GHz';
  }
  for (var h = 0; h < hosts.length; h++) {
      if (!appInstalled(hosts[h], 'network')) continue;
      var sites = connectorPaged(hosts[h].id, 'network', '/v1/sites', true);
      for (var s = 0; s < sites.length; s++) {
          var devices = connectorPaged(hosts[h].id, 'network', '/v1/sites/' + encodeURIComponent(sites[s].id) + '/devices', true);
          for (var d = 0; d < devices.length; d++) {
              if (!Array.isArray(devices[d].interfaces) || devices[d].interfaces.indexOf('radios') === -1) continue;
              var detail = connector(hosts[h].id, 'network', '/v1/sites/' + encodeURIComponent(sites[s].id) + '/devices/' + encodeURIComponent(devices[d].id), true);
              var radios = detail && detail.interfaces && Array.isArray(detail.interfaces.radios) ? detail.interfaces.radios : [];
              for (var r = 0; r < radios.length; r++) {
                  output.push({
                      ap_mac: clean(devices[d].macAddress, devices[d].id),
                      ap_name: clean(devices[d].name, clean(devices[d].macAddress, 'AP')),
                      device_id: clean(devices[d].id, ''),
                      radio_frequency: clean(radios[r].frequencyGHz, ''),
                      radio_band: band(radios[r].frequencyGHz),
                      site_id: clean(sites[s].id, ''),
                      site_name: clean(sites[s].name, sites[s].id),
                      host_id: String(hosts[h].id)
                  });
              }
          }
      }
  }
  return JSON.stringify(output);
JS

radios_lld = lld_rule(
  seed: 'lld-ap-radios',
  name: 'LLD - AP radios',
  key: 'unifi.ap.radios.discovery',
  script: radio_discovery_script,
  macros: {
    '{#AP.MAC}' => '$.ap_mac',
    '{#AP.NAME}' => '$.ap_name',
    '{#DEVICE.ID}' => '$.device_id',
    '{#RADIO.BAND}' => '$.radio_band',
    '{#RADIO.FREQUENCY}' => '$.radio_frequency',
    '{#SITE.ID}' => '$.site_id',
    '{#SITE.NAME}' => '$.site_name',
    '{#HOST.ID}' => '$.host_id'
  },
  item_prototypes: radio_item_prototypes,
  description: 'Discovers 2.4/5/6/60 GHz radios. Official latest statistics currently guarantee frequencyGHz and txRetriesPct only.'
)

macros = [
  {
    'macro' => '{$UNIFI.API.KEY}',
    'type' => 'SECRET_TEXT',
    'description' => 'API key created in UniFi Site Manager. Never commit a real key.'
  },
  {
    'macro' => '{$UNIFI.API.URL}',
    'value' => 'https://api.ui.com',
    'description' => 'Official UniFi API base URL.'
  },
  {
    'macro' => '{$UNIFI.INTERVAL}',
    'value' => '5m',
    'description' => 'Regular collection interval.'
  },
  {
    'macro' => '{$UNIFI.DISCOVERY.INTERVAL}',
    'value' => '1h',
    'description' => 'Low-level discovery interval. Large estates should increase it to stay below the per-console Cloud Connector rate limit.'
  },
  {
    'macro' => '{$UNIFI.HTTP.TIMEOUT}',
    'value' => '25s',
    'description' => 'HTTP Agent timeout. Cloud Connector itself terminates proxied requests after 25 seconds.'
  },
  {
    'macro' => '{$UNIFI.LLD.TIMEOUT}',
    'value' => '60s',
    'description' => 'JavaScript LLD timeout. Increase carefully for large multi-console accounts.'
  },
  {
    'macro' => '{$UNIFI.API.NODATA}',
    'value' => '15m',
    'description' => 'Maximum interval without a Site Manager API response.'
  },
  {
    'macro' => '{$UNIFI.DATA.MAX.AGE}',
    'value' => '30m',
    'description' => 'Maximum acceptable age for inventory data reported by Site Manager.'
  },
  {
    'macro' => '{$UNIFI.BACKUP.MAX.AGE}',
    'value' => '7d',
    'description' => 'Maximum acceptable age of a console cloud backup when latestBackupTime is available.'
  },
  {
    'macro' => '{$WAN1.EXPECTED.DL}',
    'value' => '0',
    'description' => 'Expected WAN1 download speed in Mbps. Zero disables the Speedtest threshold.'
  },
  {
    'macro' => '{$WAN1.EXPECTED.UL}',
    'value' => '0',
    'description' => 'Expected WAN1 upload speed in Mbps.'
  },
  {
    'macro' => '{$WAN2.EXPECTED.DL}',
    'value' => '0',
    'description' => 'Expected WAN2 download speed in Mbps. Zero disables the Speedtest threshold.'
  },
  {
    'macro' => '{$WAN2.EXPECTED.UL}',
    'value' => '0',
    'description' => 'Expected WAN2 upload speed in Mbps.'
  },
  {
    'macro' => '{$WAN.SPEED.THRESHOLD.PCT}',
    'value' => '70',
    'description' => 'Minimum acceptable internal Speedtest percentage.'
  },
  {
    'macro' => '{$DHCP.THRESHOLD.PCT}',
    'value' => '90',
    'description' => 'DHCP connected-address utilization threshold.'
  },
  {
    'macro' => '{$TEMP.MAX.WARN}',
    'value' => '55',
    'description' => 'Maximum acceptable device or disk temperature in degrees Celsius.'
  }
]

valuemaps = [
  {
    'uuid' => uuid('valuemap-availability'),
    'name' => 'UniFi availability',
    'mappings' => [
      {'value' => '0', 'newvalue' => 'Offline/Unavailable'},
      {'value' => '1', 'newvalue' => 'Online/Available'},
      {'value' => '2', 'newvalue' => 'Unknown'}
    ]
  },
  {
    'uuid' => uuid('valuemap-boolean'),
    'name' => 'Boolean',
    'mappings' => [
      {'value' => '0', 'newvalue' => 'No'},
      {'value' => '1', 'newvalue' => 'Yes'}
    ]
  },
  {
    'uuid' => uuid('valuemap-smart'),
    'name' => 'UniFi SMART health',
    'mappings' => [
      {'value' => '0', 'newvalue' => 'Healthy'},
      {'value' => '1', 'newvalue' => 'Warning'},
      {'value' => '2', 'newvalue' => 'Critical'}
    ]
  }
]

template = {
  'uuid' => uuid('template'),
  'template' => TEMPLATE_NAME,
  'name' => TEMPLATE_NAME,
  'description' => <<~DESC,
    PT-BR:
    Monitoramento centralizado da conta UniFi pela API oficial api.ui.com. Itens HTTP Agent
    fazem a coleta assíncrona; regras LLD JavaScript percorrem consoles e aplicações Network
    e Protect. O template gera alarmes de API, console, site, dispositivo, câmera, WAN,
    firewall, DHCP e firmware somente quando a API fornece evidência.

    Limites oficiais relevantes em 2026-09-02: o contrato Network 10.0.162 não publica
    BGP/OSPF, tabela de leases DHCP, VLAN operacional, PoE em watts, airtime, experiência
    ou Speedtest; o Protect 7.2.105 não publica gravação efetiva, modo de gravação,
    discos/SMART/RAID. Itens compatíveis com esses campos tornam-se unsupported e as LLDs
    sem endpoint retornam vazio, evitando falso estado OK.

    EN:
    Centralized monitoring of a UniFi account through the official api.ui.com API. HTTP Agent
    items provide asynchronous collection while JavaScript LLD rules enumerate consoles and
    Network/Protect entities. Alerts are emitted only when the official response contains the
    required evidence; unavailable official capabilities never produce a fabricated healthy value.
  DESC
  'vendor' => {'name' => 'Daniel Carvalho', 'version' => '7.4-1'},
  'groups' => [{'name' => 'Templates/Applications'}],
  'items' => account_items,
  'discovery_rules' => [
    console_lld,
    sites_lld,
    devices_lld,
    ports_lld,
    cameras_lld,
    disks_lld,
    wans_lld,
    routing_lld,
    subnets_lld,
    ssids_lld,
    radios_lld
  ],
  'tags' => [
    {'tag' => 'class', 'value' => 'network'},
    {'tag' => 'target', 'value' => 'unifi-site-manager'}
  ],
  'macros' => macros,
  'valuemaps' => valuemaps
}

export = {
  'zabbix_export' => {
    'version' => '7.4',
    'template_groups' => [
      {'uuid' => uuid('template-group-applications'), 'name' => 'Templates/Applications'}
    ],
    'templates' => [template]
  }
}

banner = <<~HEADER
  # PT-BR: Template avançado para UniFi Site Manager, Network e Protect no Zabbix 7.4.
  # EN: Advanced UniFi Site Manager, Network, and Protect template for Zabbix 7.4.
  #
  # Autor / Author: Daniel Carvalho <danielrc10@gmail.com>
  # LinkedIn: https://www.linkedin.com/in/daniel-ti/
  # Repositório / Repository: https://github.com/danielrc10/zabbix
  # Licença / License: PolyForm Noncommercial 1.0.0
  # Uso comercial / Commercial use: contato / contact danielrc10@gmail.com

HEADER

yaml = YAML.dump(export).sub(/\A---\s*\n/, '')
File.write(OUTPUT, banner + yaml)
File.write(SITE_JS_OUTPUT, <<~HEADER + site_discovery_script)
  /*
   * PT-BR: Cópia legível do JavaScript usado na LLD de Sites do template.
   * EN: Readable copy of the JavaScript embedded in the template Sites LLD.
   *
   * Parameters supplied by Zabbix: api_url={$UNIFI.API.URL}, token={$UNIFI.API.KEY}
   */

HEADER
puts "Generated #{OUTPUT}"
puts "Generated #{SITE_JS_OUTPUT}"
