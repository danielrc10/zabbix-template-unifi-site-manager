# UniFi Site Manager, Network e Protect / UniFi Site Manager, Network and Protect

[![Validar / Validate](https://github.com/danielrc10/zabbix-template-unifi-site-manager/actions/workflows/validate.yml/badge.svg)](https://github.com/danielrc10/zabbix-template-unifi-site-manager/actions/workflows/validate.yml)
[![Licença / License: PolyForm NC 1.0.0](https://img.shields.io/badge/licen%C3%A7a-PolyForm%20NC%201.0.0-blue.svg)](LICENSE)

[Catálogo Projetos Zabbix](https://github.com/danielrc10/projetos-zabbix)

[Português](#português) · [English](#english)

## Português

Projeto API-first para monitoramento centralizado de contas UniFi no Zabbix por meio da API oficial `https://api.ui.com`. O template principal funciona remotamente sem VPN ou Zabbix Proxy no site. Uma extensão SNMP opcional acrescenta telemetria local de interfaces, rádios e VAPs, mas nunca substitui a API.

### Versões

| Zabbix | Estado | Arquivos |
|---|---|---|
| 7.4+ | Template principal `1.1.0` + SNMP Extension `1.0.0` | [Abrir versão 7.4](zabbix-7.4/README.md) |

O template diferencia dado oficial disponível, dado condicional e capacidade ainda ausente da API. Uma métrica ausente nunca é convertida em um falso estado saudável.

## English

API-first Zabbix project for centralized UniFi monitoring through the official `https://api.ui.com` API. The primary template works remotely without a site VPN or Zabbix Proxy. An optional SNMP extension adds local interface, radio, and VAP telemetry but never replaces the API.

### Versions

| Zabbix | Status | Files |
|---|---|---|
| 7.4+ | Primary template `1.1.0` + SNMP Extension `1.0.0` | [Open version 7.4](zabbix-7.4/README.md#english) |

The template distinguishes available official data, conditional fields, and capabilities not yet exposed by the API. A missing metric is never converted into a fabricated healthy state.
