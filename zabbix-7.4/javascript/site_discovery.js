/*
 * PT-BR: Cópia legível do JavaScript usado na LLD de Sites do template.
 * EN: Readable copy of the JavaScript embedded in the template Sites LLD.
 *
 * Parameters supplied by Zabbix: api_url={$UNIFI.API.URL}, token={$UNIFI.API.KEY}
 */

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
