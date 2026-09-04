# SNMP Extension

[Português](#português) · [English](#english)

## Português

`Template UniFi Site Manager - SNMP Extension` é um complemento opcional. O monitoramento principal continua sendo feito remotamente pelo `Template UniFi Site Manager` e pela API oficial `api.ui.com`.

Use a extensão apenas quando o Zabbix Server ou Proxy conseguir alcançar o IP de gerenciamento do equipamento em UDP/161. Crie ou use um host individual para cada equipamento e configure nele uma interface SNMP v2c ou v3. A extensão não deve ser vinculada ao host lógico sem interface usado para a conta Site Manager.

### O que acrescenta

- disponibilidade do agente SNMP;
- IP, modelo, versão, uplink e uptime do UI-MIB;
- isolamento de AP;
- interfaces IF-MIB: estado administrativo/operacional, velocidade, tráfego, erros e descartes;
- rádios: utilização total, RX/TX próprio e interferência de outros BSS;
- VAP/SSID: clientes, CCQ, canal, potência, tráfego, erros, descartes e retries.

O alarme de interface caída fica desativado por padrão com `{$UNIFI.SNMP.IFCONTROL}=0`. Habilite somente interfaces críticas usando macro com contexto, por exemplo:

```text
{$UNIFI.SNMP.IFCONTROL:"eth0"} = 1
```

### Limites

- A documentação oficial informa que USW Flex e Ultra não suportam SNMP.
- A Ubiquiti ainda não oferece SNMP traps; a extensão faz polling.
- O UI-MIB oficial é incompleto e voltado principalmente aos APs; alguns OIDs podem ficar unsupported em gateways e switches.
- O UI-MIB não contém objetos de disco, SMART, temperatura de disco ou RAID. A extensão não fabrica essas métricas.

Fonte e download do UI-MIB: [SNMP Monitoring in UniFi Network](https://help.ui.com/hc/en-us/articles/33502980942615-SNMP-Monitoring-in-UniFi-Network).

## English

`Template UniFi Site Manager - SNMP Extension` is optional enrichment. The primary `Template UniFi Site Manager` continues to monitor the estate remotely through `api.ui.com`.

Apply the extension to individual device hosts with reachable UDP/161 SNMP interfaces, not to the interface-less logical Site Manager host. It adds IF-MIB interface telemetry and UI-MIB AP/radio/VAP metrics. Interface-down alarms are disabled by default and should be enabled only with context macros for critical links.

The official UI-MIB is incomplete and has no disk, SMART, disk temperature, or RAID objects. Ubiquiti also documents polling only; SNMP traps are not currently available.
