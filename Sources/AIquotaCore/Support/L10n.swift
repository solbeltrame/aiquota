import Foundation

/// Minimal in-code localization. English strings are the keys; other languages map them.
///
/// Kept in Swift (instead of .lproj bundles) so the app works the same from `swift run` and from the
/// bundled .app, and so adding a language is a single, reviewable file change.
/// To add a language: add a case to `AppLanguage` and a dictionary below.
public enum L10n {
    nonisolated(unsafe) public static var language: AppLanguage = .system

    public static var resolvedLanguage: AppLanguage {
        guard language == .system else { return language }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("pt") ? .portugueseBR : .english
    }

    public static var locale: Locale {
        switch resolvedLanguage {
        case .portugueseBR: return Locale(identifier: "pt_BR")
        case .english: return Locale(identifier: "en_US")
        case .system: return .current
        }
    }

    public static func t(_ key: String) -> String {
        switch resolvedLanguage {
        case .portugueseBR: return portugueseBR[key] ?? key
        case .english, .system: return key
        }
    }

    public static let portugueseBR: [String: String] = [
        "%@: %@ below %d%%": "%@: %@ abaixo de %d%%",
        "%@: %@ renewed": "%@: %@ renovado",
        "%@: reset expiring soon": "%@: reset expirando em breve",
        "%d%% of the %@ limit is still available.": "%d%% do %@ ainda está disponível.",
        "5-hour limit": "Limite de 5 horas",
        "5-hour window renewed": "Janela de 5 horas renovada",
        "5h and 7d": "5h e 7d",
        "5h only": "Somente 5h",
        "7d only": "Somente 7d",
        "A saved reset expires %@. Use it in %@ if you need it.": "Um reset guardado expira %@. Use-o no %@ se precisar.",
        "AIquota Settings": "Configurações do AIquota",
        "AIquota is independent and not affiliated with OpenAI or Anthropic. Codex, ChatGPT, Claude and Claude Code are trademarks of their respective owners.":
            "O AIquota é independente e não tem vínculo com a OpenAI ou a Anthropic. Codex, ChatGPT, Claude e Claude Code são marcas de seus respectivos donos.",
        "AIquota keeps the remaining 5-hour and weekly limits of your AI coding tools in the menu bar, so you never have to open a dashboard.":
            "O AIquota mantém na barra de menus os limites restantes de 5 horas e semanais das suas ferramentas de IA, sem precisar abrir dashboards.",
        "AIquota never shows an estimated number. Indicators show “–” until a source reports real values.":
            "O AIquota nunca mostra números estimados. Os indicadores exibem “–” até uma fonte informar valores reais.",
        "AIquota updates as soon as local activity is detected. This interval is only the fallback while you are active; when idle it slows down to save energy. Each provider enforces its own safe minimum.":
            "O AIquota atualiza assim que detecta atividade local. Este intervalo é apenas a alternativa enquanto você está ativo; em inatividade ele desacelera para economizar energia. Cada provedor aplica seu próprio mínimo seguro.",
        "About": "Sobre",
        "Alert colors always follow the available percentage, even when showing used.":
            "As cores de alerta sempre seguem o percentual disponível, mesmo exibindo o consumido.",
        "Allow notifications…": "Permitir notificações…",
        "Allowed": "Permitidas",
        "Allow…": "Permitir…",
        "Also color the numbers": "Colorir também os números",
        "Appearance": "Aparência",
        "Apply": "Aplicar",
        "Approve AIquota in System Settings → General → Login Items.": "Aprove o AIquota em Ajustes do Sistema → Geral → Itens de Início.",
        "Available %": "% disponível",
        "Available below %d%%": "Disponível abaixo de %d%%",
        "Back": "Voltar",
        "Bar thickness": "Espessura da barra",
        "Bars turn amber at 20% and red below 10%. Change the style in Settings → Appearance.":
            "As barras ficam âmbar em 20% e vermelhas abaixo de 10%. Mude o estilo em Configurações → Aparência.",
        "Cancel": "Cancelar",
        "Caution at %d%% available or less": "Atenção com %d%% disponível ou menos",
        "Caution": "Atenção",
        "Claude Code status line": "Status line do Claude Code",
        "Claude app usage history": "Histórico de uso do app Claude",
        "Codex App Server (official) + local session activity": "Codex App Server (oficial) + atividade local das sessões",
        "Codex App Server": "Codex App Server",
        "Codex CLI path (optional)": "Caminho do Codex CLI (opcional)",
        "Codex session activity": "Atividade das sessões do Codex",
        "Colors": "Cores",
        "Connected": "Conectado",
        "Continue": "Continuar",
        "Contributors": "Contribuidores",
        "Critical below %d%% available": "Crítico abaixo de %d%% disponível",
        "Critical": "Crítico",
        "Data source": "Fonte de dados",
        "Default": "Padrão",
        "Denied": "Negadas",
        "Detected automatically": "Detectado automaticamente",
        "Diagnostics": "Diagnóstico",
        "Disabled": "Desativado",
        "Done": "Concluir",
        "Drag the Codex indicator next to the ChatGPT icon and the Claude indicator next to the Claude icon. macOS remembers the position when possible, but placement is controlled by macOS and cannot be guaranteed automatically.":
            "Arraste o indicador do Codex para perto do ícone do ChatGPT e o do Claude para perto do ícone do Claude. O macOS lembra a posição quando possível, mas o posicionamento é controlado pelo macOS e não pode ser garantido automaticamente.",
        "Each alert is sent once per window. macOS Focus modes are respected.": "Cada alerta é enviado uma vez por janela. Os modos de Foco do macOS são respeitados.",
        "Each tool has its own indicator in the menu bar. The big number is what is left; the tiny 5h and 7d mark the window.":
            "Cada ferramenta tem seu próprio indicador na barra de menus. O número grande é o que resta; os pequenos 5h e 7d indicam a janela.",
        "Enable the Claude Code status line integration?": "Ativar a integração com a status line do Claude Code?",
        "Enable": "Ativar",
        "Enabled": "Ativada",
        "Enabled. A backup of settings.json was saved in AIquota's support folder.": "Ativada. Um backup do settings.json foi salvo na pasta de suporte do AIquota.",
        "Enable…": "Ativar…",
        "Everything runs on your Mac. AIquota never sends your data anywhere and never spends tokens to check limits.":
            "Tudo roda no seu Mac. O AIquota nunca envia seus dados para lugar nenhum e nunca gasta tokens para consultar limites.",
        "Fallback refresh": "Atualização alternativa",
        "Found on this Mac": "Encontrado neste Mac",
        "Fresh usage confirmed by the latest data.": "Uso renovado confirmado pelos dados mais recentes.",
        "General": "Geral",
        "Gentle alerts": "Alertas discretos",
        "Get a notification when a limit drops below 20%, 10% or 5%, and when a window renews. Each alert is sent once and respects Focus.":
            "Receba uma notificação quando um limite cair abaixo de 20%, 10% ou 5%, e quando uma janela renovar. Cada alerta é enviado uma vez e respeita o Foco.",
        "GitHub repository": "Repositório no GitHub",
        "Hold ⌘ Command and drag to reposition.": "Segure ⌘ Command e arraste para reposicionar.",
        "How to add a provider": "Como adicionar um provedor",
        "How to contribute": "Como contribuir",
        "Indicators": "Indicadores",
        "Label size (5h / 7d)": "Tamanho dos rótulos (5h / 7d)",
        "Language": "Idioma",
        "Last data: %@ (%@)": "Últimos dados: %@ (%@)",
        "Launch at login": "Iniciar com o macOS",
        "Limit": "Limite",
        "Low limits": "Limites baixos",
        "MIT License": "Licença MIT",
        "Manual resets you can use in %@. Separate from the automatic renewal.": "Resets manuais que você pode usar no %@. Separados da renovação automática.",
        "Microbar": "Microbarra",
        "Minimal": "Mínimo",
        "No data yet": "Sem dados ainda",
        "No sign-in is needed: AIquota uses the tools you already have.": "Nenhum login é necessário: o AIquota usa as ferramentas que você já tem.",
        "No usage data yet": "Ainda sem dados de uso",
        "Not found — the indicator will show “–”": "Não encontrado — o indicador mostrará “–”",
        "Not installed": "Não instalado",
        "Not requested": "Não solicitadas",
        "Not signed in": "Sem login",
        "Notifications allowed": "Notificações permitidas",
        "Notifications are turned off for AIquota in System Settings.": "As notificações do AIquota estão desativadas em Ajustes do Sistema.",
        "Notifications are working.": "As notificações estão funcionando.",
        "Notifications need the bundled app (run scripts/build-app.sh).": "As notificações exigem o app empacotado (execute scripts/build-app.sh).",
        "Notifications": "Notificações",
        "Number size": "Tamanho dos números",
        "Off": "Desativada",
        "Official source with reset times. Updates after each Claude Code response in the terminal. Your existing status line keeps working and can be restored at any time.":
            "Fonte oficial com horários de renovação. Atualiza após cada resposta do Claude Code no terminal. Sua status line atual continua funcionando e pode ser restaurada a qualquer momento.",
        "Open Providers settings": "Abrir configurações de provedores",
        "Open System Settings": "Abrir Ajustes do Sistema",
        "Optional. You can change this later.": "Opcional. Você pode mudar isso depois.",
        "Optional: enable the Claude Code status line integration in Settings → Providers for reset times.":
            "Opcional: ative a integração com a status line do Claude Code em Configurações → Provedores para ver horários de renovação.",
        "Permission": "Permissão",
        "Positioning indicators": "Posicionar indicadores",
        "Preview with sample values": "Prévia com valores de exemplo",
        "Preview with your current data": "Prévia com seus dados atuais",
        "Providers": "Provedores",
        "Put them next to your AI apps": "Coloque-os ao lado dos seus apps de IA",
        "Quit AIquota": "Encerrar o AIquota",
        "Read Claude app usage data (unofficial)": "Ler os dados de uso do app Claude (não oficial)",
        "Claude app usage data": "Dados de uso do app Claude",
        "The Claude app refreshes your plan usage about every 5 minutes and keeps it on disk. AIquota reads only the percentages and renewal times from those local files: no credentials, no network. These formats are undocumented and may change.":
            "O app Claude atualiza o uso do seu plano a cada 5 minutos, aproximadamente, e o guarda em disco. O AIquota lê desses arquivos locais apenas os percentuais e os horários de renovação: sem credenciais, sem rede. Esses formatos não são documentados e podem mudar.",
        "Keep the Claude app open for automatic updates. Optional: the Claude Code status line integration in Settings → Providers updates after every response.":
            "Mantenha o app Claude aberto para atualizações automáticas. Opcional: a integração com a status line do Claude Code em Configurações → Provedores atualiza após cada resposta.",
        "Refresh": "Atualizar",
        "Remove": "Remover",
        "Removed. Your previous status line was restored.": "Removida. Sua status line anterior foi restaurada.",
        "Renewal time not reported by this source": "Horário de renovação não informado por esta fonte",
        "Renewals are announced only when new data confirms them, never from the clock alone.":
            "Renovações só são anunciadas quando novos dados as confirmam, nunca apenas pelo relógio.",
        "Renewals": "Renovações",
        "Window renewed since the last reading · waiting for new data": "Janela renovada desde a última leitura · aguardando novos dados",
        "Renewed at %@ · waiting for new data": "Renovado às %@ · aguardando novos dados",
        "Renews %@ · in %@": "Renova %@ · em %@",
        "renews %@ (in %@)": "renova %@ (em %@)",
        "Replaced by another status line": "Substituída por outra status line",
        "Reset": "Reset",
        "Restore defaults": "Restaurar padrões",
        "Revert": "Desfazer",
        "Ring thickness": "Espessura do anel",
        "Ring": "Anel",
        "Same as General": "Igual ao Geral",
        "Sample data": "Dados de exemplo",
        "Saved reset expiring within 3 days": "Reset guardado expirando em até 3 dias",
        "Saved resets": "Resets guardados",
        "Send test": "Enviar teste",
        "Settings…": "Configurações…",
        "Show % sign": "Mostrar símbolo %",
        "Show each AI app's icon": "Mostrar o ícone de cada IA",
        "Useful when the AI app's own menu bar icon is hidden. Uses the icon of the app installed on your Mac.":
            "Útil quando o ícone original da IA não fica na barra de menus. Usa o ícone do app instalado no seu Mac.",
        "Show in menu bar": "Mostrar na barra de menus",
        "Show": "Mostrar",
        "Source: %@": "Fonte: %@",
        "Spacing": "Espaçamento",
        "Status line integration": "Integração com a status line",
        "Status": "Estado",
        "Style": "Estilo",
        "System": "Sistema",
        "The Claude app saves your plan usage about every 5 minutes. AIquota reads only those percentages: no credentials, no network. This file format is undocumented and may change.":
            "O app Claude salva o uso do seu plano a cada 5 minutos, aproximadamente. O AIquota lê apenas esses percentuais: sem credenciais, sem rede. Este formato de arquivo não é documentado e pode mudar.",
        "Tip: Hold ⌘ Command and drag an AIquota indicator to place it next to your AI app.":
            "Dica: segure ⌘ Command e arraste um indicador do AIquota para colocá-lo ao lado do seu app de IA.",
        "Typography & shapes": "Tipografia e formas",
        "Updated %@ ago": "Atualizado há %@",
        "Updates": "Atualizações",
        "Used %": "% consumido",
        "Version %@": "Versão %@",
        "Waiting for data": "Aguardando dados",
        "Want Gemini, Copilot or Cursor? Providers are small adapters — contributions are welcome.":
            "Quer Gemini, Copilot ou Cursor? Provedores são pequenos adaptadores — contribuições são bem-vindas.",
        "Weekly limit": "Limite semanal",
        "Weekly window renewed": "Janela semanal renovada",
        "Welcome to AIquota": "Boas-vindas ao AIquota",
        "Windows": "Janelas",
        "Your AI tools": "Suas ferramentas de IA",
        "Your indicators": "Seus indicadores",
        "Your status line had already been changed; AIquota left it untouched.": "Sua status line já tinha sido alterada; o AIquota não a modificou.",
        "available": "disponível",
        "cached": "em cache",
        "expires %@": "expira %@",
        "macOS decides menu bar placement, so AIquota cannot move items automatically. Positions are remembered when possible.":
            "O macOS controla o posicionamento na barra de menus, então o AIquota não pode mover itens automaticamente. As posições são lembradas quando possível.",
        "may be outdated": "pode estar desatualizado",
        "no data": "sem dados",
        "settings.json is not valid JSON": "settings.json não é um JSON válido",
        "unofficial": "não oficial",
        "used": "consumido",
        // Provider states
        "Waiting for the next Claude Code response": "Aguardando a próxima resposta do Claude Code",
        "Open Claude, or enable the Claude Code status line integration": "Abra o Claude ou ative a integração com a status line do Claude Code",
        "Codex returned no usage windows for this account": "O Codex não retornou janelas de uso para esta conta",
        "Signed in with an API key. Subscription limits need a ChatGPT sign-in.": "Login feito com chave de API. Limites de assinatura exigem login com ChatGPT.",
        "Remove at any time from AIquota → Settings → Providers": "Remova quando quiser em AIquota → Configurações → Provedores",
        "Keep running your current status line command after AIquota reads the numbers": "Continuar executando seu comando de status line atual depois que o AIquota ler os números",
        "You have no status line today; Claude Code will show an empty one and hide some footer hints":
            "Você ainda não tem status line; o Claude Code mostrará uma vazia e ocultará algumas dicas do rodapé",
    ]
}
