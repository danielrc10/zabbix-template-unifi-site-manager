# UniFi Site Manager — Zabbix 7.4+

[Português](#português) · [English](#english)

> API oficial `api.ui.com` · HTTP Agent assíncrono · inventário unificado · JavaScript LLD · extensão SNMP opcional

## Português

Este template monitora uma conta UniFi inteira a partir de um único host lógico do Zabbix. O Zabbix Server ou Proxy consulta o Site Manager e usa o Cloud Connector oficial para encaminhar consultas somente leitura às aplicações Network e Protect de cada console.

### Arquitetura API-first

```text
Host lógico no Zabbix
├── HTTP Agent → disponibilidade, sites, dispositivos, ISP e Cloud Connector
├── inventário unificado a cada 1h → uma única varredura multi-console
├── JavaScript LLD dependente → reaproveita o inventário sem novas chamadas
├── Protect consolidado → quatro listas por console, não uma chamada por entidade
└── itens dependentes → extraem dezenas de métricas sem tráfego adicional
```

O Cloud Connector limita cada console a 100 requisições por minuto, encerra uma consulta após 25 segundos e limita a resposta a 10 MB. O template separa disponibilidade, estado, desempenho, capacidade, configuração e inventário para evitar tratar tudo como uma coleta de um minuto.

A extensão `Template UniFi Site Manager - SNMP Extension` é um complemento independente para hosts físicos alcançáveis por SNMP. O template principal não precisa de VPN, rota privada nem Zabbix Proxy no site.

### Arquivos

- [Template YAML importável](template/template_unifi_site_manager.yaml)
- [Extensão SNMP importável](template/template_unifi_site_manager_snmp_extension.yaml)
- [JavaScript completo da LLD unificada de Sites](javascript/site_discovery.js)
- [Gerador determinístico](tools/generate_template.rb)
- [Gerador da extensão SNMP](tools/generate_snmp_extension.rb)
- [Validador estrutural e de JavaScript](tools/validate_template.rb)
- [Validador da extensão SNMP](tools/validate_snmp_extension.rb)
- [Dimensionamento e frequências](SCALING.md)
- [Guia da extensão SNMP](SNMP-EXTENSION.md)
- [Guia de implantação](DEPLOYMENT.md)

### Configuração

1. Crie um host sem interface, por exemplo `UniFi Site Manager`.
2. Importe e vincule `Template UniFi Site Manager`.
3. No host, defina `{$UNIFI.API.KEY}` como macro secreta com a chave criada no Site Manager.
4. Configure as velocidades contratadas de WAN1/WAN2. Valor `0` desativa o limiar de Speedtest.
5. Execute as descobertas e confirme quais campos sua versão das aplicações realmente publica.

| Macro | Padrão | Finalidade |
|---|---:|---|
| `{$UNIFI.API.KEY}` | vazio/secret | Chave da conta; nunca grave no Git |
| `{$UNIFI.API.URL}` | `https://api.ui.com` | Endpoint oficial |
| `{$UNIFI.INTERVAL.AVAILABILITY}` | `1m` | API, console e aplicações |
| `{$UNIFI.INTERVAL.STATUS}` | `2m` | Sites, dispositivos, WAN e estado do Protect |
| `{$UNIFI.INTERVAL.PERFORMANCE}` | `5m` | ISP, clientes, VPN e estatísticas |
| `{$UNIFI.INTERVAL.CAPACITY}` | `15m` | DHCP e armazenamento condicional |
| `{$UNIFI.INTERVAL.CONFIG}` | `15m` | Configuração e auditoria |
| `{$UNIFI.INTERVAL.INVENTORY}` | `1h` | Inventário compartilhado por onze LLDs |
| `{$UNIFI.API.NODATA}` | `5m` | Janela sem resposta da API |
| `{$UNIFI.DATA.MAX.AGE}` | `30m` | Idade máxima do inventário retornado |
| `{$UNIFI.INVENTORY.NODATA}` | `2h` | Inventário unificado sem atualização |
| `{$UNIFI.ISP.DATA.MAX.AGE}` | `15m` | Idade máxima das métricas ISP |
| `{$UNIFI.BACKUP.MAX.AGE}` | `7d` | Idade máxima do backup do console |
| `{$WAN.LATENCY.WARN}` | `100` | Latência WAN em ms |
| `{$WAN.PACKETLOSS.WARN}` | `5` | Perda WAN em % |
| `{$WAN1.EXPECTED.DL}` / `{$WAN1.EXPECTED.UL}` | `0` | Mbps esperados na WAN1 |
| `{$WAN2.EXPECTED.DL}` / `{$WAN2.EXPECTED.UL}` | `0` | Mbps esperados na WAN2 |
| `{$WAN.SPEED.THRESHOLD.PCT}` | `70` | Percentual mínimo do Speedtest |
| `{$DHCP.THRESHOLD.PCT}` | `90` | Uso estimado do pool DHCP |
| `{$TEMP.MAX.WARN}` | `55` | Temperatura máxima em °C |
| `{$WIFI.TX.RETRIES.WARN}` | `20` | Retransmissões Wi-Fi em % |
| `{$PROTECT.SENSOR.BATTERY.MIN}` | `20` | Carga mínima da bateria do sensor em % |
| `{$PROTECT.SENSOR.SIGNAL.MIN}` | `20` | Qualidade mínima do sinal do sensor em % |
| `{$PROTECT.EVENT.WINDOW}` | `10m` | Janela de alarme para evento de vazamento/violação |

### Descobertas

O template contém as dez LLDs solicitadas e três LLDs adicionais para consoles, sensores Protect e Alarm Hubs. Onze delas são dependentes do mesmo `unifi.inventory.raw`; somente o placeholder BGP/OSPF permanece desabilitado e sem chamadas:

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
11. consoles e disponibilidade das aplicações;
12. sensores Protect;
13. Protect Alarm Hubs.

A LLD de Sites correlaciona o inventário global com os IDs UUID locais do Network. O parser aceita tanto a resposta plana atual quanto estruturas `independentSites` + `fabrics`. Em 2 de setembro de 2026, o contrato público do Site Manager não inclui associação de Fabric na resposta de `/v1/sites`; portanto `{#SITE.TYPE}` só será `Fabric` quando a API realmente fornecer um `fabricId`. Caso contrário, o valor correto e seguro é `Independent`.

### Cobertura real da API oficial

| Área | Coletado agora | Condicional/limitação oficial |
|---|---|---|
| API e consoles | HTTP/API, ausência de dados, bloqueio remoto, conexão do console, Network/Protect API | Aplicação só é alarmada se o console a anunciar |
| Sites | disponibilidade do UCG/console, total/offline por categoria, clientes, convidados, WAN uptime, ISP, IPS e notificações | “Site offline” segue o console em `/v1/hosts`; não é inferido pela contagem de dispositivos |
| Dispositivos | estado detalhado, online, IP, firmware atual/disponível, uptime, CPU, RAM e clientes | temperatura e USP-RPS não fazem parte do schema garantido |
| Switch | link, velocidade, velocidade máxima, capacidade/estado PoE | nome configurado, VLAN operacional e watts não são garantidos |
| Protect | conexão das câmeras; sensores com bateria, sinal, temperatura, umidade, luz, abertura, movimento, vazamento e tamper; Alarm Hub; armamento/breach do NVR | stream loss separado, gravação ativa/modo, discos, SMART e RAID não são publicados |
| WAN/ISP | interfaces, disponibilidade primária, latência média/máxima, perda, throughput, uptime/downtime, ISP/ASN e frescor | prioridade ativa e Speedtest interno não são publicados no endpoint WAN comum |
| Segurança | contagem e hash canônico de ACL, ordenação, políticas/zonas de firewall, DNS, listas de tráfego, LAG, MC-LAG e switch stacks | não abrange famílias legadas que não estão nos endpoints oficiais atuais |
| DHCP | range configurado e percentual de endereços atualmente observados nos clientes conectados | não é a tabela de leases: clientes desconectados com lease válido não aparecem e IPs estáticos podem aparecer; por isso o valor é uma estimativa |
| Wi-Fi | SSIDs, rádios, TX retries e clientes por uplink/AP | SSID/banda por cliente, experience e airtime não são publicados |
| BGP/OSPF | não monitorado pela API oficial; a LLD obrigatória permanece desabilitada e não descobre entidades | a API Network publicada não oferece endpoint de vizinhos, estado de adjacência, flaps ou contagem de rotas |

Campos condicionais usam pré-processamento que gera estado `unsupported` quando ausentes. Isso é deliberado: retornar zero criaria falsos alarmes ou, pior, falsa saúde.

#### Como interpretar o DHCP estimado

O endpoint oficial lista **clientes conectados**, não todos os leases concedidos pelo servidor DHCP. O template cruza os IPs desses clientes com o início e o fim do pool. Por exemplo: em um pool com 101 endereços, se 30 endereços forem vistos entre os clientes conectados, o item mostrará aproximadamente `29,7%`.

Esse número não é a ocupação real do servidor DHCP: um notebook desligado ainda pode conservar um lease válido e não aparecer na lista; um cliente com IP estático dentro do intervalo pode aparecer sem consumir lease. Consequentemente, o alerta ajuda a indicar concentração de clientes ativos, mas pode não detectar a exaustão real do pool. A medição exata exige uma tabela de leases que a API oficial publicada atualmente não oferece.

#### O que significa a LLD de BGP/OSPF desabilitada

Ela não realiza coleta nem cria itens para peers. Foi mantida somente para deixar explícita a LLD exigida no escopo original, sem fingir que há cobertura. A API Network oficial publicada atualmente não disponibiliza vizinhos BGP/OSPF, estado de adjacência, flaps ou quantidade de rotas. Para monitorar esses dados de verdade é necessário acrescentar outra fonte, como coleta local/SSH no gateway ou telemetria externa; isso fica fora da solução baseada exclusivamente na API oficial do Site Manager.

### Alertas adicionais recomendados e incluídos

- API inacessível, resposta de erro, chave/permissão inválida, rate limit, dados antigos, páginas truncadas e ausência de dados;
- console desconectado ou com acesso remoto bloqueado;
- backup do console antigo quando `latestBackupTime` estiver disponível;
- Network/Protect inacessível por console;
- UCG/console associado ao site desconectado por duas coletas consecutivas (por exemplo, desligado da tomada);
- sensor Protect ou Alarm Hub offline, bateria crítica/baixa, sinal fraco, vazamento e violação física;
- estado `breach` no armamento do NVR;
- latência, perda de pacotes, problema de Internet e métricas ISP antigas;
- alteração do modo IPS e contagem de assinaturas;
- notificações críticas abertas;
- alteração canônica de ACL/firewall;
- dispositivos offline, reboot e firmware pendente;
- indisponibilidade agregada de Internet e VPNs inventariadas.

Também é recomendável criar alarmes de orçamento PoE, capacidade total do NVR, detecções de segurança, versão do aplicativo e expiração da API key assim que esses valores forem publicados de forma estável pelos endpoints oficiais.

### Validação

```bash
ruby zabbix-7.4/tools/generate_template.rb
ruby zabbix-7.4/tools/generate_snmp_extension.rb
ruby zabbix-7.4/tools/validate_template.rb
ruby zabbix-7.4/tools/validate_snmp_extension.rb
```

O validador confere YAML, UUIDs, macros, masters dependentes, TLS, HTTP Agents, dez LLDs obrigatórias, prioridades e sintaxe JavaScript. A validação definitiva continua sendo importar o arquivo em uma instalação de homologação com o mesmo patch do Zabbix 7.4 usado em produção e testar com uma API key de leitura.

Fontes oficiais: [Site Manager API](https://developer.ui.com/site-manager/v1.0.0/gettingstarted), [Network API 10.4.57](https://developer.ui.com/network/v10.4.57/gettingstarted), [Protect API 7.2.105](https://developer.ui.com/protect/v7.2.105/gettingstarted) e [SNMP no UniFi Network](https://help.ui.com/hc/en-us/articles/33502980942615-SNMP-Monitoring-in-UniFi-Network).

---

## English

This template monitors a complete UniFi account from one logical Zabbix host. Zabbix Server or Proxy polls Site Manager and uses the official Cloud Connector to forward read-only requests to every console's Network and Protect applications.

Asynchronous HTTP Agent items collect operational payloads. One hourly unified inventory feeds eleven dependent JavaScript LLD rules, and one consolidated Protect collector replaces per-entity polling. Configure `{$UNIFI.API.KEY}` as a secret host macro, set the expected WAN bandwidth, run discovery, and verify the fields published by your application versions.

The optional `Template UniFi Site Manager - SNMP Extension` adds reachable-device IF-MIB and UI-MIB telemetry. It never replaces the primary API template and is not required for remote monitoring.

The ten requested discovery rules plus console, Protect sensor, and Alarm Hub discovery are included. The Sites parser supports the current flat response and forward-compatible `independentSites`/`fabrics` shapes. The current public `/v1/sites` contract does not expose Fabric membership, so a site is classified as `Fabric` only when an actual fabric identifier is present.

The capability table above is equally applicable in English: unavailable official fields become unsupported or an empty disabled discovery, never a fabricated healthy value. Validate the YAML locally, then import it into a staging Zabbix 7.4 instance before production use.
