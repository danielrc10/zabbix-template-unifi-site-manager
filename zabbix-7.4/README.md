# UniFi Site Manager — Zabbix 7.4+

[Português](#português) · [English](#english)

> API oficial `api.ui.com` · HTTP Agent assíncrono · JavaScript LLD · Network · Protect

## Português

Este template monitora uma conta UniFi inteira a partir de um único host lógico do Zabbix. O Zabbix Server ou Proxy consulta o Site Manager e usa o Cloud Connector oficial para encaminhar consultas somente leitura às aplicações Network e Protect de cada console.

### Arquitetura

```text
Host lógico no Zabbix
├── HTTP Agent → /v1/hosts, /v1/sites, /v1/devices e /v1/isp-metrics
├── JavaScript LLD → enumera consoles e entidades de todas as aplicações
└── HTTP Agent prototypes → Cloud Connector → Network / Protect
```

O Cloud Connector limita cada console a 100 requisições por minuto, encerra uma consulta após 25 segundos e limita a resposta a 10 MB. Para ambientes grandes, aumente `{$UNIFI.DISCOVERY.INTERVAL}` e distribua a coleta em proxies/hosts separados se necessário.

### Arquivos

- [Template YAML importável](template/template_unifi_site_manager.yaml)
- [JavaScript completo da LLD unificada de Sites](javascript/site_discovery.js)
- [Gerador determinístico](tools/generate_template.rb)
- [Validador estrutural e de JavaScript](tools/validate_template.rb)
- [Guia de implantação](DEPLOYMENT.md)

### Configuração

1. Crie um host sem interface, por exemplo `UniFi Site Manager`.
2. Importe e vincule `Template UniFi Site Manager by HTTP`.
3. No host, defina `{$UNIFI.API.KEY}` como macro secreta com a chave criada no Site Manager.
4. Configure as velocidades contratadas de WAN1/WAN2. Valor `0` desativa o limiar de Speedtest.
5. Execute as descobertas e confirme quais campos sua versão das aplicações realmente publica.

| Macro | Padrão | Finalidade |
|---|---:|---|
| `{$UNIFI.API.KEY}` | vazio/secret | Chave da conta; nunca grave no Git |
| `{$UNIFI.API.URL}` | `https://api.ui.com` | Endpoint oficial |
| `{$UNIFI.INTERVAL}` | `5m` | Coleta regular |
| `{$UNIFI.DISCOVERY.INTERVAL}` | `1h` | LLD multi-console |
| `{$UNIFI.API.NODATA}` | `15m` | Janela sem resposta da API |
| `{$UNIFI.DATA.MAX.AGE}` | `30m` | Idade máxima do inventário retornado |
| `{$UNIFI.BACKUP.MAX.AGE}` | `7d` | Idade máxima do backup do console |
| `{$WAN1.EXPECTED.DL}` / `{$WAN1.EXPECTED.UL}` | `0` | Mbps esperados na WAN1 |
| `{$WAN2.EXPECTED.DL}` / `{$WAN2.EXPECTED.UL}` | `0` | Mbps esperados na WAN2 |
| `{$WAN.SPEED.THRESHOLD.PCT}` | `70` | Percentual mínimo do Speedtest |
| `{$DHCP.THRESHOLD.PCT}` | `90` | Uso estimado do pool DHCP |
| `{$TEMP.MAX.WARN}` | `55` | Temperatura máxima em °C |

### Descobertas

O template contém as dez LLDs solicitadas e uma LLD adicional de consoles:

1. Sites (`{#SITE.ID}`, `{#SITE.NAME}`, `{#SITE.TYPE}`);
2. dispositivos Network;
3. portas de switch;
4. câmeras Protect;
5. discos/armazenamento;
6. links WAN;
7. roteamento dinâmico;
8. subnets/DHCP;
9. SSIDs;
10. rádios de AP;
11. consoles e disponibilidade das aplicações.

A LLD de Sites correlaciona o inventário global com os IDs UUID locais do Network. O parser aceita tanto a resposta plana atual quanto estruturas `independentSites` + `fabrics`. Em 2 de setembro de 2026, o contrato público do Site Manager não inclui associação de Fabric na resposta de `/v1/sites`; portanto `{#SITE.TYPE}` só será `Fabric` quando a API realmente fornecer um `fabricId`. Caso contrário, o valor correto e seguro é `Independent`.

### Cobertura real da API oficial

| Área | Coletado agora | Condicional/limitação oficial |
|---|---|---|
| API e consoles | HTTP/API, ausência de dados, bloqueio remoto, conexão do console, Network/Protect API | Aplicação só é alarmada se o console a anunciar |
| Sites | total/offline de dispositivos, clientes, updates e notificações críticas | “Site offline” é derivado quando todos os dispositivos estão offline |
| Dispositivos | online, uptime, CPU, RAM, firmware, clientes por uplink/AP | temperatura e USP-RPS não fazem parte do schema garantido |
| Switch | link, velocidade, velocidade máxima, capacidade/estado PoE | nome configurado, VLAN operacional e watts não são garantidos |
| Protect | conexão da câmera | stream loss separado, gravação ativa/modo, discos, SMART e RAID não são publicados |
| WAN/ISP | interfaces, uptime/downtime agregado, latência, perda e throughput | IP público, prioridade ativa e Speedtest interno não são publicados |
| Segurança | total e hash canônico das regras ACL oficiais | não abrange famílias legadas de regras que não estão no endpoint ACL |
| DHCP | range configurado e ocupação estimada por clientes conectados | não existe endpoint oficial de leases; o item é identificado como estimativa |
| Wi-Fi | SSIDs, rádios, TX retries e clientes por uplink/AP | SSID/banda por cliente, experience e airtime não são publicados |
| BGP/OSPF | LLD desabilitada e explicitamente vazia | não existe endpoint oficial para peers, flaps ou rotas |

Campos condicionais usam pré-processamento que gera estado `unsupported` quando ausentes. Isso é deliberado: retornar zero criaria falsos alarmes ou, pior, falsa saúde.

### Alertas adicionais recomendados e incluídos

- API inacessível, resposta de erro, chave/permissão inválida, rate limit, dados antigos, páginas truncadas e ausência de dados;
- console desconectado ou com acesso remoto bloqueado;
- backup do console antigo quando `latestBackupTime` estiver disponível;
- Network/Protect inacessível por console;
- site integralmente offline;
- notificações críticas abertas;
- alteração canônica de ACL/firewall;
- dispositivos offline, reboot e firmware pendente;
- indisponibilidade agregada de Internet e VPNs inventariadas.

Também é recomendável criar alarmes de orçamento PoE, capacidade total do NVR, detecções de segurança, versão do aplicativo e expiração da API key assim que esses valores forem publicados de forma estável pelos endpoints oficiais.

### Validação

```bash
ruby templates/unifi-site-manager/zabbix-7.4/tools/generate_template.rb
ruby templates/unifi-site-manager/zabbix-7.4/tools/validate_template.rb
```

O validador confere YAML, UUIDs, macros, masters dependentes, TLS, HTTP Agents, dez LLDs obrigatórias, prioridades e sintaxe JavaScript. A validação definitiva continua sendo importar o arquivo em uma instalação de homologação com o mesmo patch do Zabbix 7.4 usado em produção e testar com uma API key de leitura.

Fontes oficiais: [Site Manager API](https://developer.ui.com/site-manager/v1.0.0/gettingstarted), [Network API 10.0.162](https://developer.ui.com/network/v10.0.162/gettingstarted), [Protect API 7.2.105](https://developer.ui.com/protect/v7.2.105/gettingstarted).

---

## English

This template monitors a complete UniFi account from one logical Zabbix host. Zabbix Server or Proxy polls Site Manager and uses the official Cloud Connector to forward read-only requests to every console's Network and Protect applications.

Asynchronous HTTP Agent items collect raw payloads; JavaScript LLD rules enumerate the estate and dependent items extract metrics. Configure `{$UNIFI.API.KEY}` as a secret host macro, set the expected WAN bandwidth, run discovery, and verify the fields published by your application versions.

The ten requested discovery rules plus console discovery are included. The Sites parser supports the current flat response and forward-compatible `independentSites`/`fabrics` shapes. The current public `/v1/sites` contract does not expose Fabric membership, so a site is classified as `Fabric` only when an actual fabric identifier is present.

The capability table above is equally applicable in English: unavailable official fields become unsupported or an empty disabled discovery, never a fabricated healthy value. Validate the YAML locally, then import it into a staging Zabbix 7.4 instance before production use.
