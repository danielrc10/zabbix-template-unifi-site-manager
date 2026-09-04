# Dimensionamento e frequências / Scaling and intervals

[Português](#português) · [English](#english)

## Português

O número de itens não equivale ao número de chamadas externas. Itens dependentes processam o valor de um mestre sem consultar novamente a API. O projeto separa quatro custos: chamadas HTTP, processamento JavaScript, cardinalidade descoberta e histórico no banco.

### Classes de coleta

| Classe | Padrão | Conteúdo |
|---|---:|---|
| Disponibilidade | `1m` | Site Manager, consoles, Network e Protect |
| Estado | `2m` | sites, dispositivos, WANs, câmeras, sensores, Alarm Hubs e NVR |
| Desempenho | `5m` | ISP, clientes, VPN, CPU, RAM e estatísticas |
| Capacidade | `15m` | DHCP e armazenamento condicional |
| Configuração | `15m` | redes, Wi-Fi, ACL/firewall e auditoria |
| Inventário | `1h` | sites, dispositivos, portas, Protect, WANs, subnets, SSIDs e rádios |

As onze LLDs suportadas pela API consomem o mesmo item `unifi.inventory.raw`. A execução horária consulta cada família de inventário uma vez e entrega arrays separados para as regras dependentes. O placeholder BGP/OSPF permanece desabilitado.

O Protect usa `unifi.protect.status.raw`: a cada dois minutos são feitas quatro consultas de lista por console Protect — câmeras, sensores, Alarm Hubs e NVR. Todos os itens descobertos reutilizam esse JSON; aumentar a quantidade de câmeras ou sensores não multiplica as chamadas operacionais.

Network exige consultas individuais para detalhes e estatísticas de cada equipamento. Elas ficam na classe Desempenho (`5m`), enquanto disponibilidade de console, site e dispositivo usa os inventários globais de `1m`/`2m`. Assim uma conta grande pode aliviar CPU/RAM, portas e estatísticas sem atrasar os alarmes críticos.

Os itens mestre que carregam JSON guardam somente uma hora de histórico. Fontes calculadas que apenas transportam JSON usam histórico zero. Valores numéricos derivados guardam 30 dias de detalhe e 365 dias de trends. Estados estáveis sem alarme por sequência — versão, IP, modo, bateria e estados binários — descartam repetições e gravam apenas mudanças mais um heartbeat periódico. Itens usados para provar indisponibilidade por quatro coletas consecutivas não descartam amostras.

### Ajustes para contas grandes

- Aumente `{$UNIFI.INTERVAL.INVENTORY}` para `3h` ou `6h` quando houver muitos sites, portas ou rádios.
- Aumente `{$UNIFI.INTERVAL.PERFORMANCE}` antes de reduzir a cobertura de disponibilidade.
- Preserve `{$UNIFI.INTERVAL.AVAILABILITY}` em `1m` para detectar API e consoles desligados.
- Não execute manualmente várias descobertas: todas recebem o mesmo inventário automaticamente.
- Observe a fila de pollers HTTP e preprocessors, o tamanho do item `unifi.inventory.raw` e respostas HTTP 429.

O Cloud Connector documenta limite de 100 requisições por minuto por console, timeout de 25 segundos e resposta máxima de 10 MB. O inventário unificado usa paginação e guardas de segurança; se atingir os limites, o item deixa de atualizar e o alerta de inventário sem dados é acionado.

## English

Item count is not request count. Dependent items reuse a master value without another API call. The project separates availability (`1m`), state (`2m`), performance (`5m`), capacity/configuration (`15m`), and unified inventory (`1h`).

Eleven supported LLD rules reuse `unifi.inventory.raw`. Protect uses four consolidated list requests per console for cameras, sensors, Alarm Hubs, and NVR rather than one request per discovered entity. Raw JSON masters retain one hour, transport-only calculated items retain no history, and numeric derived data retains 30 days plus 365 days of trends.

For large estates, increase the inventory interval first, then the performance interval. Keep one-minute availability whenever possible and monitor HTTP/preprocessing queues, inventory payload size, and HTTP 429 responses.
