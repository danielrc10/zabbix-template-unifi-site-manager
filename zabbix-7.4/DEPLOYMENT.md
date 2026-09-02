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
git clone https://github.com/danielrc10/zabbix.git /opt/zabbix-community
cd /opt/zabbix-community
ruby templates/unifi-site-manager/zabbix-7.4/tools/validate_template.rb
```

Na GUI do Zabbix:

1. Importe `templates/unifi-site-manager/zabbix-7.4/template/template_unifi_site_manager.yaml`.
2. Crie um host lógico sem interface.
3. Vincule `Template UniFi Site Manager by HTTP`.
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

### Dimensionamento

As LLDs percorrem consoles, sites e dispositivos. Em contas grandes:

- aumente a descoberta de `1h` para `3h` ou `6h`;
- monitore a fila dos HTTP Agent pollers;
- respeite 100 requisições/minuto por console;
- evite executar todas as LLDs manualmente ao mesmo tempo;
- divida contas muito grandes em hosts lógicos separados.

## English

Requirements are Zabbix Server/Proxy 7.4+ with HTTPS egress to `api.ui.com:443`, enough HTTP Agent pollers, a read-capable Site Manager API key, and consoles supported by Cloud Connector.

Clone the repository, run the validator, import the YAML, create an interface-less logical host, link the template, and configure `{$UNIFI.API.KEY}` as a secret host macro. Never commit the key or place it directly on a shell command line. For large estates, increase the LLD interval, watch HTTP Agent queues, respect the 100 requests/minute per-console limit, and split collection when necessary.
