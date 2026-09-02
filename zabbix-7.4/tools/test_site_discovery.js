#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const source = fs.readFileSync(path.resolve(__dirname, '../javascript/site_discovery.js'), 'utf8');

function execute(siteManagerPayload) {
  const hostPayload = {
    data: [{id: 'console-1', hardwareId: 'console-mac', userData: {controllers: ['network']}}],
    httpStatusCode: 200
  };
  const localSitesPayload = {
    data: [{id: '11111111-2222-4333-8444-555555555555', name: 'Default', internalReference: 'default'}],
    count: 1,
    totalCount: 1,
    offset: 0,
    limit: 200
  };

  function HttpRequest() {
    this.status = 200;
    this.addHeader = function () {};
    this.getStatus = () => this.status;
    this.get = (url) => {
      if (url.includes('/v1/sites?pageSize=200')) return JSON.stringify(siteManagerPayload);
      if (url.includes('/v1/hosts?pageSize=200')) return JSON.stringify(hostPayload);
      if (url.includes('/proxy/network/integration/v1/sites?offset=0&limit=200')) return JSON.stringify(localSitesPayload);
      throw new Error(`Unexpected URL: ${url}`);
    };
  }

  const run = new Function('value', 'HttpRequest', source);
  return JSON.parse(run(JSON.stringify({api_url: 'https://api.ui.com', token: 'test-key'}), HttpRequest));
}

const flat = execute({
  data: [{
    siteId: 'sm-independent-1',
    hostId: 'console-1',
    meta: {name: 'default', desc: 'Default'}
  }],
  httpStatusCode: 200
});

if (flat.length !== 1 || flat[0].site_id !== 'sm-independent-1' || flat[0].site_type !== 'Independent') {
  throw new Error(`Flat Site Manager response was not normalized: ${JSON.stringify(flat)}`);
}

const fabric = execute({
  data: {
    independentSites: [],
    fabrics: [{
      id: 'fabric-1',
      sites: [{siteId: 'sm-fabric-1', hostId: 'console-1', meta: {name: 'default', desc: 'Default'}}]
    }]
  },
  httpStatusCode: 200
});

if (fabric.length !== 1 || fabric[0].site_id !== 'sm-fabric-1' || fabric[0].site_type !== 'Fabric' || fabric[0].fabric_id !== 'fabric-1') {
  throw new Error(`Nested Fabric response was not normalized: ${JSON.stringify(fabric)}`);
}

console.log('OK: flat Independent and nested Fabric site payloads were normalized and correlated');
