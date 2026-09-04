# Implantação / Deployment

[Português](#português) · [English](#english)

## Português

### Pré-requisitos

- Zabbix Server ou Proxy 7.4+ com saída HTTPS para `api.ui.com:443`;
- quantidade suficiente de HTTP Agent pollers;
- API key do Site Manager com acesso de leitura aos consoles e aplicações;
- consoles compatíveis com Cloud Connector (firmware 5.0.3 ou superior para o conector atual).

### Instalação

```bash
git clone https://github.com/danielrc10/zabbix-template-unifi-site-manager.git /opt/zabbix-template-unifi-site-manager
cd /opt/zabbix-template-unifi-site-manager
ruby zabbix-7.4/tools/validate_template.rb
```

Na GUI do Zabbix:

1. Importe `zabbix-7.4/template/template_unifi_site_manager.yaml`.
2. Crie um host lógico sem interface.
3. Vincule `Template UniFi Site Manager`.
4. Defina `{$UNIFI.API.KEY}` no host como **Texto secreto**.
5. Defina os valores de WAN e execute as regras LLD.

Nunca grave a chave no template, no repositório ou em uma macro visível. Se vários hosts usarem a mesma conta, avalie um provedor de secrets compatível com Zabbix.

### Teste seguro da chave

Execute a partir do mesmo Zabbix Server/Proxy, fornecendo a chave de forma interativa ou por um secret manager. O retorno deve ter `httpStatusCode: 200` e um array `data`:

```bash
curl --fail-with-body \
  -H 'Accept: application/json' \
  -H "X-API-Key: $UNIFI_API_KEY" \
  'https://api.ui.com/v1/hosts?pageSize=1'
```

Não coloque a chave diretamente na linha de comando, pois ela pode aparecer no histórico e na lista de processos.

### Extensão SNMP opcional

Importe `template/template_unifi_site_manager_snmp_extension.yaml` somente se desejar telemetria local adicional. Vincule `Template UniFi Site Manager - SNMP Extension` aos hosts individuais que possuam interface SNMP alcançável. Não o vincule ao host lógico da conta Site Manager.

Consulte [SNMP-EXTENSION.md](SNMP-EXTENSION.md) para OIDs, limitações e macros com contexto.

### Dimensionamento

As LLDs suportadas reutilizam uma única coleta de inventário. Em contas grandes:

- aumente `{$UNIFI.INTERVAL.INVENTORY}` de `1h` para `3h` ou `6h`;
- ajuste desempenho e configuração independentemente da disponibilidade;
- monitore a fila dos HTTP Agent pollers;
- respeite 100 requisições/minuto por console;
- monitore a fila de preprocessors e o tamanho do inventário unificado;
- consulte [SCALING.md](SCALING.md) antes de dividir contas.

## English

Requirements are Zabbix Server/Proxy 7.4+ with HTTPS egress to `api.ui.com:443`, enough HTTP Agent pollers, a read-capable Site Manager API key, and consoles supported by Cloud Connector.

Clone the repository, run both validators, import the primary YAML, create an interface-less logical host, link `Template UniFi Site Manager`, and configure `{$UNIFI.API.KEY}` as a secret host macro. Never commit the key or place it directly on a shell command line.

The optional `Template UniFi Site Manager - SNMP Extension` belongs on individual reachable device hosts, never on the logical API host. For large estates, tune inventory and performance independently and follow [SCALING.md](SCALING.md).
