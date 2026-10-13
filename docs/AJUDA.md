# Ajuda do AIquota

## Lendo os indicadores

`83%⁵ʰ 42%⁷ᵈ` significa que 83% do limite de 5 horas e 42% do limite semanal ainda estão **disponíveis**
(você pode trocar para **consumido** em Configurações → Geral). A barra ou o anel mostra o mesmo número.

- Barra neutra: mais de 20% disponível.
- Âmbar suave: 20% ou menos. Vermelho suave: abaixo de 10%. (Limites e cores são configuráveis.)
- Número esmaecido: os dados têm mais de 3 horas.
- `–`: ainda não há dados confiáveis, ou a janela foi renovada e os dados novos ainda não chegaram.

## Movendo os indicadores

**Segure ⌘ Command e arraste um indicador do AIquota para colocá-lo ao lado do seu app de IA.**

O macOS lembra a posição de cada indicador quando possível. O AIquota não consegue posicioná-los
automaticamente — a ordem da barra de menus é controlada pelo macOS — e nunca move ícones de outros apps.
Se um indicador sumir, a barra pode estar cheia (em Macs com notch, itens podem ficar escondidos atrás dele).

## Claude mostra "Aguardando dados" ou "–"

1. Mantenha o app Claude aberto — ele registra o uso do plano a cada ~5 minutos; ou
2. Ative a **integração com a status line** (Configurações → Provedores → Claude Code → Ativar…). Após a
   próxima resposta do Claude Code no terminal, o AIquota recebe os números exatos e os horários de renovação.

Os limites só são informados para os planos Claude.ai Pro e Max.

## Codex mostra "Não instalado" ou "Sem login"

O AIquota procura o comando `codex` no PATH, em pastas comuns e dentro do ChatGPT para Mac. Defina um
caminho em Configurações → Provedores se necessário. Os limites de assinatura exigem login no Codex com
ChatGPT; logins com chave de API não têm limites de 5 horas/semanais.

## Removendo a integração da status line

Configurações → Provedores → Claude Code → **Remover**. Sua status line anterior é restaurada exatamente.
Um backup completo do `settings.json` fica em `~/Library/Application Support/AIquota/claude/`.

## Desinstalando

1. Remova a integração da status line, se ativada.
2. Encerre o AIquota (popover → botão de desligar) e apague `/Applications/AIquota.app`.
3. Opcional: apague `~/Library/Application Support/AIquota` e execute `defaults delete app.aiquota.AIquota`.
