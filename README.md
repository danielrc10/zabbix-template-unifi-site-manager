# UniFi Site Manager, Network e Protect / UniFi Site Manager, Network and Protect

[![Validar / Validate](https://github.com/danielrc10/zabbix-template-unifi-site-manager/actions/workflows/validate.yml/badge.svg)](https://github.com/danielrc10/zabbix-template-unifi-site-manager/actions/workflows/validate.yml)
[![Licença / License: PolyForm NC 1.0.0](https://img.shields.io/badge/licen%C3%A7a-PolyForm%20NC%201.0.0-blue.svg)](LICENSE)

[Catálogo Projetos Zabbix](https://github.com/danielrc10/projetos-zabbix)

[Português](#português) · [English](#english)

## Português

Template avançado para monitoramento centralizado de contas UniFi no Zabbix por meio da API oficial `https://api.ui.com`. A solução combina itens HTTP Agent assíncronos com LLD em JavaScript para descobrir consoles, sites, dispositivos Network, portas, câmeras Protect, WANs, redes/DHCP, SSIDs e rádios.

### Versões

| Zabbix | Estado | Arquivos |
|---|---|---|
| 7.4+ | Validado estruturalmente | [Abrir versão 7.4](zabbix-7.4/README.md) |

O template diferencia dado oficial disponível, dado condicional e capacidade ainda ausente da API. Uma métrica ausente nunca é convertida em um falso estado saudável.

## English

Advanced Zabbix template for centralized monitoring of UniFi accounts through the official `https://api.ui.com` API. It combines asynchronous HTTP Agent items with JavaScript LLD to discover consoles, sites, Network devices, ports, Protect cameras, WANs, networks/DHCP, SSIDs, and radios.

### Versions

| Zabbix | Status | Files |
|---|---|---|
| 7.4+ | Structurally validated | [Open version 7.4](zabbix-7.4/README.md#english) |

The template distinguishes available official data, conditional fields, and capabilities not yet exposed by the API. A missing metric is never converted into a fabricated healthy state.
